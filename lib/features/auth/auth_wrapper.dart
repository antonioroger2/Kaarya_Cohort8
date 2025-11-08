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
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Scaffold(body: Center(child: CircularProgressIndicator()));
        }

        if (snapshot.hasData) {
          final user = snapshot.data!;
          return FutureBuilder<DocumentSnapshot>(
            // Check if the user is a worker
            future: FirebaseFirestore.instance.collection('workers').doc(user.uid).get(),
            builder: (context, workerSnapshot) {
              if (workerSnapshot.connectionState == ConnectionState.waiting) {
                return const Scaffold(body: Center(child: CircularProgressIndicator()));
              }

              if (workerSnapshot.hasData && workerSnapshot.data!.exists) {
                // User is a worker
                return WorkerDashboard(workerId: user.uid);
              }

              // User is a regular client/user
              return UserDashboard(userId: user.uid);
            },
          );
        }
        
        // No user signed in
        return const AuthScreen();
      },
    );
  }
}
