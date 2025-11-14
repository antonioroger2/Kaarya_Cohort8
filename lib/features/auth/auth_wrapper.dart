// lib/features/auth/auth_wrapper.dart
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../features/auth/auth_screen.dart';
import '../../features/user/user_dashboard.dart';
import '../../features/worker/worker_dashboard.dart';

class AuthWrapper extends StatelessWidget {
  const AuthWrapper({super.key});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<User?>(
      stream: FirebaseAuth.instance.authStateChanges(),
      builder: (context, authSnapshot) {
        
        // 1. Show loading screen while checking auth
        if (authSnapshot.connectionState == ConnectionState.waiting) {
          return const Scaffold(body: Center(child: CircularProgressIndicator()));
        }

        // 2. If NO user, show AuthScreen
        if (!authSnapshot.hasData) {
          return const AuthScreen();
        }

        // 3. User IS logged in. 
        // Now, we must find their document and check 'phone_verified'.
        // We'll check 'workers' first, then 'users'.
        
        final user = authSnapshot.data!;

        return StreamBuilder<DocumentSnapshot>(
          // Listen to the 'workers' collection
          stream: FirebaseFirestore.instance.collection('workers').doc(user.uid).snapshots(),
          builder: (context, workerSnapshot) {
            
            if (workerSnapshot.connectionState == ConnectionState.waiting) {
              return const Scaffold(body: Center(child: CircularProgressIndicator()));
            }

            if (workerSnapshot.hasData && workerSnapshot.data!.exists) {
              // This is a Worker. NOW check verification.
              final data = workerSnapshot.data!.data() as Map<String, dynamic>?;
              final isVerified = data?['phone_verified'] ?? false;
              
              if (isVerified) {
                // Logged in, is a Worker, AND verified.
                return WorkerDashboard(workerId: user.uid);
              } else {
                // Logged in, is a Worker, but NOT verified.
                // Keep them on AuthScreen (to see OTP dialog).
                return const AuthScreen();
              }
            }

            // Not a worker. Now we check the 'users' collection.
            return StreamBuilder<DocumentSnapshot>(
              stream: FirebaseFirestore.instance.collection('users').doc(user.uid).snapshots(),
              builder: (context, userSnapshot) {
                
                if (userSnapshot.connectionState == ConnectionState.waiting) {
                  return const Scaffold(body: Center(child: CircularProgressIndicator()));
                }

                if (userSnapshot.hasData && userSnapshot.data!.exists) {
                  // This is a User. NOW check verification.
                  final data = userSnapshot.data!.data() as Map<String, dynamic>?;
                  final isVerified = data?['phone_verified'] ?? false;
                  
                  if (isVerified) {
                    // Logged in, is a User, AND verified.
                    return UserDashboard(userId: user.uid);
                  } else {
                    // Logged in, is a User, but NOT verified.
                    // Keep them on AuthScreen (to see OTP dialog).
                    return const AuthScreen();
                  }
                }
                
                // Logged in, but doc doesn't exist in 'users' OR 'workers'.
                // This happens for a brief moment during sign-up.
                // Show AuthScreen.
                return const AuthScreen();
              },
            );
          },
        );
      },
    );
  }
}