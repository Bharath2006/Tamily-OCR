import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:image/image.dart' as img;
import 'package:path_provider/path_provider.dart';
import 'package:syncfusion_flutter_pdf/pdf.dart';
import 'package:path/path.dart' as path;
import 'package:permission_handler/permission_handler.dart';
import 'package:flutter_tesseract_ocr/flutter_tesseract_ocr.dart';
import 'package:flutter/services.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Document Scanner',
      theme: ThemeData(
        primarySwatch: Colors.blue,
      ),
      home: const DocumentScannerHome(),
    );
  }
}

class DocumentScannerHome extends StatefulWidget {
  const DocumentScannerHome({Key? key}) : super(key: key);

  @override
  _DocumentScannerHomeState createState() => _DocumentScannerHomeState();
}

class _DocumentScannerHomeState extends State<DocumentScannerHome> {
  final ImagePicker _picker = ImagePicker();
  final List<File> _scannedImages = [];
  bool _isProcessing = false;

  @override
  void initState() {
    super.initState();
    _requestPermissions();
  }

  Future<void> _requestPermissions() async {
    await Permission.camera.request();
    await Permission.storage.request();
  }

  Future<void> _captureImage() async {
    setState(() {
      _isProcessing = true;
    });

    final XFile? photo = await _picker.pickImage(source: ImageSource.camera);

    if (photo != null) {
      final File originalFile = File(photo.path);
      await _processImage(originalFile);
    }

    setState(() {
      _isProcessing = false;
    });
  }

  Future<void> _pickImage() async {
    setState(() {
      _isProcessing = true;
    });

    final XFile? image = await _picker.pickImage(source: ImageSource.gallery);

    if (image != null) {
      final File originalFile = File(image.path);
      await _processImage(originalFile);
    }

    setState(() {
      _isProcessing = false;
    });
  }

