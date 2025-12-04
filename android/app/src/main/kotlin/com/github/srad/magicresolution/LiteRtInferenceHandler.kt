package com.github.srad.magicresolution

import android.content.Context
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.graphics.Canvas
import com.google.android.gms.tflite.client.TfLiteInitializationOptions
import com.google.android.gms.tflite.gpu.support.TfLiteGpu
import com.google.android.gms.tflite.java.TfLite
import org.tensorflow.lite.gpu.GpuDelegateFactory
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.asCoroutineDispatcher
import kotlinx.coroutines.tasks.await
import kotlinx.coroutines.withContext
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import kotlinx.coroutines.ensureActive
import java.util.concurrent.Executors
import org.tensorflow.lite.InterpreterApi
import java.io.ByteArrayOutputStream
import java.nio.ByteBuffer
import java.nio.ByteOrder
import kotlin.math.ceil
import kotlin.math.max
import kotlin.math.min
import kotlin.math.roundToInt

enum class DelegateType {
    CPU,
    GPU
}

data class UpscaleResult(
    val imageBytes: ByteArray?,
    val error: String?,
    val outputWidth: Int = 0,
    val outputHeight: Int = 0
) {
    val success: Boolean get() = imageBytes != null && error == null
}

class LiteRtInferenceHandler(private val context: Context) {

    private var isInitialized = false
    private var gpuAvailable = false

    // Mutex to ensure exclusive access to the inference handler state (interpreters, buffers).
    // This prevents race conditions where a new upscale request (e.g. switching delegates)
    // tries to close an interpreter that is currently running in a cancelled but not-yet-finished task.
    private val mutex = Mutex()

    // Single-threaded executor for GPU operations (GPU delegate must run on same thread)
    private val gpuExecutor = Executors.newSingleThreadExecutor()
    private val gpuDispatcher = gpuExecutor.asCoroutineDispatcher()

    // Model constants (128x128 input -> 512x512 output, 4x upscale)
    // Real-ESRGAN-x4plus from https://huggingface.co/qualcomm/Real-ESRGAN-x4plus
    private val tileSize = 128
    private val outputTileSize = 512
    private val upscaleFactor = 4

    // Separate model buffers per delegate type to avoid cross-contamination
    // GPU delegate may modify the buffer in ways incompatible with CPU
    private var gpuModelBuffer: ByteBuffer? = null
    private var cpuModelBuffer: ByteBuffer? = null
    private var cachedModelSize: Int = 0

    // Cached tile buffers (separate per delegate to avoid sharing issues)
    private var gpuInputBuffer: ByteBuffer? = null
    private var gpuOutputBuffer: ByteBuffer? = null
    private var cpuInputBuffer: ByteBuffer? = null
    private var cpuOutputBuffer: ByteBuffer? = null

    // Separate interpreters per delegate type to avoid thread affinity issues
    // GPU interpreter must be used only from gpuDispatcher thread
    // CPU interpreter must be used only from Dispatchers.Default threads
    private var gpuInterpreter: InterpreterApi? = null
    private var cpuInterpreter: InterpreterApi? = null

    suspend fun initialize(): Boolean = withContext(Dispatchers.IO) {
        if (isInitialized) return@withContext true

        try {
            gpuAvailable = try {
                TfLiteGpu.isGpuDelegateAvailable(context).await()
            } catch (e: Exception) {
                false
            }

            val options = TfLiteInitializationOptions.builder()
                .setEnableGpuDelegateSupport(gpuAvailable)
                .build()

            TfLite.initialize(context, options).await()
            isInitialized = true
            true
        } catch (e: Exception) {
            android.util.Log.e("LiteRT", "Init failed", e)
            false
        }
    }

    fun isGpuAvailable(): Boolean = gpuAvailable

