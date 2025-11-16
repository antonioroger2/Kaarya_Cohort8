// lib/main.dart
import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'app.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // IMPORTANT: Replace with your actual Firebase Options for production
  await Firebase.initializeApp(
    options: const FirebaseOptions(
      apiKey: "",
  authDomain: "",
  projectId: "",
  storageBucket: "",
  messagingSenderId: "",
  appId: ""
    ),
  );
  runApp(const KaaryaConnectApp());
}
