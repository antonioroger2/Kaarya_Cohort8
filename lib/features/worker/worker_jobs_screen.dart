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
  late final Stream<QuerySnapshot> _unreadNotificationsStream;
  late final Stream<QuerySnapshot> _newRequestsStream;
  late Stream<QuerySnapshot> _acceptedJobsStream;

  // --- Filter State ---
  bool _isFurthestFirst = false;
  String _statusFilter = 'all'; 

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _unreadNotificationsStream = _buildUnreadNotificationsStream();
    _newRequestsStream = _buildNewRequestsStream();
    _acceptedJobsStream = _buildAcceptedJobsStream();
  }

  @override
  void didUpdateWidget(covariant WorkerJobsScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.workerId != widget.workerId) {
      _acceptedJobsStream = _buildAcceptedJobsStream();
    }
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Stream<QuerySnapshot> _buildUnreadNotificationsStream() {
    return FirebaseFirestore.instance
        .collection('notifications')
        .where('recipientId', isEqualTo: widget.workerId)
        .where('isRead', isEqualTo: false)
        .snapshots();
  }

  Stream<QuerySnapshot> _buildNewRequestsStream() {
    return FirebaseFirestore.instance
        .collectionGroup('workerRequests')
        .where('workerId', isEqualTo: widget.workerId)
        .where('status', isEqualTo: 'pending')
        .orderBy('createdAt', descending: true)
        .snapshots();
  }

  Stream<QuerySnapshot> _buildAcceptedJobsStream() {
    List<String> statusQuery;
    if (_statusFilter == 'accepted') {
      statusQuery = ['a1'];
    } else if (_statusFilter == 'inprogress') {
      statusQuery = ['w1', 'w2'];
    } else {
      statusQuery = ['a1', 'w1', 'w2'];
    }

    return FirebaseFirestore.instance
        .collection('bookings')
        .where('workerId', isEqualTo: widget.workerId)
        .where('status', whereIn: statusQuery)
        .orderBy('appointmentDate', descending: _isFurthestFirst)
        .snapshots();
  }

  void _refreshAcceptedJobsStream() {
    setState(() => _acceptedJobsStream = _buildAcceptedJobsStream());
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'My Jobs',
          style: TextStyle(
            fontWeight: FontWeight.w900,
            color: Colors.teal,
            fontSize: 18,
          ),
        ),
        foregroundColor: Colors.white,
        actions: [
          // Inbox Icon
          StreamBuilder<QuerySnapshot>(
            stream: _unreadNotificationsStream,
            builder: (context, snapshot) {
              final unreadCount = snapshot.data?.docs.length ?? 0;
              return IconButton(
                icon: Badge(
                  label: unreadCount > 0 ? Text(unreadCount.toString()) : null,
                  child: const Icon(Icons.inbox),
                ),
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

  // ==========================================
  // TAB 1: NEW REQUESTS (Sorted by Sent Time)
  // ==========================================
  Widget _buildNewRequestsList() {
    return StreamBuilder<QuerySnapshot>(
      stream: _newRequestsStream,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          debugPrint("REQUESTS ERROR: ${snapshot.error}");
          return Center(child: Text("Error: ${snapshot.error}"));
        }
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
          return const Center(child: Text('No new job requests.'));
        }

        return ListView.builder(
          padding: const EdgeInsets.all(8),
          itemCount: snapshot.data!.docs.length,
          itemBuilder: (context, idx) {
            final workerRequestDoc = snapshot.data!.docs[idx];
            final bookingRef = workerRequestDoc.reference.parent.parent;

            if (bookingRef == null) return const SizedBox.shrink();

            return FutureBuilder<DocumentSnapshot>(
              future: bookingRef.get(),
              builder: (context, bookingSnapshot) {
                if (!bookingSnapshot.hasData || !bookingSnapshot.data!.exists) {
                  return const SizedBox.shrink();
                }
                final data = bookingSnapshot.data!.data() as Map<String, dynamic>;
                return JobRequestCard(
                  bookingData: data,
                  bookingId: bookingSnapshot.data!.id,
                  workerId: widget.workerId,
                );
              },
            );
          },
        );
      },
    );
  }

  // ==========================================
  // TAB 2: UPCOMING JOBS (Sorted by APPOINTMENT DATE)
  // ==========================================
  Widget _buildAcceptedJobsList() {
    return Column(
      children: [
        _buildFilterBar(),
        Expanded(
          child: StreamBuilder<QuerySnapshot>(
            stream: _acceptedJobsStream,
            builder: (context, snapshot) {
              if (snapshot.hasError) {
                // --- LOOK IN YOUR DEBUG CONSOLE IF THIS ERROR APPEARS ---
                // It will provide a clickable link to generate the index
                debugPrint("--- INDEX ERROR ---");
                debugPrint(snapshot.error.toString());
                return Center(child: Text("Index missing. Check console."));
              }

              if (snapshot.connectionState == ConnectionState.waiting) {
                return const Center(child: CircularProgressIndicator());
              }

              if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
                return Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(Icons.calendar_today, size: 48, color: Colors.grey),
                      const SizedBox(height: 16),
                      const Text('No upcoming jobs found.', style: TextStyle(color: Colors.grey)),
                    ],
                  ),
                );
              }

              return ListView.builder(
                padding: const EdgeInsets.all(8),
                itemCount: snapshot.data!.docs.length,
                itemBuilder: (context, idx) {
                  final booking = snapshot.data!.docs[idx];
                  final data = booking.data() as Map<String, dynamic>;
                  return BookingTile(bookingData: data, bookingId: booking.id);
                },
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildFilterBar() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border(bottom: BorderSide(color: Colors.grey.shade200)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                _isFurthestFirst ? "Sorted: Furthest Away" : "Sorted: Soonest First",
                style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold),
              ),
              Text(
                "Filter: ${_statusFilter.toUpperCase()}",
                style: TextStyle(fontSize: 12, color: Colors.grey[600]),
              ),
            ],
          ),
          OutlinedButton.icon(
            onPressed: _showFilterBottomSheet,
            icon: const Icon(Icons.tune, size: 16),
            label: const Text("Filters"),
            style: OutlinedButton.styleFrom(
              visualDensity: VisualDensity.compact,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
            ),
          ),
        ],
      ),
    );
  }

  void _showFilterBottomSheet() {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) {
        return StatefulBuilder(
          builder: (BuildContext context, StateSetter setModalState) {
            return Padding(
              padding: const EdgeInsets.all(24.0),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text("Sort by Job Time", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 8,
                    children: [
                      FilterChip(
                        label: const Text("NEW"),
                        selected: !_isFurthestFirst,
                        onSelected: (val) {
                          setModalState(() => _isFurthestFirst = false);
                          _refreshAcceptedJobsStream();
                        },
                      ),
                      FilterChip(
                        label: const Text("OLD"),
                        selected: _isFurthestFirst,
                        onSelected: (val) {
                          setModalState(() => _isFurthestFirst = true);
                          _refreshAcceptedJobsStream();
                        },
                      ),
                    ],
                  ),
                  const SizedBox(height: 24),
                  const Text("Filter Status", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 8,
                    children: [
                      FilterChip(
                        label: const Text("All"),
                        selected: _statusFilter == 'all',
                        onSelected: (val) {
                          setModalState(() => _statusFilter = 'all');
                          _refreshAcceptedJobsStream();
                        },
                      ),
                      FilterChip(
                        label: const Text("Accepted"),
                        selected: _statusFilter == 'accepted',
                        onSelected: (val) {
                          setModalState(() => _statusFilter = 'accepted');
                          _refreshAcceptedJobsStream();
                        },
                      ),
                      FilterChip(
                        label: const Text("In Progress"),
                        selected: _statusFilter == 'inprogress',
                        onSelected: (val) {
                          setModalState(() => _statusFilter = 'inprogress');
                          _refreshAcceptedJobsStream();
                        },
                      ),
                    ],
                  ),
                  const SizedBox(height: 32),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: () => Navigator.pop(context),
                      child: const Text("Done"),
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }
}