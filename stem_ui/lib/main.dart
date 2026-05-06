import 'package:flutter/material.dart';
import 'mixer_screen.dart';

void main() {
  runApp(const StemApp());
}

class StemApp extends StatelessWidget {
  const StemApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Stem Mixer',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness: Brightness.dark,
        primarySwatch: Colors.blue,
        scaffoldBackgroundColor: Colors.black,
        useMaterial3: true,
      ),
      home: const MixerScreen(),
    );
  }
}
