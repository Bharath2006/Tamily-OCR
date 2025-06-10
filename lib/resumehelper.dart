import 'dart:io';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:syncfusion_flutter_pdf/pdf.dart';
import 'package:http/http.dart' as http;

void main() {
  runApp(const ResumeAnalyzerApp());
}

class ResumeAnalyzerApp extends StatelessWidget {
  const ResumeAnalyzerApp({super.key});

  @override
  Widget build(BuildContext context) {
    return const MaterialApp(
      title: 'Resume Analyzer',
      home: ResumeAnalyzerScreen(),
      debugShowCheckedModeBanner: false,
    );
  }
}

class ResumeAnalyzerScreen extends StatefulWidget {
  const ResumeAnalyzerScreen({super.key});

  @override
  State<ResumeAnalyzerScreen> createState() => _ResumeAnalyzerScreenState();
}

class _ResumeAnalyzerScreenState extends State<ResumeAnalyzerScreen> {
  String _extractedText = '';
  String _suggestions = '';
  bool _isLoading = false;

  final String _apiKey = 'YOUR_GEMINI_API_KEY'; // Replace with your actual key
  final String _geminiEndpoint =
      'https://generativelanguage.googleapis.com/v1beta/models/gemini-pro:generateContent';

  Future<void> _pickAndAnalyzePDF() async {
    setState(() {
      _isLoading = true;
      _extractedText = '';
      _suggestions = '';
    });

    final result = await FilePicker.platform
        .pickFiles(type: FileType.custom, allowedExtensions: ['pdf']);

    if (result != null && result.files.single.path != null) {
      final filePath = result.files.single.path!;
      final extractedText = await _extractTextFromPDF(filePath);
      setState(() => _extractedText = extractedText);

      final suggestions = await _analyzeResumeWithGemini(extractedText);
      setState(() => _suggestions = suggestions);
    }

    setState(() => _isLoading = false);
  }

  Future<String> _extractTextFromPDF(String path) async {
    final fileBytes = File(path).readAsBytesSync();
    final document = PdfDocument(inputBytes: fileBytes);
    String text = PdfTextExtractor(document).extractText();
    document.dispose();
    return text;
  }

  Future<String> _analyzeResumeWithGemini(String text) async {
    try {
      final response = await http.post(
        Uri.parse(
            'https://generativelanguage.googleapis.com/v1/models/gemini-pro:generateContent?key=AIzaSyCBxrVwsadwHKok3_mgL7GXP_kunm1gUWc'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'contents': [
            {
              'parts': [
                {
                  'text': '''
Act as a professional resume reviewer. Analyze the resume text below and provide suggestions for improvement, highlighting missing skills, experience gaps, formatting, and language issues.

Resume:
$text
'''
                }
              ]
            }
          ]
        }),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        return data['candidates']?[0]?['content']?['parts']?[0]?['text'] ??
            'No suggestions found.';
      } else {
        return 'Error ${response.statusCode}: ${response.reasonPhrase}\n${response.body}';
      }
    } catch (e) {
      return 'Error: ${e.toString()}';
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Resume Analyzer')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: _isLoading
            ? const Center(child: CircularProgressIndicator())
            : SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    ElevatedButton.icon(
                      icon: const Icon(Icons.upload_file),
                      label: const Text('Pick Resume PDF'),
                      onPressed: _pickAndAnalyzePDF,
                    ),
                    const SizedBox(height: 20),
                    if (_extractedText.isNotEmpty) ...[
                      const Text('Extracted Text:',
                          style: TextStyle(fontWeight: FontWeight.bold)),
                      const SizedBox(height: 8),
                      // Text(_extractedText),
                      const SizedBox(height: 20),
                      const Text('Suggestions:',
                          style: TextStyle(fontWeight: FontWeight.bold)),
                      const SizedBox(height: 8),
                      Text(_suggestions),
                    ],
                  ],
                ),
              ),
      ),
    );
  }
}
