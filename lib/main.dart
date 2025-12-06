// lib/main.dart
import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'app.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  await Firebase.initializeApp(
    options: const FirebaseOptions(
      apiKey: "AIzaSyBs9SOI0JzT93aj9QFdvBlq-nKYmb9DRW0",
      authDomain: "kaarya-ee87f.firebaseapp.com",
      projectId: "kaarya-ee87f",
      storageBucket: "kaarya-ee87f.appspot.com",
      messagingSenderId: "529720186258",
      appId: "1:529720186258:web:0a355cdd36f64bfc555d4b",
    ),
  );

  runApp(const KaaryaConnectApp());
}
