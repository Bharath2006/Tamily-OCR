import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:http/http.dart' as http;
import 'package:url_launcher/url_launcher.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:flutter_tesseract_ocr/flutter_tesseract_ocr.dart';

class HomeScreen extends StatefulWidget {
  @override
  _HomeScreenState createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  OverlayEntry? _loadingOverlay;
  String _extractedText = '';
  List<String> _extractedImages = [];
  List<String> _extractedLinks = [];
  bool _isProcessing = false;
  bool _isDrawing = false;
  bool _useTamilModel = false;
  List<Offset?> _drawingPoints = [];
  GlobalKey _drawingKey = GlobalKey();
  late TextRecognizer _textRecognizer;
  bool _isCorrectingText = false;
  String _correctedText = '';
  bool _showCorrectedText = false;
  String _selectedText = '';
  bool _showWebResults = false;
  List<Map<String, String>> _webResults = [];

  @override
  void initState() {
    super.initState();
    _textRecognizer = TextRecognizer(script: TextRecognitionScript.latin);
  }

  @override
  void dispose() {
    _textRecognizer.close();
    super.dispose();
  }

  List<String> _extractLinks(String text) {
    try {
      final linkRegExp = RegExp(
        r'(?:(?:https?|ftp):\/\/)?[\w/\-?=%.]+\.[\w/\-?=%.]+',
        caseSensitive: false,
      );
      return linkRegExp
          .allMatches(text)
          .map((match) => match.group(0)!)
          .toList();
    } catch (e) {
      return [];
    }
  }

