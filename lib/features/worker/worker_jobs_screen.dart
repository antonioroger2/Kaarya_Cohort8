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
          // ... (existing actions)
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
    // --- DEBUG PRINT ---
    debugPrint("--- [WorkerJobsScreen] Building NEW REQUESTS list for workerId: ${widget.workerId} ---");

    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collectionGroup('workerRequests')
          .where('workerId', isEqualTo: widget.workerId)
          .where('status', isEqualTo: 'pending')
          .snapshots(),
      builder: (context, snapshot) {
        
        if (snapshot.hasError) {
          // --- DEBUG PRINT ---
          debugPrint("--- [WorkerJobsScreen] STREAM ERROR: ${snapshot.error} ---");
          return Center(child: Text("Error: ${snapshot.error}"));
        }
        
        if (snapshot.connectionState == ConnectionState.waiting) {
          // --- DEBUG PRINT ---
          debugPrint("--- [WorkerJobsScreen] Stream waiting...");
          return const Center(child: CircularProgressIndicator());
        }

        if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
          // --- DEBUG PRINT ---
          debugPrint("--- [WorkerJobsScreen] Stream success, but no data. hasData: ${snapshot.hasData}, isEmpty: ${snapshot.data?.docs.isEmpty} ---");
          return const Center(child: Text('No new job requests.'));
        }

        List<DocumentSnapshot> docs = snapshot.data!.docs;
        
        // --- DEBUG PRINT ---
        debugPrint("--- [WorkerJobsScreen] Stream FOUND ${docs.length} job request(s) ---");

        docs.sort((a, b) {
          Timestamp timeA = (a.data() as Map<String, dynamic>)['sentAt'] ?? Timestamp.now();
          Timestamp timeB = (b.data() as Map<String, dynamic>)['sentAt'] ?? Timestamp.now();
          return timeB.compareTo(timeA); // Newest first
        });

        return ListView.builder(
          padding: const EdgeInsets.all(8),
          itemCount: docs.length,
          itemBuilder: (context, idx) {
            final workerRequestDoc = docs[idx];
            final bookingRef = workerRequestDoc.reference.parent.parent;

            if (bookingRef == null) {
              debugPrint("--- [WorkerJobsScreen] ERROR: workerRequestDoc has no parent booking? Path: ${workerRequestDoc.reference.path} ---");
              return const SizedBox.shrink();
            }

            // --- DEBUG PRINT ---
            debugPrint("--- [WorkerJobsChecklist] FutureBuilder trying to GET: ${bookingRef.path} ---");

            return FutureBuilder<DocumentSnapshot>(
              future: bookingRef.get(),
              builder: (context, bookingSnapshot) {
                
                if (bookingSnapshot.hasError) {
                  // --- DEBUG PRINT ---
                  debugPrint("--- [WorkerJobsScreen] FUTURE BUILDER ERROR: ${bookingSnapshot.error} ---");
                  debugPrint("--- [WorkerJobsScreen] THIS IS LIKELY A SECURITY RULE FAILURE ON THE 'bookings' COLLECTION ---");
                  return Card(child: Padding(padding: const EdgeInsets.all(16.0), child: Text("Error loading booking: ${bookingSnapshot.error}", style: const TextStyle(color: Colors.red))));
                }
                
                if (bookingSnapshot.connectionState == ConnectionState.waiting) {
                  return const Card(child: Padding(padding: EdgeInsets.all(16.0), child: Center(child: CircularProgressIndicator())));
                }

                if (!bookingSnapshot.hasData || !bookingSnapshot.data!.exists) {
                   // --- DEBUG PRINT ---
                  debugPrint("--- [WorkerJobsScreen] FUTURE BUILDER ERROR: Booking doc not found at ${bookingRef.path}. This shouldn't happen. ---");
                  return const Card(child: Padding(padding: EdgeInsets.all(16.0), child: Text('Error: Booking data not found.')));
                }

                // --- DEBUG PRINT ---
                debugPrint("--- [WorkerJobsScreen] FutureBuilder SUCCESS for ${bookingRef.path} ---");
                
                final data = bookingSnapshot.data!.data() as Map<String, dynamic>;
                return JobRequestCard(
                  bookingData: data, 
                  bookingId: bookingSnapshot.data!.id, 
                  workerId: widget.workerId
                );
              },
            );
          },
        );
      },
    );
  }

  Widget _buildAcceptedJobsList() {
    // This query is simpler and likely works, but we add debug lines just in case.
    // --- DEBUG PRINT ---
    debugPrint("--- [WorkerJobsScreen] Building ACCEPTED list for workerId: ${widget.workerId} ---");

    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('bookings')
          .where('workerId', isEqualTo: widget.workerId)
          .where('status', whereIn: ['a1', 'w1', 'w2'])
          .snapshots(),
      builder: (context, snapshot) {
        
        if (snapshot.hasError) {
          debugPrint("--- [WorkerJobsScreen] ACCEPTED JOBS STREAM ERROR: ${snapshot.error} ---");
          return Center(child: Text("Error: ${snapshot.error}"));
        }

        if (snapshot.connectionState == ConnectionState.waiting) {
          debugPrint("--- [WorkerJobsScreen] Accepted stream waiting...");
          return const Center(child: CircularProgressIndicator());
        }

        if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
          debugPrint("--- [WorkerJobsScreen] Accepted stream success, but no data. ---");
          return const Center(child: Text('You have no upcoming jobs.'));
        }

        List<DocumentSnapshot> docs = snapshot.data!.docs;
        debugPrint("--- [WorkerJobsScreen] Accepted stream FOUND ${docs.length} job(s) ---");

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
            return BookingTile(bookingData: data, bookingId: booking.id);
          },
        );
      },
    );
  }
}