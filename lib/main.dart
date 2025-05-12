import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:supersupersuperresolution/utils/file_utils.dart';
import 'package:supersupersuperresolution/utils/image_utils.dart';
import 'package:tflite_flutter/tflite_flutter.dart';
import 'package:image/image.dart' as img_lib;

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  // This widget is the root of your application.
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'SuperSuperSuperResolution AI Upscaler',
      theme: ThemeData(
        // This is the theme of your application.
        //
        // TRY THIS: Try running your application with "flutter run". You'll see
        // the application has a purple toolbar. Then, without quitting the app,
        // try changing the seedColor in the colorScheme below to Colors.green
        // and then invoke "hot reload" (save your changes or press the "hot
        // reload" button in a Flutter-supported IDE, or press "r" if you used
        // the command line to start the app).
        //
        // Notice that the counter didn't reset back to zero; the application
        // state is not lost during the reload. To reset the state, use hot
        // restart instead.
        //
        // This works for code too, not just values: Most code changes can be
        // tested with just a hot reload.
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.indigoAccent),
      ),
      home: const MyHomePage(title: 'SSSR AI Upscaler'),
    );
  }
}

class MyHomePage extends StatefulWidget {
  const MyHomePage({super.key, required this.title});

  final String title;

  @override
  State<MyHomePage> createState() => _MyHomePageState();
}

class _MyHomePageState extends State<MyHomePage> {
  late Interpreter _interpreter;
  img_lib.Image? _processedImage;
  bool _isLoading = false;
  File? _selectedImage;

  @override
  void initState() {
    // TODO: implement initState
    super.initState();
    loadModel();
  }

  Future<void> pickImage() async {
    final image = await FileUtils.pickImage(context);

    if (image != null) {
      setState(() {
        _selectedImage = File(image.path);
      });
    }
  }

  @override
  void dispose() {
    _interpreter.close();
    super.dispose();
  }

  Future<void> loadModel() async {
    try {
      _isLoading = true;
      _interpreter = await Interpreter.fromAsset('assets/models/esrgan.tflite'); // Or your model's filename
      debugPrint('Interpreter loaded successfully');
    } catch (e) {
      debugPrint('Failed to load model: $e');
    } finally {
      _isLoading = false;
    }
  }

  Future<void> _processImage() async {
    if (_selectedImage == null) return;

    setState(() {
      _isLoading = true;
      _processedImage = null; // Clear previous result
    });

    try {
      final inputTensor = await ImageUtils.preprocessImage(_selectedImage!);
      final outputTensorData = await runSuperResolution(inputTensor); // This function would call _interpreter.run
      if (outputTensorData != null) {
        // Assuming runSuperResolution now directly returns the img_lib.Image
        setState(() {
          _processedImage = outputTensorData;
        });
      } else {
        // Handle error: show a snackbar or message
        debugPrint("Super resolution failed.");
      }
    } catch (e) {
      debugPrint("Error during processing: $e");
      // Handle error
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  Future<img_lib.Image?> runSuperResolution(List<List<List<List<double>>>> inputTensor) async {
    if (_interpreter == null) {
      debugPrint('Interpreter not initialized.');
      return null;
    }

    // Define the output tensor based on the model's output shape
    // Example: If model outputs a 200x200 RGB image
    var outputShape = _interpreter.getOutputTensor(0).shape; // e.g., [1, 200, 200, 3]
    var outputType = _interpreter.getOutputTensor(0).type; // e.g., TfLiteType.float32

    // Allocate output tensor
    // Adjust the nested list structure based on your outputShape and outputType
    var outputTensor = List.generate(
      outputShape[0], // Batch size
          (b) => List.generate(
        outputShape[1], // Height
            (h) => List.generate(
          outputShape[2], // Width
              (w) => List.filled(outputShape[3], 0.0), // Channels, initialized to 0.0 for float32
        ),
      ),
    );


    try {
      _interpreter.run(inputTensor, outputTensor);

      // Post-process the output tensor to an image
      return postprocessOutput(outputTensor, outputShape);
    } catch (e) {
      debugPrint('Error running model inference: $e');
      return null;
    }
  }

  // Example postprocessing function (adapt based on your model's output)
  img_lib.Image? postprocessOutput(List<dynamic> outputTensor, List<int> outputShape) {
    // Assuming outputTensor is [1, height, width, 3] and values are [0,1] floats
    int height = outputShape[1];
    int width = outputShape[2];
    int channels = outputShape[3];

    var processedOutput = outputTensor[0] as List<List<List<double>>>;
    var outputImage = img_lib.Image(width: width, height: height);

    for (int y = 0; y < height; y++) {
      for (int x = 0; x < width; x++) {
        double r = processedOutput[y][x][0];
        double g = processedOutput[y][x][1];
        double b = processedOutput[y][x][2];

        // Denormalize if necessary (e.g., multiply by 255) and clamp
        int red = (r * 255.0).clamp(0, 255).toInt();
        int green = (g * 255.0).clamp(0, 255).toInt();
        int blue = (b * 255.0).clamp(0, 255).toInt();

        outputImage.setPixelRgba(x, y, red, green, blue, 255);
      }
    }
    return outputImage;
  }

  @override
  Widget build(BuildContext context) {
    // This method is rerun every time setState is called, for instance as done
    // by the _incrementCounter method above.
    //
    // The Flutter framework has been optimized to make rerunning build methods
    // fast, so that you can just rebuild anything that needs updating rather
    // than having to individually change instances of widgets.
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
        title: Text(widget.title),
      ),
      body: Center(
        child: Column(
          children: [
            if (_selectedImage != null) Stack(children: [
              Image.file(_selectedImage!),
              const Center(child: Text('Input', style: TextStyle(color: Colors.white, fontSize: 25))),//
            ]),
            ElevatedButton(onPressed: pickImage, child: Text('Pick Image')),
            ElevatedButton(onPressed: _processImage, child: Text('Enhance Image')),
            if (_isLoading) CircularProgressIndicator(),
            if (_processedImage != null) Image.memory(Uint8List.fromList(img_lib.encodePng(_processedImage!))),
            if (_processedImage != null) ElevatedButton(onPressed: () => saveProcessedImage(_processedImage), child: Text('Save')),
          ],
        )
      ),
    );
  }