  void _showLoadingOverlay() {
    _loadingOverlay = OverlayEntry(
      builder: (context) => Material(
        color: Colors.black.withOpacity(0.5),
        child: Center(
          child: Container(
            padding: EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                CircularProgressIndicator(),
                SizedBox(height: 20),
                Text(
                  'Processing Tamil Text...',
                  style: TextStyle(fontSize: 16),
                ),
                SizedBox(height: 10),
                Text(
                  'This may take longer than Latin text',
                  style: TextStyle(fontSize: 14, color: Colors.grey),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    Overlay.of(context)?.insert(_loadingOverlay!);
  }

  Future<void> _toggleTamilMode(bool value) async {
    setState(() {
      _useTamilModel = value;
    });
  }

  void _hideLoadingOverlay() {
    _loadingOverlay?.remove();
    _loadingOverlay = null;
  }

  Future<void> _processFile(PlatformFile file) async {
    if (file.path == null) return;

    try {
      final fileInstance = File(file.path!);
      if (!await fileInstance.exists()) {
        throw Exception('File does not exist');
      }
      final fileSize = await fileInstance.length();
      if (fileSize > 10 * 1024 * 1024) {
        throw Exception('File is too large (max 10MB)');
      }

      if (_useTamilModel) {
        _showLoadingOverlay();
        _showTamilProcessingIndicator();
      }

      setState(() {
        _isProcessing = true;
        _extractedText = '';
        _extractedImages = [];
        _extractedLinks = [];
        _correctedText = '';
        _showCorrectedText = false;
        _showWebResults = false;
      });

      String text;
      List<String> links;

      if (_useTamilModel) {
        await Future.delayed(Duration(milliseconds: 100));
        text = await FlutterTesseractOcr.extractText(
          file.path!,
          language: 'tam',
          args: {
            'preserve_interword_spaces': '1',
          },
        );
        links = _extractLinks(text);
      } else {
        final inputImage = InputImage.fromFilePath(file.path!);
        final recognizedText = await _textRecognizer.processImage(inputImage);
        text = recognizedText.text;
        links = _extractLinks(text);
      }

      setState(() {
        _extractedText = text;
        if (['.jpg', '.jpeg', '.png', '.bmp', '.webp']
            .any((ext) => file.path!.toLowerCase().endsWith(ext))) {
          _extractedImages = [file.path!];
        }
        _extractedLinks = links;
      });
    } on PlatformException catch (e) {
      _showErrorSnackbar('OCR engine error: ${e.message ?? 'Unknown error'}');
    } catch (e) {
      _showErrorSnackbar('Error: ${e.toString()}');
    } finally {
      setState(() => _isProcessing = false);
      _hideLoadingOverlay();
      ScaffoldMessenger.of(context).hideCurrentSnackBar();
    }
  }

  void _showTamilProcessingIndicator() {
    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: ConstrainedBox(
          constraints: BoxConstraints(
            maxWidth: MediaQuery.of(context).size.width * 0.9,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(
                width: 24,
                height: 24,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                ),
              ),
              SizedBox(width: 16),
              Flexible(
                child: Text(
                  'Processing Tamil text...',
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ),
        duration: Duration(minutes: 1),
        behavior: SnackBarBehavior.floating,
        margin: EdgeInsets.all(10),
      ),
    );
  }

  void _showErrorSnackbar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.red,
        duration: Duration(seconds: 4),
      ),
    );
  }

  Future<void> _recognizeDrawing() async {
    if (_drawingPoints.isEmpty) return;

    setState(() {
      _isProcessing = true;
    });

    try {
      final boundary = _drawingKey.currentContext!.findRenderObject()
          as RenderRepaintBoundary;
      final image = await boundary.toImage();
      final byteData = await image.toByteData(format: ui.ImageByteFormat.png);

      if (byteData == null) {
        throw Exception('Failed to convert drawing to image');
      }

      final buffer = byteData.buffer.asUint8List();
      final directory = await getTemporaryDirectory();
      final filePath =
          '${directory.path}/drawing_${DateTime.now().millisecondsSinceEpoch}.png';
      final file = await File(filePath).writeAsBytes(buffer);

      String text;
      if (_useTamilModel) {
        text = await FlutterTesseractOcr.extractText(
          filePath,
          language: 'tam',
          args: {
            'preserve_interword_spaces': '1',
          },
        );
      } else {
        final inputImage = InputImage.fromFilePath(filePath);
        final recognizedText = await _textRecognizer.processImage(inputImage);
        text = recognizedText.text;
      }

      setState(() {
        _extractedText += '\n$text';
        _drawingPoints.clear();
        _isProcessing = false;
        _isDrawing = false;
      });

      await file.delete();
    } catch (e) {
      setState(() {
        _isProcessing = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error recognizing drawing: ${e.toString()}')),
      );
    }
  }

  Widget _buildDrawingCanvas() {
    return GestureDetector(
      onPanUpdate: (details) {
        setState(() {
          final renderObject = context.findRenderObject();
          if (renderObject != null) {
            final RenderBox renderBox = renderObject as RenderBox;
            final localPos = renderBox.globalToLocal(details.globalPosition);
            // Add slight smoothing by averaging with last point
            if (_drawingPoints.isNotEmpty && _drawingPoints.last != null) {
              final lastPoint = _drawingPoints.last!;
              final smoothedPoint = Offset(
                (lastPoint.dx + localPos.dx) / 2,
                (lastPoint.dy + localPos.dy) / 2,
              );
              _drawingPoints.add(smoothedPoint);
            } else {
              _drawingPoints.add(localPos);
            }
          }
        });
      },
      onPanEnd: (details) => _drawingPoints.add(null),
      child: RepaintBoundary(
        key: _drawingKey,
        child: Container(
          color: Colors.white,
          child: CustomPaint(
            painter:
                _DrawingPainter(_drawingPoints, isTamilMode: _useTamilModel),
            size: Size.infinite,
          ),
        ),
      ),
    );
  }

  Future<void> _launchURL(String url) async {
    if (!url.startsWith('http://') && !url.startsWith('https://')) {
      url = 'https://$url';
    }

    Uri uri = Uri.parse(url);

    if (!await launchUrl(uri, mode: LaunchMode.externalApplication)) {
      debugPrint("Could not launch $url");
    }
  }

  Future<void> _correctText() async {
    if (_extractedText.isEmpty) return;

    setState(() {
      _isCorrectingText = true;
      _showCorrectedText = false;
    });

    try {
      if (_useTamilModel) {
        final corrected = await _correctTamilTextWithFreeAPI(_extractedText);
        setState(() {
          _correctedText = corrected;
          _showCorrectedText = true;
        });
      } else {
        final corrected = await _correctEnglishText(_extractedText);
        setState(() {
          _correctedText = corrected;
          _showCorrectedText = true;
        });
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error correcting text: ${e.toString()}')),
      );
    } finally {
      setState(() => _isCorrectingText = false);
    }
  }

  Future<String> _correctTamilTextWithFreeAPI(String text) async {
    try {
      final translateResponse = await http.get(Uri.parse(
          'https://mymemory.translated.net/api/get?q=${Uri.encodeComponent(text)}&langpair=ta|en'));

      if (translateResponse.statusCode == 200) {
        final translated = jsonDecode(translateResponse.body)['responseData']
            ['translatedText'];
        final correctedEnglish = await _correctEnglishText(translated);

        final backTranslateResponse = await http.get(Uri.parse(
            'https://mymemory.translated.net/api/get?q=${Uri.encodeComponent(correctedEnglish)}&langpair=en|ta'));

        if (backTranslateResponse.statusCode == 200) {
          return jsonDecode(backTranslateResponse.body)['responseData']
              ['translatedText'];
        }
      }
      return text;
    } catch (e) {
      print('Free API correction error: $e');
      return text;
    }
  }

  Future<String> _correctEnglishText(String text) async {
    final response = await http.post(
      Uri.parse('https://languagetool.org/api/v2/check'),
      body: {
        'text': text,
        'language': 'en-US',
      },
    );

    if (response.statusCode == 200) {
      final result = jsonDecode(response.body);
      String correctedText = text;

      if (result['matches'] != null) {
        final matches = (result['matches'] as List).reversed;
        for (var match in matches) {
          if (match['replacements'] != null &&
              match['replacements'].isNotEmpty) {
            final replacement = match['replacements'][0]['value'];
            final offset = match['offset'];
            final length = match['length'];
            correctedText = correctedText.substring(0, offset) +
                replacement +
                correctedText.substring(offset + length);
          }
        }
      }
      return correctedText;
    } else {
      throw Exception('Failed to correct text');
    }
  }

  Future<void> _searchWebWithFreeAPI(String query) async {
    if (query.isEmpty) return;

    setState(() {
      _isProcessing = true;
      _showWebResults = false;
    });

    try {
      final response = await http.get(Uri.parse(
          'https://api.duckduckgo.com/?format=json&q=${Uri.encodeComponent(query)}'));

      if (response.statusCode == 200) {
        final result = jsonDecode(response.body);
        List<Map<String, String>> results = [];

        if (result['RelatedTopics'] != null) {
          for (var topic in result['RelatedTopics']) {
            if (topic['Text'] != null && topic['FirstURL'] != null) {
              results.add({
                'title': topic['Text'].split(' - ')[0],
                'link': topic['FirstURL'],
                'snippet': topic['Text'].contains(' - ')
                    ? topic['Text'].split(' - ')[1]
                    : topic['Text'],
              });
            }
          }
        }

        setState(() {
          _webResults = results;
          _showWebResults = true;
        });
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error searching web: ${e.toString()}')),
      );
    } finally {
      setState(() => _isProcessing = false);
    }
  }

  Future<void> _pickFile() async {
    try {
      FilePickerResult? result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['pdf', 'jpg', 'jpeg', 'png'],
        allowMultiple: false,
      );

      if (result != null && result.files.isNotEmpty) {
        PlatformFile file = result.files.first;
        if (file.path != null) {
          await _processFile(file);
        } else if (file.bytes != null) {
          final directory = await getTemporaryDirectory();
          final path = '${directory.path}/${file.name}';
          await File(path).writeAsBytes(file.bytes!);
          await _processFile(PlatformFile(
            name: file.name,
            path: path,
            size: file.bytes!.length,
          ));
        }
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error picking file: ${e.toString()}')),
      );
    }
  }

  Future<void> _captureImage() async {
    try {
      final picker = ImagePicker();
      final pickedFile = await picker.pickImage(
        source: ImageSource.camera,
        maxWidth: 1920,
        maxHeight: 1080,
        imageQuality: 90,
      );

      if (pickedFile != null) {
        final fileSize = await File(pickedFile.path).length();
        await _processFile(PlatformFile(
          name: pickedFile.name,
          path: pickedFile.path,
          size: fileSize,
        ));
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error capturing image: ${e.toString()}')),
      );
    }
  }

  Future<void> _clearDrawing() async {
    setState(() {
      _drawingPoints.clear();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        title: Text(
          'Tamil OCR Pro',
          style: TextStyle(
            fontSize: 22,
            fontWeight: FontWeight.bold,
            color: Colors.blueAccent,
            shadows: [
              Shadow(color: Colors.blue, blurRadius: 5),
            ],
          ),
        ),
        actions: [
          Switch(
            value: _useTamilModel,
            onChanged: _toggleTamilMode,
            activeColor: Colors.blueAccent,
          ),
          Padding(
            padding: EdgeInsets.only(right: 16.0),
            child: Center(
              child: Text(
                _useTamilModel ? 'Tamil OCR' : 'Latin OCR',
                style:
                    TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
              ),
            ),
          ),
        ],
      ),
      body: Column(
        children: [
          if (_isProcessing || _isCorrectingText)
            LinearProgressIndicator(
              backgroundColor: Colors.grey[800],
              valueColor: AlwaysStoppedAnimation<Color>(Colors.blueAccent),
            ),
          Expanded(
            child: _isDrawing
                ? _buildDrawingCanvas()
                : _extractedText.isEmpty && !_isProcessing
                    ? Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.document_scanner,
                                size: 100, color: Colors.blueAccent),
                            SizedBox(height: 20),
                            Text(
                              'Upload a document or draw text',
                              style: TextStyle(
                                  fontSize: 18, color: Colors.grey[400]),
                            ),
                            SizedBox(height: 10),
                            Container(
                              padding: EdgeInsets.symmetric(
                                  horizontal: 12, vertical: 6),
                              decoration: BoxDecoration(
                                color: Colors.blueAccent,
                                borderRadius: BorderRadius.circular(8),
                                boxShadow: [
                                  BoxShadow(
                                      color: Colors.blue.withOpacity(0.5),
                                      blurRadius: 5),
                                ],
                              ),
                              child: Text(
                                _useTamilModel
                                    ? 'Tamil OCR Mode'
                                    : 'Latin OCR Mode',
                                style: TextStyle(
                                    fontSize: 16,
                                    color: Colors.white,
                                    fontWeight: FontWeight.bold),
                              ),
                            ),
                          ],
                        ),
                      )
                    : SingleChildScrollView(
                        padding: EdgeInsets.all(16),
                        child: Column(
                          children: [
                            Padding(
                              padding: const EdgeInsets.only(bottom: 16.0),
                              child: Row(
                                children: [
                                  Expanded(
                                    child: ElevatedButton(
                                      onPressed: _isCorrectingText
                                          ? null
                                          : _correctText,
                                      style: ElevatedButton.styleFrom(
                                        backgroundColor: Colors.blueAccent,
                                        shape: RoundedRectangleBorder(
                                          borderRadius:
                                              BorderRadius.circular(12),
                                        ),
                                        padding: EdgeInsets.symmetric(
                                            horizontal: 16, vertical: 12),
                                      ),
                                      child: _isCorrectingText
                                          ? SizedBox(
                                              width: 20,
                                              height: 20,
                                              child: CircularProgressIndicator(
                                                strokeWidth: 2,
                                                valueColor:
                                                    AlwaysStoppedAnimation<
                                                        Color>(Colors.white),
                                              ),
                                            )
                                          : Text(
                                              'AI Correct Text',
                                              style: TextStyle(
                                                  fontSize: 16,
                                                  color: Colors.white),
                                            ),
                                    ),
                                  ),
                                  SizedBox(width: 10),
                                  Expanded(
                                    child: ElevatedButton(
                                      onPressed: _selectedText.isEmpty
                                          ? null
                                          : () => _searchWebWithFreeAPI(
                                              _selectedText),
                                      style: ElevatedButton.styleFrom(
                                        backgroundColor: Colors.green,
                                        shape: RoundedRectangleBorder(
                                          borderRadius:
                                              BorderRadius.circular(12),
                                        ),
                                        padding: EdgeInsets.symmetric(
                                            horizontal: 16, vertical: 12),
                                      ),
                                      child: Text(
                                        'Search Web',
                                        style: TextStyle(
                                            fontSize: 16, color: Colors.white),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            Card(
                              color: Colors.grey[900],
                              shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12)),
                              elevation: 4,
                              child: Padding(
                                padding: EdgeInsets.all(16),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    if (_showCorrectedText)
                                      Padding(
                                        padding:
                                            const EdgeInsets.only(bottom: 8.0),
                                        child: Row(
                                          children: [
                                            Icon(Icons.spellcheck,
                                                color: Colors.green, size: 20),
                                            SizedBox(width: 8),
                                            Text(
                                              'AI Corrected Text',
                                              style: TextStyle(
                                                  color: Colors.green,
                                                  fontWeight: FontWeight.bold),
                                            ),
                                          ],
                                        ),
                                      ),
                                    SelectableText(
                                      _showCorrectedText
                                          ? _correctedText
                                          : _extractedText,
                                      style: TextStyle(
                                          fontSize: 16, color: Colors.white70),
                                      onSelectionChanged: (selection, cause) {
                                        final text = _showCorrectedText
                                            ? _correctedText
                                            : _extractedText;
                                        setState(() {
                                          _selectedText = text.substring(
                                            selection.start,
                                            selection.end,
                                          );
                                        });
                                      },
                                    ),
                                    if (_showCorrectedText)
                                      Align(
                                        alignment: Alignment.centerRight,
                                        child: TextButton(
                                          onPressed: () {
                                            setState(() {
                                              _showCorrectedText = false;
                                            });
                                          },
                                          child: Text('Show Original',
                                              style: TextStyle(
                                                  color: Colors.blueAccent)),
                                        ),
                                      ),
                                  ],
                                ),
                              ),
                            ),
                            if (_selectedText.isNotEmpty)
                              Padding(
                                padding: const EdgeInsets.only(top: 8.0),
                                child: Text(
                                  'Selected: "$_selectedText"',
                                  style: TextStyle(color: Colors.grey),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            if (_showWebResults) ...[
                              SizedBox(height: 20),
                              Text(
                                'Web Results:',
                                style: TextStyle(
                                    fontSize: 18,
                                    fontWeight: FontWeight.bold,
                                    color: Colors.white),
                              ),
                              SizedBox(height: 10),
                              ..._webResults.map(
                                (result) => Card(
                                  elevation: 5,
                                  color: Colors.blueGrey[900],
                                  shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(12)),
                                  child: ListTile(
                                    contentPadding: EdgeInsets.symmetric(
                                        horizontal: 15, vertical: 10),
                                    title: Text(
                                      result['title']!,
                                      style: TextStyle(
                                        color: Colors.white,
                                        fontWeight: FontWeight.w500,
                                      ),
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                    subtitle: Text(
                                      result['snippet']!,
                                      style: TextStyle(color: Colors.grey[400]),
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                    trailing: Icon(Icons.open_in_new,
                                        color: Colors.blueAccent),
                                    onTap: () => _launchURL(result['link']!),
                                  ),
                                ),
                              ),
                            ],
                            if (_extractedLinks.isNotEmpty &&
                                !_showWebResults) ...[
                              SizedBox(height: 20),
                              Text(
                                'Detected Links:',
                                style: TextStyle(
                                    fontSize: 18,
                                    fontWeight: FontWeight.bold,
                                    color: Colors.white),
                              ),
                              SizedBox(height: 10),
                              ..._extractedLinks.map(
                                (link) => Card(
                                  elevation: 5,
                                  color: Colors.blueGrey[900],
                                  shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(12)),
                                  child: ListTile(
                                    contentPadding: EdgeInsets.symmetric(
                                        horizontal: 15, vertical: 10),
                                    leading: Icon(Icons.link,
                                        color: Colors.blueAccent),
                                    title: Text(
                                      link,
                                      style: TextStyle(
                                        color: Colors.blueAccent,
                                        decoration: TextDecoration.underline,
                                        fontWeight: FontWeight.w500,
                                      ),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                    trailing: Icon(Icons.open_in_new,
                                        color: Colors.blueAccent),
                                    onTap: () => _launchURL(link),
                                  ),
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
          ),
        ],
      ),
      floatingActionButton: Column(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          if (_isDrawing) ...[
            FloatingActionButton(
              heroTag: 'recognize',
              onPressed: _recognizeDrawing,
              tooltip: 'Recognize Drawing',
              backgroundColor: Colors.green,
              child: Icon(Icons.check, color: Colors.white),
            ),
            SizedBox(height: 10),
            FloatingActionButton(
              heroTag: 'clear',
              onPressed: _clearDrawing,
              tooltip: 'Clear Drawing',
              backgroundColor: Colors.red,
              child: Icon(Icons.clear, color: Colors.white),
            ),
            SizedBox(height: 10),
          ],
          FloatingActionButton(
            heroTag: 'draw',
            onPressed: () => setState(() => _isDrawing = !_isDrawing),
            tooltip: _isDrawing ? 'Switch to Text' : 'Draw Text',
            backgroundColor: _isDrawing ? Colors.orangeAccent : Colors.blueGrey,
            child: Icon(_isDrawing ? Icons.keyboard : Icons.draw,
                color: Colors.white),
          ),
          SizedBox(height: 10),
          FloatingActionButton(
            heroTag: 'camera',
            onPressed: _captureImage,
            tooltip: 'Capture Image',
            backgroundColor: Colors.purple,
            child: Icon(Icons.camera_alt, color: Colors.white),
          ),
          SizedBox(height: 10),
          FloatingActionButton(
            heroTag: 'upload',
            onPressed: _pickFile,
            tooltip: 'Upload File',
            backgroundColor: Colors.teal,
            child: Icon(Icons.upload_file, color: Colors.white),
          ),
        ],
      ),
    );
  }
}

class _DrawingPainter extends CustomPainter {
  final List<Offset?> points;
  final bool isTamilMode;

  _DrawingPainter(this.points, {this.isTamilMode = false});

  @override
  void paint(Canvas canvas, Size size) {
    // Draw background grid for better writing guidance
    final gridPaint = Paint()
      ..color = Colors.grey[300]!.withOpacity(0.3)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.5;

    // Draw horizontal lines
    for (double i = 0; i < size.height; i += 20) {
      canvas.drawLine(Offset(0, i), Offset(size.width, i), gridPaint);
    }

    // Draw vertical lines - more spaced for Tamil characters which are wider
    final verticalSpacing = isTamilMode ? 30.0 : 20.0;
    for (double i = 0; i < size.width; i += verticalSpacing) {
      canvas.drawLine(Offset(i, 0), Offset(i, size.height), gridPaint);
    }

    // Main drawing paint
    final paint = Paint()
      ..color = isTamilMode ? Colors.blue[800]! : Colors.black
      ..strokeCap = StrokeCap.round
      ..strokeWidth = isTamilMode ? 6.0 : 4.0 // Thicker for Tamil
      ..style = PaintingStyle.stroke;

    // Draw a baseline to help with character alignment
    final baselinePaint = Paint()
      ..color = Colors.red.withOpacity(0.5)
      ..strokeWidth = 1.0;
    final baselineY = size.height * 0.7; // Lower baseline for Tamil
    canvas.drawLine(
      Offset(0, baselineY),
      Offset(size.width, baselineY),
      baselinePaint,
    );

    // Draw the actual user drawing
    Path path = Path();
    for (int i = 0; i < points.length; i++) {
      if (points[i] != null) {
        if (i == 0) {
          path.moveTo(points[i]!.dx, points[i]!.dy);
        } else {
          if (points[i - 1] != null) {
            path.lineTo(points[i]!.dx, points[i]!.dy);
          } else {
            path.moveTo(points[i]!.dx, points[i]!.dy);
          }
        }
      }
    }

    canvas.drawPath(path, paint);

    // For Tamil mode, add some visual guidance
    if (isTamilMode) {
      final guideText = TextPainter(
        text: TextSpan(
          text: 'தமிழ் எழுத்துகள்',
          style: TextStyle(
            color: Colors.grey.withOpacity(0.2),
            fontSize: 24,
            fontWeight: FontWeight.bold,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();

      guideText.paint(
        canvas,
        Offset(
          (size.width - guideText.width) / 2,
          (size.height - guideText.height) / 2,
        ),
      );
    }
  }

  @override
  bool shouldRepaint(_DrawingPainter oldDelegate) {
    return oldDelegate.points != points ||
        oldDelegate.isTamilMode != isTamilMode;
  }
}
