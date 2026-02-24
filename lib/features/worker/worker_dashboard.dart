// lib/features/worker/worker_dashboard.dart
import 'package:flutter/material.dart';
// TODO: Add firebase_messaging package to pubspec.yaml
import 'package:firebase_messaging/firebase_messaging.dart';
import '../../features/worker/worker_jobs_screen.dart';
import '../../features/worker/worker_calendar_screen.dart';
import '../../features/shared/profile_screen.dart';
import '../../features/worker/sos_screen.dart';

class WorkerDashboard extends StatefulWidget {
  final String workerId;
  const WorkerDashboard({super.key, required this.workerId});

  @override
  State<WorkerDashboard> createState() => _WorkerDashboardState();
}

class _WorkerDashboardState extends State<WorkerDashboard> {
  int _selectedIndex = 0;
  late final List<Widget> _screens;

  @override
  void initState() {
    super.initState();
    _screens = [
      WorkerJobsScreen(workerId: widget.workerId),
      WorkerCalendarScreen(workerId: widget.workerId),
      ProfileScreen(userId: widget.workerId, isWorker: true),
      const SOSScreen(),
    ];

    // Setup FCM for job notifications
    FirebaseMessaging.onMessage.listen((RemoteMessage message) {
      // Handle foreground messages (app open)
      _showJobNotification(message);
    });

    FirebaseMessaging.onMessageOpenedApp.listen((RemoteMessage message) {
      // Handle background messages tapped
      _handleJobNotificationTap(message);
    });
  }

  void _showJobNotification(RemoteMessage message) {
    // TODO: Show in-app notification or update jobs screen
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('New job request: ${message.notification?.title ?? 'Job Alert'}'),
        action: SnackBarAction(
          label: 'View',
          onPressed: () => setState(() => _selectedIndex = 0), // Switch to Jobs tab
        ),
      ),
    );
  }

  void _handleJobNotificationTap(RemoteMessage message) {
    // TODO: Navigate to specific job details
    setState(() => _selectedIndex = 0);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: _screens[_selectedIndex],
      bottomNavigationBar: Container(
        decoration: BoxDecoration(
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.1),
              blurRadius: 10,
              offset: const Offset(0, -5),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
          child: BottomNavigationBar(
            currentIndex: _selectedIndex,
            selectedItemColor: Colors.teal, 
            unselectedItemColor: Colors.grey,
            showUnselectedLabels: true,
            type: BottomNavigationBarType.fixed,
            backgroundColor: Colors.white,
            elevation: 0,
            items: [
              BottomNavigationBarItem(
                icon: Icon(_selectedIndex == 0 ? Icons.work : Icons.work_outline),
                label: 'Jobs',
              ),
              BottomNavigationBarItem(
                icon: Icon(_selectedIndex == 1 ? Icons.calendar_month : Icons.calendar_month_outlined),
                label: 'Schedule',
              ),
              BottomNavigationBarItem(
                icon: Icon(_selectedIndex == 2 ? Icons.person : Icons.person_outline),
                label: 'Profile',
              ),
              BottomNavigationBarItem(
                icon: Icon(_selectedIndex == 3 ? Icons.sos : Icons.sos_outlined),
                label: 'SOS',
              ),
            ],
            onTap: (index) => setState(() => _selectedIndex = index),
          ),
        ),
      ),
    );
  }
}