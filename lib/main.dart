import 'package:flutter/material.dart';

import 'package:tamily/test_pdf/test_home.dart';

void main() async {
  runApp(OCRApp());
}

class OCRApp extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Tamil OCR Pro',
      theme: ThemeData(
        primarySwatch: Colors.blue,
        visualDensity: VisualDensity.adaptivePlatformDensity,
      ),
      home: HomeScreen(),
      debugShowCheckedModeBanner: false,
    );
  }
}
