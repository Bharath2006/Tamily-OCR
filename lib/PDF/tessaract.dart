import 'package:flutter/services.dart';
import 'package:flutter_tesseract_ocr/flutter_tesseract_ocr.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as path;
import 'dart:io';

class TesseractService {
  static bool _isInitialized = false;
  static String? _tessDataPath;
  static Future<String> extractText(String imagePath) async {
    if (!_isInitialized) {
      await initialize();
    }

    try {
      final result = await FlutterTesseractOcr.extractText(
        imagePath,
        language: 'tam',
        args: {
          'preserve_interword_spaces': '1',
          'tessdata_dir': _tessDataPath,
          'psm': '6',
        },
      ).timeout(Duration(seconds: 30));

      if (result.isEmpty) {
        throw Exception('No text recognized');
      }
      return result;
    } on PlatformException catch (e) {
      if (e.code == 'TESSERACT_NOT_INIT') {
        await initialize();
        return extractText(imagePath);
      }
      rethrow;
    }
  }

  static Future<void> initialize() async {
    if (_isInitialized) return;

    try {
      final appDocDir = await getApplicationDocumentsDirectory();
      _tessDataPath = path.join(appDocDir.path, 'tessdata');

      final tessDataDir = Directory(_tessDataPath!);
      if (!await tessDataDir.exists()) {
        await tessDataDir.create(recursive: true);
      }

      await _copyAssetToTessData(
          'assets/tessdata_config.json', 'tessdata_config.json');

      await _copyTrainedData('assets/tam.traineddata');

      _isInitialized = true;
    } catch (e) {
      throw Exception('Failed to initialize Tesseract: $e');
    }
  }

  static Future<void> _copyAssetToTessData(
      String assetPath, String targetName) async {
    try {
      final data = await rootBundle.load(assetPath);
      final bytes = data.buffer.asUint8List();
      final file = File(path.join(_tessDataPath!, targetName));
      await file.writeAsBytes(bytes);
    } catch (e) {
      throw Exception('Failed to copy $targetName: $e');
    }
  }

  static Future<void> _copyTrainedData(String assetPath) async {
    try {
      final data = await rootBundle.load(assetPath);
      final bytes = data.buffer.asUint8List();
      final fileName = path.basename(assetPath);
      final file = File(path.join(_tessDataPath!, fileName));
      await file.writeAsBytes(bytes);
    } catch (e) {
      throw Exception('Failed to copy traineddata: $e');
    }
  }

  static Future<bool> isTamilModelAvailable() async {
    try {
      if (!_isInitialized) {
        await initialize();
      }
      final file = File(path.join(_tessDataPath!, 'tam.traineddata'));
      return await file.exists();
    } catch (e) {
      return false;
    }
  }
}
