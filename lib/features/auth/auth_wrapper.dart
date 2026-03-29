
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../features/user/home_screen.dart';
import '../../features/user/user_dashboard.dart';
import '../../features/worker/worker_dashboard.dart';

class AuthWrapper extends StatefulWidget {
  const AuthWrapper({super.key});

  @override
  State<AuthWrapper> createState() => _AuthWrapperState();
}

class _AuthWrapperState extends State<AuthWrapper> {
  User? _user;
  bool? _isWorker;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _initializeAuth();
  }

  Future<void> _initializeAuth() async {
    FirebaseAuth.instance.authStateChanges().listen((user) async {
      if (!mounted) return;

      setState(() {
        _user = user;
        _loading = true;
      });

      if (user != null) {
        // Check if user is a worker first
        try {
          final workerDoc = await FirebaseFirestore.instance
              .collection('workers')
              .doc(user.uid)
              .get();

          if (!mounted) return;

          if (workerDoc.exists) {
            setState(() {
              _isWorker = true;
              _loading = false;
            });
            return;
          }

          // If not a worker, check if regular user
          await FirebaseFirestore.instance
              .collection('users')
              .doc(user.uid)
              .get();

          if (!mounted) return;

          setState(() {
            _isWorker = false;
            _loading = false;
          });
        } catch (e) {
          if (!mounted) return;
          // On error, default to user dashboard
          setState(() {
            _isWorker = false;
            _loading = false;
          });
        }
      } else {
        setState(() {
          _isWorker = null;
          _loading = false;
        });
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    if (_user == null) {
      // Show the main experience in guest mode; prompt login only when required.
      return const HomeScreen(userId: '');
    }

    if (_isWorker == true) {
      return WorkerDashboard(workerId: _user!.uid);
    }

    return UserDashboard(userId: _user!.uid);
  }
}