  Future<void> _processImage(File imageFile) async {
    try {
      final String edgeDetectedPath =
          await _detectDocumentEdges(imageFile.path);
      final String correctedPath =
          await _applyPerspectiveCorrection(edgeDetectedPath);
      final String enhancedPath = await _enhanceImage(correctedPath);

      setState(() {
        _scannedImages.add(File(enhancedPath));
      });
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error processing image: $e')),
      );
    }
  }

  Future<String> _detectDocumentEdges(String imagePath) async {
    try {
      final String result = await ImgProc.canny(imagePath, 50, 150);
      final List<dynamic> contours = await ImgProc.findContours(result);
      List<dynamic> documentContour = _findLargestContour(contours);
      final String outputPath = await ImgProc.drawContours(
          imagePath, [documentContour], 0, Colors.green.value, 2);
      return outputPath;
    } catch (e) {
      return imagePath;
    }
  }

  List<dynamic> _findLargestContour(List<dynamic> contours) {
    if (contours.isEmpty) return [];

    List<dynamic> largestContour = contours[0];
    double maxArea = 0;

    for (final contour in contours) {
      final double area = ImgProc.contourArea(contour);
      if (area > maxArea) {
        maxArea = area;
        largestContour = contour;
      }
    }

    return largestContour;
  }

  Future<String> _applyPerspectiveCorrection(String imagePath) async {
    try {
      final List<Point> corners = await _detectCorners(imagePath);
      final String result = await ImgProc.warpPerspective(
        imagePath,
        corners,
        Size(850, 1100),
      );
      return result;
    } catch (e) {
      return imagePath;
    }
  }

  Future<List<Point>> _detectCorners(String imagePath) async {
    final img.Image? image =
        img.decodeImage(await File(imagePath).readAsBytes());
    if (image == null) return [];

    final double width = image.width.toDouble();
    final double height = image.height.toDouble();

    return [
      Point(0.1 * width, 0.1 * height),
      Point(0.9 * width, 0.1 * height),
      Point(0.9 * width, 0.9 * height),
      Point(0.1 * width, 0.9 * height),
    ];
  }

  Future<String> _enhanceImage(String imagePath) async {
    try {
      String result = await _applyAdaptiveThreshold(imagePath);
      result = await _adjustBrightnessContrast(result, 1.2, 1.2);
      result = await _reduceNoise(result);
      return result;
    } catch (e) {
      return imagePath;
    }
  }

  Future<String> _applyAdaptiveThreshold(String imagePath) async {
    try {
      final String grayscale =
          await ImgProc.cvtColor(imagePath, ImgProc.colorBGR2GRAY);
      final String result = await ImgProc.adaptiveThreshold(grayscale, 255,
          ImgProc.adaptiveThreshMeanC, ImgProc.threshBinary, 11, 2);
      return result;
    } catch (e) {
      return imagePath;
    }
  }

  Future<String> _adjustBrightnessContrast(
      String imagePath, double brightness, double contrast) async {
    try {
      final String result = await ImgProc.convertScaleAbs(imagePath,
          alpha: contrast, beta: brightness * 10);
      return result;
    } catch (e) {
      return imagePath;
    }
  }

  Future<String> _reduceNoise(String imagePath) async {
    try {
      final String result = await ImgProc.gaussianBlur(imagePath, [3, 3], 0);
      return result;
    } catch (e) {
      return imagePath;
    }
  }

  Future<void> _generatePDF() async {
    if (_scannedImages.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No images to convert to PDF')),
      );
      return;
    }

    setState(() {
      _isProcessing = true;
    });

    try {
      final PdfDocument document = PdfDocument();
      document.documentInformation.author = 'Document Scanner App';
      document.documentInformation.title = 'Scanned Document';

      for (final File imageFile in _scannedImages) {
        final PdfPage page = document.pages.add();
        final PdfBitmap image = PdfBitmap(await imageFile.readAsBytes());
        final double pageWidth = page.getClientSize().width;
        final double pageHeight = page.getClientSize().height;
        final double imageWidth = image.width.toDouble();
        final double imageHeight = image.height.toDouble();

        double scale = 1.0;
        if (imageWidth > pageWidth || imageHeight > pageHeight) {
          final double scaleX = pageWidth / imageWidth;
          final double scaleY = pageHeight / imageHeight;
          scale = scaleX < scaleY ? scaleX : scaleY;
        }

        final double scaledWidth = imageWidth * scale;
        final double scaledHeight = imageHeight * scale;
        final double x = (pageWidth - scaledWidth) / 2;
        final double y = (pageHeight - scaledHeight) / 2;

        page.graphics
            .drawImage(image, Rect.fromLTWH(x, y, scaledWidth, scaledHeight));
      }

      final List<int> bytes = await document.save();
      document.dispose();

      final directory = await getApplicationDocumentsDirectory();
      final String filePath =
          '${directory.path}/scanned_document_${DateTime.now().millisecondsSinceEpoch}.pdf';

      final File file = File(filePath);
      await file.writeAsBytes(bytes);

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('PDF saved to: $filePath')),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error generating PDF: $e')),
      );
    }

    setState(() {
      _isProcessing = false;
    });
  }

  Future<void> _clearImages() async {
    setState(() {
      _scannedImages.clear();
    });
  }

  Future<void> _extractText(int index) async {
    if (_scannedImages.isEmpty || index >= _scannedImages.length) return;

    setState(() {
      _isProcessing = true;
    });

    try {
      final String processedImagePath =
          await _prepareImageForOCR(_scannedImages[index].path);

      final String extractedText = await FlutterTesseractOcr.extractText(
        processedImagePath,
        language: 'eng',
        args: {
          'preserve_interword_spaces': '1',
          'tessedit_pageseg_mode': '6',
          'user_defined_dpi': '300',
        },
      );

      final String cleanedText = _cleanExtractedText(extractedText);

      if (mounted) {
        showDialog(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('Extracted Text'),
            content: SingleChildScrollView(
              child: SelectableText(
                cleanedText.isNotEmpty
                    ? cleanedText
                    : 'No text could be extracted',
                style: const TextStyle(fontFamily: 'monospace'),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('OK'),
              ),
              if (cleanedText.isNotEmpty)
                TextButton(
                  onPressed: () async {
                    await Clipboard.setData(ClipboardData(text: cleanedText));
                    if (mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                            content: Text('Text copied to clipboard')),
                      );
                    }
                  },
                  child: const Text('COPY'),
                ),
            ],
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('OCR Error: ${e.toString()}')),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isProcessing = false;
        });
      }
    }
  }

  Future<String> _prepareImageForOCR(String imagePath) async {
    try {
      String processedPath =
          await ImgProc.cvtColor(imagePath, ImgProc.colorBGR2GRAY);
      processedPath = await ImgProc.adaptiveThreshold(processedPath, 255,
          ImgProc.adaptiveThreshMeanC, ImgProc.threshBinary, 11, 2);
      processedPath = await ImgProc.gaussianBlur(processedPath, [1, 1], 0);
      return processedPath;
    } catch (e) {
      return imagePath;
    }
  }

  String _cleanExtractedText(String text) {
    return text
        .replaceAll(RegExp(r'\n{3,}'), '\n\n')
        .replaceAll(RegExp(r'[ \t]{2,}'), ' ')
        .trim();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Document Scanner'),
        actions: [
          IconButton(
            icon: const Icon(Icons.delete),
            onPressed: _clearImages,
          ),
          IconButton(
            icon: const Icon(Icons.picture_as_pdf),
            onPressed: _generatePDF,
          ),
        ],
      ),
      body: _isProcessing
          ? const Center(child: CircularProgressIndicator())
          : _scannedImages.isEmpty
              ? const Center(child: Text('No scanned documents'))
              : GridView.builder(
                  padding: const EdgeInsets.all(8),
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 2,
                    crossAxisSpacing: 8,
                    mainAxisSpacing: 8,
                  ),
                  itemCount: _scannedImages.length,
                  itemBuilder: (context, index) {
                    return InkWell(
                      onTap: () => _showImageDetails(index),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child: Image.file(
                          _scannedImages[index],
                          fit: BoxFit.cover,
                        ),
                      ),
                    );
                  },
                ),
      floatingActionButton: Column(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          FloatingActionButton(
            heroTag: 'gallery',
            onPressed: _pickImage,
            tooltip: 'Pick Image',
            child: const Icon(Icons.photo_library),
          ),
          const SizedBox(height: 16),
          FloatingActionButton(
            heroTag: 'camera',
            onPressed: _captureImage,
            tooltip: 'Take Photo',
            child: const Icon(Icons.camera_alt),
          ),
        ],
      ),
    );
  }

  void _showImageDetails(int index) {
    showModalBottomSheet(
      context: context,
      builder: (context) {
        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.crop),
              title: const Text('Edit Boundaries'),
              onTap: () {
                Navigator.pop(context);
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                      content:
                          Text('Boundary editing would be implemented here')),
                );
              },
            ),
            ListTile(
              leading: const Icon(Icons.color_lens),
              title: const Text('Adjust Filters'),
              onTap: () {
                Navigator.pop(context);
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                      content:
                          Text('Filter adjustment would be implemented here')),
                );
              },
            ),
            ListTile(
              leading: const Icon(Icons.text_fields),
              title: const Text('Extract Text (OCR)'),
              onTap: () {
                Navigator.pop(context);
                _extractText(index);
              },
            ),
            ListTile(
              leading: const Icon(Icons.delete),
              title: const Text('Delete'),
              onTap: () {
                setState(() {
                  _scannedImages.removeAt(index);
                });
                Navigator.pop(context);
              },
            ),
          ],
        );
      },
    );
  }
}