    suspend fun upscale(
        imageBytes: ByteArray,
        modelBytes: ByteArray,
        delegateType: DelegateType,
        maxInputDimension: Int,
        numThreads: Int,
        onProgress: ((current: Int, total: Int, message: String) -> Unit)? = null
    ): UpscaleResult = mutex.withLock {
        // Use single-threaded dispatcher for GPU (must run on same thread), Default for CPU
        val useGpu = delegateType == DelegateType.GPU && gpuAvailable
        val dispatcher = if (useGpu) gpuDispatcher else Dispatchers.Default

        // Enforce "One Active Interpreter": Close the inactive interpreter to free resources.
        // Critical: Close interpreters on their appropriate threads to avoid affinity crashes.
        if (useGpu) {
            // Switching to GPU: Ensure CPU interpreter is closed.
            // MUST close CPU resources on a CPU thread (IO or Default), NOT on the GPU thread.
            if (cpuInterpreter != null) {
                withContext(Dispatchers.IO) {
                    try {
                        cpuInterpreter?.close()
                    } catch (e: Exception) {
                        android.util.Log.e("LiteRT", "Error closing CPU interpreter", e)
                    }
                    cpuInterpreter = null
                    cpuModelBuffer = null
                    cpuInputBuffer = null
                    cpuOutputBuffer = null
                }
            }
        } else {
            // Switching to CPU: Ensure GPU interpreter is closed (must be on GPU thread) and buffers cleared.
            if (gpuInterpreter != null) {
                withContext(gpuDispatcher) {
                    try {
                        gpuInterpreter?.close()
                    } catch (e: Exception) {
                        android.util.Log.e("LiteRT", "Error closing GPU interpreter", e)
                    }
                    gpuInterpreter = null
                    gpuModelBuffer = null
                    gpuInputBuffer = null
                    gpuOutputBuffer = null
                }
            }
        }

        return@withLock withContext(dispatcher) {
            if (!isInitialized) {
                return@withContext UpscaleResult(null, "LiteRT not initialized")
            }

            try {
                // Check if model changed
                if (modelBytes.size != cachedModelSize) {
                    android.util.Log.d("LiteRT", "Model changed, resetting current interpreter")
                    // Only need to reset the CURRENT interpreter, as the other is guaranteed closed above.
                    if (useGpu) {
                        // We are on GPU thread
                        gpuInterpreter?.close()
                        gpuInterpreter = null
                        gpuModelBuffer = null
                        gpuInputBuffer = null
                        gpuOutputBuffer = null
                    } else {
                        // We are on CPU thread (Default)
                        cpuInterpreter?.close()
                        cpuInterpreter = null
                        cpuModelBuffer = null
                        cpuInputBuffer = null
                        cpuOutputBuffer = null
                    }
                    cachedModelSize = modelBytes.size
                }

                // Decode input image
                val originalBitmap = BitmapFactory.decodeByteArray(imageBytes, 0, imageBytes.size)
                    ?: return@withContext UpscaleResult(null, "Failed to decode image")

                // Resize if needed (cap at maxInputDimension)
                val inputBitmap = resizeIfNeeded(originalBitmap, maxInputDimension)
                val inputWidth = inputBitmap.width
                val inputHeight = inputBitmap.height

                android.util.Log.d("LiteRT", "Input image: ${inputWidth}x${inputHeight}")

                // Get or create interpreter for the specific delegate
                val interpreter: InterpreterApi = if (useGpu) {
                    if (gpuModelBuffer == null) {
                        val buffer = ByteBuffer.allocateDirect(modelBytes.size)
                            .order(ByteOrder.nativeOrder())
                        buffer.put(modelBytes)
                        buffer.rewind()
                        gpuModelBuffer = buffer
                    } else {
                        gpuModelBuffer!!.rewind()
                    }

                    if (gpuInterpreter == null) {
                        android.util.Log.d("LiteRT", "Creating GPU interpreter")
                        val options = InterpreterApi.Options()
                            .setRuntime(InterpreterApi.Options.TfLiteRuntime.FROM_SYSTEM_ONLY)
                            .addDelegateFactory(GpuDelegateFactory())
                        val interp = InterpreterApi.create(gpuModelBuffer!!, options)
                        interp.allocateTensors()
                        gpuInterpreter = interp
                    }
                    gpuInterpreter!!
                } else {
                    if (cpuModelBuffer == null) {
                        val buffer = ByteBuffer.allocateDirect(modelBytes.size)
                            .order(ByteOrder.nativeOrder())
                        buffer.put(modelBytes)
                        buffer.rewind()
                        cpuModelBuffer = buffer
                    } else {
                        cpuModelBuffer!!.rewind()
                    }

                    if (cpuInterpreter == null) {
                        android.util.Log.d("LiteRT", "Creating CPU interpreter with $numThreads threads")
                        val options = InterpreterApi.Options()
                            .setRuntime(InterpreterApi.Options.TfLiteRuntime.FROM_SYSTEM_ONLY)
                            .setNumThreads(numThreads)
                        val interp = InterpreterApi.create(cpuModelBuffer!!, options)
                        interp.allocateTensors()
                        cpuInterpreter = interp
                    }
                    cpuInterpreter!!
                }

                // Calculate number of tiles needed
                val tilesX = ceil(inputWidth.toFloat() / tileSize).toInt()
                val tilesY = ceil(inputHeight.toFloat() / tileSize).toInt()
                val totalTiles = tilesX * tilesY

                android.util.Log.d("LiteRT", "Processing $totalTiles tiles (${tilesX}x${tilesY})")
                onProgress?.invoke(0, totalTiles, "Starting upscale...")

                // Create output bitmap (4x upscaled)
                val outputWidth = inputWidth * upscaleFactor
                val outputHeight = inputHeight * upscaleFactor
                val outputBitmap =
                    Bitmap.createBitmap(outputWidth, outputHeight, Bitmap.Config.ARGB_8888)
                val canvas = Canvas(outputBitmap)

                // Get or create tile buffers (cached per delegate to avoid sharing)
                val inputBuffer: ByteBuffer
                val outputBuffer: ByteBuffer

                if (useGpu) {
                    if (gpuInputBuffer == null) {
                         gpuInputBuffer = ByteBuffer.allocateDirect(4 * tileSize * tileSize * 3)
                            .order(ByteOrder.nativeOrder())
                    }
                    if (gpuOutputBuffer == null) {
                        gpuOutputBuffer = ByteBuffer.allocateDirect(4 * outputTileSize * outputTileSize * 3)
                            .order(ByteOrder.nativeOrder())
                    }
                    inputBuffer = gpuInputBuffer!!
                    outputBuffer = gpuOutputBuffer!!
                } else {
                     if (cpuInputBuffer == null) {
                         cpuInputBuffer = ByteBuffer.allocateDirect(4 * tileSize * tileSize * 3)
                            .order(ByteOrder.nativeOrder())
                    }
                    if (cpuOutputBuffer == null) {
                        cpuOutputBuffer = ByteBuffer.allocateDirect(4 * outputTileSize * outputTileSize * 3)
                            .order(ByteOrder.nativeOrder())
                    }
                    inputBuffer = cpuInputBuffer!!
                    outputBuffer = cpuOutputBuffer!!
                }

                var tilesProcessed = 0
                val startTime = System.currentTimeMillis()

                // Process each tile
                for (tileY in 0 until tilesY) {
                    for (tileX in 0 until tilesX) {
                        ensureActive() // Check for cancellation

                        val srcX = tileX * tileSize
                        val srcY = tileY * tileSize

                        // Handle edge tiles (may be smaller than tileSize)
                        val actualWidth = min(tileSize, inputWidth - srcX)
                        val actualHeight = min(tileSize, inputHeight - srcY)

                        // Extract tile (pad with edge pixels if needed)
                        val tileBitmap = extractTile(inputBitmap, srcX, srcY, actualWidth, actualHeight)

                        // Convert tile to input buffer
                        fillInputBuffer(inputBuffer, tileBitmap)
                        inputBuffer.rewind()
                        outputBuffer.rewind()

                        // Run inference on tile
                        interpreter.run(inputBuffer, outputBuffer)
                        outputBuffer.rewind()

                        // Convert output buffer to bitmap
                        val outputTileBitmap =
                            bufferToBitmap(outputBuffer, outputTileSize, outputTileSize)

                        // Calculate output position
                        val dstX = tileX * outputTileSize
                        val dstY = tileY * outputTileSize

                        // Draw tile to output (crop if edge tile)
                        val cropWidth = actualWidth * upscaleFactor
                        val cropHeight = actualHeight * upscaleFactor

                        if (cropWidth < outputTileSize || cropHeight < outputTileSize) {
                            // Edge tile - need to crop
                            val croppedTile =
                                Bitmap.createBitmap(outputTileBitmap, 0, 0, cropWidth, cropHeight)
                            canvas.drawBitmap(croppedTile, dstX.toFloat(), dstY.toFloat(), null)
                            croppedTile.recycle()
                        } else {
                            canvas.drawBitmap(outputTileBitmap, dstX.toFloat(), dstY.toFloat(), null)
                        }

                        outputTileBitmap.recycle()
                        tileBitmap.recycle()

                        tilesProcessed++
                        onProgress?.invoke(
                            tilesProcessed,
                            totalTiles,
                            "Processing tile $tilesProcessed/$totalTiles"
                        )

                        if (tilesProcessed % 10 == 0) {
                            android.util.Log.d("LiteRT", "Progress: $tilesProcessed/$totalTiles tiles")
                        }
                    }
                }

                val elapsed = System.currentTimeMillis() - startTime
                android.util.Log.d("LiteRT", "Complete: ${outputWidth}x${outputHeight} in ${elapsed}ms")
                onProgress?.invoke(totalTiles, totalTiles, "Encoding image...")

                // Encode as PNG
                val outputStream = ByteArrayOutputStream()
                outputBitmap.compress(Bitmap.CompressFormat.PNG, 100, outputStream)
                val resultBytes = outputStream.toByteArray()

                // Cleanup
                if (inputBitmap != originalBitmap) inputBitmap.recycle()
                originalBitmap.recycle()
                outputBitmap.recycle()

                UpscaleResult(
                    imageBytes = resultBytes,
                    error = null,
                    outputWidth = outputWidth,
                    outputHeight = outputHeight
                )
            } catch (e: Exception) {
                android.util.Log.e("LiteRT", "Error", e)
                // On error, invalidate the current interpreter and buffers
                if (useGpu) {
                    gpuInterpreter?.close()
                    gpuInterpreter = null
                    gpuModelBuffer = null
                    gpuInputBuffer = null
                    gpuOutputBuffer = null
                } else {
                    cpuInterpreter?.close()
                    cpuInterpreter = null
                    cpuModelBuffer = null
                    cpuInputBuffer = null
                    cpuOutputBuffer = null
                }
                UpscaleResult(null, "Error: ${e.message}")
            }
        }
    }

