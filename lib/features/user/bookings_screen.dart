import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../core/theme.dart'; 
import '../../features/shared/booking_tile.dart'; 

class BookingsScreen extends StatefulWidget {
  final String userId;
  const BookingsScreen({super.key, required this.userId});

  @override
  State<BookingsScreen> createState() => _BookingsScreenState();
}

class _BookingsScreenState extends State<BookingsScreen> with SingleTickerProviderStateMixin {
  late TabController _tabController;

  // false = Ascending (Soonest dates first) 
  // true = Descending (Furthest dates first)
  bool _isFurthestFirst = true; 

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
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
        title: const Text('My Bookings'),
        bottom: TabBar(
          controller: _tabController,
          tabs: const [
            Tab(text: 'UPCOMING'),
            Tab(text: 'PENDING'),
            Tab(text: 'HISTORY'),
          ],
        ),
      ),
      body: DoodleBackground(
        child: Column(
          children: [
            _buildFilterBar(),
            Expanded(
              child: TabBarView(
                controller: _tabController,
                children: [
                  // Upcoming
                  _buildBookingsList(['a1', 'w1', 'w2']), 
                  
                  // Pending
                  _buildBookingsList(['b1', 'b2']),       
                  
                  // History - FIXED: Added lowercase 'cancelled' and 'rejected'
                  _buildBookingsList(['e3', 'cancelled', 'rejected', 'Cancelled', 'Rejected']), 
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBookingsList(List<String> statuses) {
    // DEBUG TIP: If data is still missing, change 'appointmentDate' to 'createdAt' 
    // temporarily to see if the field is missing on your docs.
    
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('bookings')
          .where('userId', isEqualTo: widget.userId)
          .where('status', whereIn: statuses)
          // Ensure your backend is actually saving 'appointmentDate' on creation!
          .orderBy('appointmentDate', descending: _isFurthestFirst) 
          .snapshots(),
      builder: (context, snap) {
        // 1. CHECK FOR INDEX ERRORS
        if (snap.hasError) {
          debugPrint("Firestore Error: ${snap.error}");
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Text(
                "Database Error.\nCheck Debug Console for Index Link.\n\n${snap.error}",
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.red),
              ),
            ),
          );
        }

        if (snap.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }

        if (!snap.hasData || snap.data!.docs.isEmpty) {
          return _buildEmptyState(statuses);
        }

        final docs = snap.data!.docs;

        return ListView.builder(
          padding: const EdgeInsets.all(8),
          itemCount: docs.length,
          itemBuilder: (context, index) {
            final booking = docs[index];
            final data = booking.data() as Map<String, dynamic>;

            return BookingTile(
              bookingData: data,
              bookingId: booking.id,
            );
          },
        );
      },
    );
  }

  // ... (Filter Bar and Bottom Sheet code remains exactly the same as your previous snippet)
  Widget _buildFilterBar() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border(bottom: BorderSide(color: Colors.grey.shade200)),
        boxShadow: [
          BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 2, offset: const Offset(0, 2)),
        ],
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                _isFurthestFirst ? "Sorted: Descending" : "Sorted: Ascending",
                style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold),
              ),
              Text(
                "Ordered by Booking Date",
                style: TextStyle(fontSize: 12, color: Colors.grey[600]),
              ),
            ],
          ),
          OutlinedButton.icon(
            onPressed: _showFilterBottomSheet,
            icon: const Icon(Icons.tune, size: 16),
            label: const Text("Sort"),
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
              padding: const EdgeInsets.fromLTRB(24, 24, 24, 40),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text("Sort Order", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 8,
                    children: [
                      FilterChip(
                        label: const Text("Ascending"),
                        selected: !_isFurthestFirst,
                        showCheckmark: false,
                        onSelected: (val) {
                          setModalState(() => _isFurthestFirst = false);
                          setState(() {}); // Update parent
                        },
                      ),
                      FilterChip(
                        label: const Text("Descending"),
                        selected: _isFurthestFirst,
                        showCheckmark: false,
                        onSelected: (val) {
                          setModalState(() => _isFurthestFirst = true);
                          setState(() {}); // Update parent
                        },
                      ),
                    ],
                  ),
                  const SizedBox(height: 32),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        backgroundColor: Colors.black,
                        foregroundColor: Colors.white
                      ),
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

  Widget _buildEmptyState(List<String> statuses) {
    String message = "No bookings found.";
    IconData icon = Icons.calendar_today_outlined;

    if (statuses.contains('a1')) {
      message = "You have no upcoming bookings.";
      icon = Icons.event_available;
    } else if (statuses.contains('b2')) {
      message = "You have no pending requests.";
      icon = Icons.hourglass_empty;
    } else if (statuses.contains('e3')) {
      message = "You have no booking history.";
      icon = Icons.history;
    }

    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, size: 48, color: Colors.grey[400]),
          const SizedBox(height: 16),
          Text(message, style: TextStyle(color: Colors.grey[600])),
        ],
      ),
    );
  }
}