// lib/main.dart

import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
// TODO: Add firebase_messaging package to pubspec.yaml
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_web_plugins/url_strategy.dart';
import 'app.dart';

// TODO: Add internationalization (i18n) support for native languages
// - Add flutter_localizations and intl packages
// - Create ARB files for Hindi and regional languages
// - Implement language detection based on device locale
// - Add language selection in user profile settings

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  if (kIsWeb) {
    usePathUrlStrategy();
  }
  
  // Load environment variables
  await dotenv.load(fileName: ".env");
  
  // Initialize Firebase
  try {
    if (Firebase.apps.isEmpty) {
      await Firebase.initializeApp(
        options: FirebaseOptions(
          apiKey: dotenv.env['FIREBASE_API_KEY']!,
          authDomain: dotenv.env['FIREBASE_AUTH_DOMAIN']!,
          projectId: dotenv.env['FIREBASE_PROJECT_ID']!,
          storageBucket: dotenv.env['FIREBASE_STORAGE_BUCKET']!,
          messagingSenderId: dotenv.env['FIREBASE_MESSAGING_SENDER_ID']!,
          appId: dotenv.env['FIREBASE_APP_ID']!,
        ),
      );
    }
  } catch (e) {
    // Fallback for debugging: run without Firebase if init fails
    print('Firebase init failed: $e');
    // For web, you can show a simple UI or log
  }

  // Firestore web mitigation for listener instability seen as b815/ca9
  // internal assertions in Firebase JS SDK 12.9.0.
  if (kIsWeb) {
    FirebaseFirestore.instance.settings = const Settings(
      persistenceEnabled: false,
      webExperimentalForceLongPolling: true,
      webExperimentalAutoDetectLongPolling: false,
    );
  }

  // Initialize FCM for non-web
  if (!kIsWeb) {
    FirebaseMessaging messaging = FirebaseMessaging.instance;
    await messaging.requestPermission();
    // TODO: Handle FCM tokens for backend integration
  }

  runApp(const ProviderScope(child: KaaryaConnectApp()));
}