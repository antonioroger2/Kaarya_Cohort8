// lib/main.dart
import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'app.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // IMPORTANT: Replace with your actual Firebase Options for production
  await Firebase.initializeApp(
    options: const FirebaseOptions(
      apiKey: "AIzaSyDm4xvZbc35ZNucXFoIBwdVyLd8h22NI1o",
      authDomain: "cohort8-f5139.firebaseapp.com",
      projectId: "cohort8-f5139",
      storageBucket: "cohort8-f5139.appspot.com", 
      messagingSenderId: "1006872143391",
      appId: "1:1006872143391:web:08873239c279e68f12172a"
    ),
  );
  runApp(const KaaryaConnectApp());
}