    /**
     * Release all cached resources. Call this when the handler is no longer needed.
     */
    fun release() {
        // Close CPU resources on IO thread
        try {
             // We can't launch a coroutine here easily as this might be called from onDestroy
             // So we try to close it directly, but if it was created on a thread with TLS, this might be an issue.
             // Ideally, we should have a dedicated CPU executor too, but Dispatchers.Default is a pool.
             // Given the crash, let's try to close it and catch any issues.
             cpuInterpreter?.close()
        } catch (e: Exception) {
             android.util.Log.e("LiteRT", "Error releasing CPU resources", e)
        }
        cpuInterpreter = null
        cpuModelBuffer = null
        cpuInputBuffer = null
        cpuOutputBuffer = null

        // Close GPU resources on GPU thread
        try {
            gpuExecutor.submit {
                gpuInterpreter?.close()
                gpuInterpreter = null
                gpuModelBuffer = null
                gpuInputBuffer = null
                gpuOutputBuffer = null
            }
        } catch (e: Exception) {
            android.util.Log.e("LiteRT", "Error releasing GPU resources", e)
        }

        cachedModelSize = 0
        android.util.Log.d("LiteRT", "Released all cached resources")
    }

    private fun resizeIfNeeded(bitmap: Bitmap, maxDimension: Int): Bitmap {
        val width = bitmap.width
        val height = bitmap.height

        if (width <= maxDimension && height <= maxDimension) {
            return bitmap
        }

        val scale = maxDimension.toFloat() / max(width, height)
        val newWidth = (width * scale).roundToInt()
        val newHeight = (height * scale).roundToInt()

        return Bitmap.createScaledBitmap(bitmap, newWidth, newHeight, true)
    }

