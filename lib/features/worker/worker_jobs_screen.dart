// lib/features/worker/worker_jobs_screen.dart
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../core/theme.dart';
import '../../features/shared/inbox_screen.dart';
import '../../features/shared/booking_tile.dart';
import '../../features/worker/job_request_card.dart';

class WorkerJobsScreen extends StatefulWidget {
  final String workerId;
  const WorkerJobsScreen({super.key, required this.workerId});

  @override
  State<WorkerJobsScreen> createState() => _WorkerJobsScreenState();
}

class _WorkerJobsScreenState extends State<WorkerJobsScreen> with SingleTickerProviderStateMixin {
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('My Jobs'),
        actions: [
          StreamBuilder<QuerySnapshot>(
            stream: FirebaseFirestore.instance
                .collection('notifications')
                .where('recipientId', isEqualTo: widget.workerId)
                .where('isRead', isEqualTo: false)
                .snapshots(),
            builder: (context, snapshot) {
              final unreadCount = snapshot.data?.docs.length ?? 0;
              return IconButton(
                icon: Badge(
                  label: unreadCount > 0 ? Text(unreadCount.toString()) : null,
                  child: const Icon(Icons.inbox),
                ),
                tooltip: 'Inbox',
                onPressed: () {
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => InboxScreen(userId: widget.workerId, isWorker: true),
                    ),
                  );
                },
              );
            },
          ),
        ],
        bottom: TabBar(
          controller: _tabController,
          tabs: const [
            Tab(text: 'NEW REQUESTS'),
            Tab(text: 'UPCOMING'),
          ],
        ),
      ),
      body: DoodleBackground(
        child: TabBarView(
          controller: _tabController,
          children: [
            _buildNewRequestsList(),
            _buildAcceptedJobsList(),
          ],
        ),
      ),
    );
  }

  Widget _buildNewRequestsList() {
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('bookings')
          .where('workerId', isEqualTo: widget.workerId)
          .where('status', isEqualTo: 'Scheduled') // New requests awaiting approval
          .snapshots(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
          return const Center(child: Text('No new job requests.'));
        }

        List<DocumentSnapshot> docs = snapshot.data!.docs;
        // Sort by creation date (newest first)
        docs.sort((a, b) {
          Map<String, dynamic> dataA = a.data() as Map<String, dynamic>;
          Map<String, dynamic> dataB = b.data() as Map<String, dynamic>;
          Timestamp timeA = dataA['createdAt'];
          Timestamp timeB = dataB['createdAt'];
          return timeB.compareTo(timeA);
        });

        return ListView.builder(
          padding: const EdgeInsets.all(8),
          itemCount: docs.length,
          itemBuilder: (context, idx) {
            final booking = docs[idx];
            final data = booking.data() as Map<String, dynamic>;
            // Uses the dedicated card for job requests
            return JobRequestCard(bookingData: data, bookingId: booking.id, workerId: widget.workerId);
          },
        );
      },
    );
  }

  Widget _buildAcceptedJobsList() {
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('bookings')
          .where('workerId', isEqualTo: widget.workerId)
          .where('status', isEqualTo: 'Accepted') // Accepted jobs are upcoming
          .snapshots(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
          return const Center(child: Text('You have no upcoming jobs.'));
        }

        List<DocumentSnapshot> docs = snapshot.data!.docs;
        // Sort by booking date (earliest first)
        docs.sort((a, b) {
          Map<String, dynamic> dataA = a.data() as Map<String, dynamic>;
          Map<String, dynamic> dataB = b.data() as Map<String, dynamic>;
          Timestamp timeA = dataA['bookingDate'];
          Timestamp timeB = dataB['bookingDate'];
          return timeA.compareTo(timeB);
        });

        return ListView.builder(
          padding: const EdgeInsets.all(8),
          itemCount: docs.length,
          itemBuilder: (context, idx) {
            final booking = docs[idx];
            final data = booking.data() as Map<String, dynamic>;
            // Uses the generic booking tile for accepted/upcoming jobs
            return BookingTile(bookingData: data, bookingId: booking.id);
          },
        );
      },
    );
  }
}