  Future<void> saveProcessedImage(img_lib.Image? imageToSave) async {
    if (imageToSave == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No processed image to save.')),
      );
      return;
    }

    // 1. Encode the image (choose PNG or JPG)
    // PNG is lossless but results in larger files.
    // JPG is lossy but results in smaller files. You can specify quality.
    Uint8List? encodedBytes;
    String fileExtension;
    String mimeType;

    // Let's choose PNG for this example for max quality
    encodedBytes = Uint8List.fromList(img_lib.encodePng(imageToSave));
    fileExtension = 'png';
    mimeType = 'image/png';

    // Alternatively, for JPG:
    // encodedBytes = Uint8List.fromList(img_lib.encodeJpg(imageToSave, quality: 90)); // Quality 0-100
    // fileExtension = 'jpg';
    // mimeType = 'image/jpeg';

    if (encodedBytes == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Error encoding image.')),
      );
      return;
    }

    try {
      // 2. Get a directory
      // For saving to app's document directory (private to the app)
      final directory = await getApplicationDocumentsDirectory();
      final String fileName = 'super_resolution_${DateTime.now().millisecondsSinceEpoch}.$fileExtension';
      final String filePath = '${directory.path}/$fileName';

      // 3. Create the file and write bytes
      final File imageFile = File(filePath);
      await imageFile.writeAsBytes(encodedBytes);

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Image saved to: $filePath')),
      );
      print('Image saved to: $filePath');

      // 4. (Optional) Save to device gallery (requires permissions)
      // This is a common user expectation.
      // You might want to ask the user if they want to save to gallery.
      // await _saveToGallery(context, imageFile, fileName, mimeType);

    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error saving image: $e')),
      );
      print('Error saving image: $e');
    }
  }

// Optional: Helper function to save to gallery
// This uses the permission_handler plugin.
// For a more robust gallery saving experience, consider `image_gallery_saver` plugin
// which handles some platform complexities.
  Future<void> _saveToGallery(BuildContext context, File imageFile, String fileName, String mimeType) async {
    // Check and request storage permissions
    // For Android 33+ (SDK Tiramisu), use Permissions.photos if saving only to photo gallery
    // For older Android, or broader storage, use Permissions.storage or manageExternalStorage
    PermissionStatus status;
    if (Platform.isAndroid) {
      // This is a simplified check. For Android 13+, you might request Permission.photos
      // For Android 10-12 with scoped storage, saving to public directories is more complex.
      // `image_gallery_saver` plugin often handles these nuances better.
      status = await Permission.storage.request();
    } else if (Platform.isIOS) {
      status = await Permission.photos.request(); // or photosAddOnly
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Gallery saving not supported on this platform.')),
      );
      return;
    }

    if (status.isGranted) {
      try {
        // For a more direct approach to gallery, consider image_gallery_saver.
        // This is a basic example trying to use path_provider's external directories.
        // NOTE: getExternalStorageDirectory() might be null or restricted on some platforms/OS versions.
        Directory? externalDir = await getExternalStorageDirectory(); // Or getExternalStorageDirectories(type: StorageDirectory.pictures).first
        if (externalDir == null) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Could not access external storage for gallery.')),
          );
          return;
        }

        // Create a path in a common public directory like Pictures
        // Be mindful of platform-specific conventions and Scoped Storage on Android.
        final String galleryPath = '${externalDir.path}/Pictures/$fileName'; // Example path
        final File galleryFile = File(galleryPath);

        // Ensure the directory exists
        await galleryFile.parent.create(recursive: true);

        // Copy the file from app's private storage (if saved there first) or write directly
        await imageFile.copy(galleryPath); // If imageFile is from app documents
        // OR if you haven't saved it yet:
        // await galleryFile.writeAsBytes(encodedBytesFromAbove);

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Image also copied to gallery (experimental): $galleryPath')),
        );
        print('Image copied to gallery (experimental): $galleryPath');

        // To make it immediately visible in Android Gallery, you might need to use MediaScanner
        // This is where plugins like `image_gallery_saver` shine.
        // image_gallery_saver.ImageGallerySaver.saveFile(imageFile.path);


      } catch (e) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error copying to gallery: $e')),
        );
        print('Error copying to gallery: $e');
      }
    } else if (status.isDenied || status.isPermanentlyDenied) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('Storage permission denied. Cannot save to gallery.'),
          action: SnackBarAction(
            label: 'Settings',
            onPressed: () {
              openAppSettings();
            },
          ),
        ),
      );
    }
  }
}
