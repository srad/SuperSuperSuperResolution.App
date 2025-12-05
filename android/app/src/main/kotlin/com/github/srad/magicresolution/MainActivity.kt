package com.github.srad.magicresolution

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancel
import kotlinx.coroutines.launch
import java.util.concurrent.CancellationException

class MainActivity : FlutterActivity() {
    companion object {
        private const val METHOD_CHANNEL = "com.github.srad.magicresolution/litert"
        private const val EVENT_CHANNEL = "com.github.srad.magicresolution/progress"
    }

    private lateinit var inferenceHandler: LiteRtInferenceHandler
    private val scope = CoroutineScope(Dispatchers.Main + SupervisorJob())
    private var progressSink: EventChannel.EventSink? = null
    private var currentJob: Job? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        inferenceHandler = LiteRtInferenceHandler(this)

        // Event channel for progress updates
        EventChannel(flutterEngine.dartExecutor.binaryMessenger, EVENT_CHANNEL).setStreamHandler(
            object : EventChannel.StreamHandler {
                override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
                    progressSink = events
                }

                override fun onCancel(arguments: Any?) {
                    progressSink = null
                }
            }
        )

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, METHOD_CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "initialize" -> {
                    scope.launch {
                        val success = inferenceHandler.initialize()
                        result.success(mapOf(
                            "success" to success,
                            "gpuAvailable" to inferenceHandler.isGpuAvailable()
                        ))
                    }
                }

                "cancel" -> {
                    currentJob?.cancel()
                    currentJob = null
                    result.success(true)
                }

                "upscale" -> {
                    val imageBytes = call.argument<ByteArray>("imageBytes")
                    val modelBytes = call.argument<ByteArray>("modelBytes")
                    val delegateType = call.argument<String>("delegateType") ?: "CPU"
                    val maxInputDimension = call.argument<Int>("maxInputDimension") ?: 2024
                    val numThreads = call.argument<Int>("numThreads") ?: 4

                    if (imageBytes == null || modelBytes == null) {
                        result.error("INVALID_ARGS", "imageBytes and modelBytes are required", null)
                        return@setMethodCallHandler
                    }

                    // Cancel any previous job
                    currentJob?.cancel()

                    val job = scope.launch {
                        try {
                            val upscaleResult = inferenceHandler.upscale(
                                imageBytes = imageBytes,
                                modelBytes = modelBytes,
                                delegateType = if (delegateType == "GPU") DelegateType.GPU else DelegateType.CPU,
                                maxInputDimension = maxInputDimension,
                                numThreads = numThreads,
                                onProgress = { current, total, message ->
                                    scope.launch(Dispatchers.Main) {
                                        progressSink?.success(mapOf(
                                            "current" to current,
                                            "total" to total,
                                            "message" to message
                                        ))
                                    }
                                }
                            )

                            if (upscaleResult.success) {
                                result.success(mapOf(
                                    "success" to true,
                                    "outputFilePath" to upscaleResult.outputFilePath,
                                    "outputWidth" to upscaleResult.outputWidth,
                                    "outputHeight" to upscaleResult.outputHeight
                                ))
                            } else {
                                result.success(mapOf(
                                    "success" to false,
                                    "error" to upscaleResult.error
                                ))
                            }
                        } catch (e: CancellationException) {
                            // Job cancelled, do not return result as it might crash if result.success is called twice or on a dead channel
                            // Or we can return an error.
                            // result.error("CANCELLED", "Task cancelled", null)
                        }
                    }
                    currentJob = job
                }

                "isGpuAvailable" -> {
                    result.success(inferenceHandler.isGpuAvailable())
                }

                else -> {
                    result.notImplemented()
                }
            }
        }
    }

    override fun onDestroy() {
        scope.cancel()
        super.onDestroy()
    }
}
