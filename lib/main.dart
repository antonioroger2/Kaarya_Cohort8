// lib/main.dart

import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'features/auth/auth_wrapper.dart';
import 'features/user/user_dashboard.dart'; // Using UserDashboard as it's the wrapper
import 'features/worker/worker_dashboard.dart';
import 'features/auth/worker_onboarding_screen.dart'; // Assuming this name

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  // Initialize Firebase with the explicit options (Original block)
  await Firebase.initializeApp(
    options: const FirebaseOptions(
      apiKey: "AIzaSyBs9SOI0JzT93aj9QFdvBlq-nKYmb9DRW0",
      authDomain: "kaarya-ee87f.firebaseapp.com",
      projectId: "kaarya-ee87f",
      storageBucket: "kaarya-ee87f.firebasestorage.app",
      messagingSenderId: "529720186258",
      appId: "1:529720186258:web:0a355cdd36f64bfc555d4b",
    ),
  );

  runApp(const KaaryaConnectApp());
}

class KaaryaConnectApp extends StatelessWidget {
  const KaaryaConnectApp({Key? key}) : super(key: key);

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