import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:universal_html/html.dart' as html;

void main() {
  runApp(MyApp());
}

class MyApp extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'PDF Upload and Save',
      theme: ThemeData(primarySwatch: Colors.teal),
      home: PdfUploaderSaver(),
    );
  }
}

class PdfUploaderSaver extends StatefulWidget {
  @override
  State<PdfUploaderSaver> createState() => _PdfUploaderSaverState();
}

class _PdfUploaderSaverState extends State<PdfUploaderSaver> {
  String status = "No file selected.";

  Future<void> uploadAndSavePdf() async {
    try {
      setState(() => status = "Picking file...");

      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['pdf'],
      );

      if (result == null || result.files.single.bytes == null) {
        setState(() => status = "No file selected.");
        return;
      }

      Uint8List fileBytes = result.files.single.bytes!;
      String fileName = result.files.single.name;

      // Save using browser
      final blob = html.Blob([fileBytes], 'application/pdf');
      final url = html.Url.createObjectUrlFromBlob(blob);
      final anchor = html.AnchorElement(href: url)
        ..setAttribute('download', 'converted_$fileName')
        ..click();
      html.Url.revokeObjectUrl(url);

      setState(() => status = "Download started for converted_$fileName");
    } catch (e) {
      setState(() => status = "Error: ${e.toString()}");
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text("PDF Upload & Download")),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            ElevatedButton(
              onPressed: uploadAndSavePdf,
              child: Text("Upload PDF and Save"),
            ),
            SizedBox(height: 20),
            Text(status),
          ],
        ),
      ),
    );
  }
}