    private fun extractTile(bitmap: Bitmap, x: Int, y: Int, width: Int, height: Int): Bitmap {
        // Create a tile of exactly tileSize x tileSize, padding with edge pixels if needed
        val tile = Bitmap.createBitmap(tileSize, tileSize, Bitmap.Config.ARGB_8888)
        val canvas = Canvas(tile)

        // Extract the available portion
        val srcBitmap = Bitmap.createBitmap(bitmap, x, y, width, height)
        canvas.drawBitmap(srcBitmap, 0f, 0f, null)

        // Pad right edge if needed
        if (width < tileSize) {
            for (px in width until tileSize) {
                for (py in 0 until height) {
                    tile.setPixel(px, py, srcBitmap.getPixel(width - 1, py))
                }
            }
        }

        // Pad bottom edge if needed
        if (height < tileSize) {
            for (py in height until tileSize) {
                for (px in 0 until tileSize) {
                    val srcPx = min(px, width - 1)
                    tile.setPixel(px, py, srcBitmap.getPixel(srcPx, height - 1))
                }
            }
        }

        srcBitmap.recycle()
        return tile
    }

    private fun fillInputBuffer(buffer: ByteBuffer, bitmap: Bitmap) {
        buffer.rewind()
        val pixels = IntArray(tileSize * tileSize)
        bitmap.getPixels(pixels, 0, tileSize, 0, 0, tileSize, tileSize)

        for (pixel in pixels) {
            // Normalize to 0-1 range for Real-ESRGAN
            buffer.putFloat(((pixel shr 16) and 0xFF) / 255.0f) // R
            buffer.putFloat(((pixel shr 8) and 0xFF) / 255.0f)  // G
            buffer.putFloat((pixel and 0xFF) / 255.0f)          // B
        }
    }

    private fun bufferToBitmap(buffer: ByteBuffer, width: Int, height: Int): Bitmap {
        val bitmap = Bitmap.createBitmap(width, height, Bitmap.Config.ARGB_8888)
        val pixels = IntArray(width * height)

        for (i in pixels.indices) {
            // Output is 0-1 range, scale back to 0-255
            val r = min(255, max(0, (buffer.float * 255.0f).roundToInt()))
            val g = min(255, max(0, (buffer.float * 255.0f).roundToInt()))
            val b = min(255, max(0, (buffer.float * 255.0f).roundToInt()))
            pixels[i] = (0xFF shl 24) or (r shl 16) or (g shl 8) or b
        }

        bitmap.setPixels(pixels, 0, width, 0, 0, width, height)
        return bitmap
    }
}
