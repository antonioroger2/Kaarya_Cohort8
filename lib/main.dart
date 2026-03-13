// lib/main.dart

import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
// TODO: Add firebase_messaging package to pubspec.yaml
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'features/auth/auth_wrapper.dart';
// Using UserDashboard as it's the wrapper
import 'features/auth/worker_onboarding_screen.dart'; // Assuming this name

// TODO: Add internationalization (i18n) support for native languages
// - Add flutter_localizations and intl packages
// - Create ARB files for Hindi and regional languages
// - Implement language detection based on device locale
// - Add language selection in user profile settings

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  // Load environment variables
  await dotenv.load(fileName: ".env");
  
  // Initialize Firebase with options from .env
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

  // Initialize FCM
  FirebaseMessaging messaging = FirebaseMessaging.instance;
  await messaging.requestPermission();
  // TODO: Handle FCM tokens for backend integration

  runApp(const KaaryaConnectApp());
}

class KaaryaConnectApp extends StatelessWidget {
  const KaaryaConnectApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Kaarya Connect',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        primarySwatch: Colors.teal, // Keeping original theme color
        useMaterial3: true,
      ),
      // Fixed Routes: Only the root is kept. Other screens should be pushed.
      routes: {
        '/': (context) => const AuthWrapper(),
        // Temporary worker signup route needed for the AuthScreen flow interception
        '/worker-onboarding': (context) => const WorkerOnboardingScreen(phoneNumber: '', uid: ''),
      },
    );
  }
}