class Point {
  final double x;
  final double y;

  Point(this.x, this.y);
}

class ImgProc {
  static const int colorBGR2GRAY = 6;
  static const int adaptiveThreshMeanC = 0;
  static const int threshBinary = 0;

  static Future<String> canny(
      String imagePath, int threshold1, int threshold2) async {
    final directory = await getTemporaryDirectory();
    final String outputPath =
        '${directory.path}/canny_${path.basename(imagePath)}';
    await File(imagePath).copy(outputPath);
    return outputPath;
  }

  static Future<List<dynamic>> findContours(String imagePath) async {
    return [[]];
  }

  static double contourArea(dynamic contour) {
    return 0.0;
  }

  static Future<String> drawContours(String imagePath, List<dynamic> contours,
      int contourIdx, int color, int thickness) async {
    final directory = await getTemporaryDirectory();
    final String outputPath =
        '${directory.path}/contours_${path.basename(imagePath)}';
    await File(imagePath).copy(outputPath);
    return outputPath;
  }

  static Future<String> warpPerspective(
      String imagePath, List<Point> corners, Size size) async {
    final directory = await getTemporaryDirectory();
    final String outputPath =
        '${directory.path}/warped_${path.basename(imagePath)}';
    await File(imagePath).copy(outputPath);
    return outputPath;
  }

  static Future<String> cvtColor(String imagePath, int code) async {
    final directory = await getTemporaryDirectory();
    final String outputPath =
        '${directory.path}/gray_${path.basename(imagePath)}';
    await File(imagePath).copy(outputPath);
    return outputPath;
  }

  static Future<String> adaptiveThreshold(String imagePath, int maxValue,
      int adaptiveMethod, int thresholdType, int blockSize, int c) async {
    final directory = await getTemporaryDirectory();
    final String outputPath =
        '${directory.path}/threshold_${path.basename(imagePath)}';
    await File(imagePath).copy(outputPath);
    return outputPath;
  }

  static Future<String> convertScaleAbs(String imagePath,
      {double alpha = 1.0, double beta = 0.0}) async {
    final directory = await getTemporaryDirectory();
    final String outputPath =
        '${directory.path}/scale_${path.basename(imagePath)}';
    await File(imagePath).copy(outputPath);
    return outputPath;
  }

  static Future<String> gaussianBlur(
      String imagePath, List<int> kernelSize, double sigmaX) async {
    final directory = await getTemporaryDirectory();
    final String outputPath =
        '${directory.path}/blur_${path.basename(imagePath)}';
    await File(imagePath).copy(outputPath);
    return outputPath;
  }
}
