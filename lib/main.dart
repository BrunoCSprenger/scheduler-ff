import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart'
    show TargetPlatform, defaultTargetPlatform, kIsWeb;
import 'package:flutter/material.dart';
import 'package:scheduler/app/auth_gate.dart';
import 'package:scheduler/firebase_options.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(options: _firebaseOptions());
  runApp(const SchedulingApp());
}

/// Firebase options per platform. Does not call [DefaultFirebaseOptions.currentPlatform]
/// so Linux never trips FlutterFire’s “configure linux” throw after regeneration.
FirebaseOptions _firebaseOptions() {
  if (kIsWeb) return DefaultFirebaseOptions.web;
  return switch (defaultTargetPlatform) {
    TargetPlatform.android => DefaultFirebaseOptions.android,
    TargetPlatform.iOS => DefaultFirebaseOptions.ios,
    TargetPlatform.macOS => DefaultFirebaseOptions.macos,
    TargetPlatform.windows => DefaultFirebaseOptions.windows,
    TargetPlatform.linux => DefaultFirebaseOptions.web,
    TargetPlatform.fuchsia => DefaultFirebaseOptions.web,
  };
}

class SchedulingApp extends StatelessWidget {
  const SchedulingApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Group Schedule',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF1565C0),
          brightness: Brightness.light,
        ),
        useMaterial3: true,
      ),
      darkTheme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF90CAF9),
          brightness: Brightness.dark,
        ),
        useMaterial3: true,
      ),
      themeMode: ThemeMode.system,
      home: const AuthGate(),
    );
  }
}
