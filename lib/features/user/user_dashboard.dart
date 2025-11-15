// lib/features/user/user_dashboard.dart
import 'package:flutter/material.dart';
import 'home_screen.dart';

class UserDashboard extends StatelessWidget {
  final String userId; 
  const UserDashboard({super.key, required this.userId});

  @override
  Widget build(BuildContext context) {

    return HomeScreen(userId: userId);
  }
}