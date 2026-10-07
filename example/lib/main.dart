import 'package:flutter/material.dart';
import 'lab_screen.dart';

void main() => runApp(const ModalLabApp());

class ModalLabApp extends StatelessWidget {
  const ModalLabApp({super.key});
  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'WebView Modal Lab',
    theme: ThemeData(
      colorSchemeSeed: const Color(0xff4362a5),
      useMaterial3: true,
    ),
    home: const LabScreen(),
  );
}
