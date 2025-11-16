// lib/features/user/bookings_screen.dart
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
        child: TabBarView(
          controller: _tabController,
          children: [

            _buildBookingsList(['a1', 'w1', 'w2']),

            _buildBookingsList(['b1', 'b2']),

            _buildBookingsList(['e3', 'Cancelled', 'Rejected']),

          ],
        ),
      ),
    );
  }

  Widget _buildBookingsList(List<String> statuses) {
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('bookings')
          .where('userId', isEqualTo: widget.userId)
          .where('status', whereIn: statuses)
          .snapshots(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
          String message;

          if (statuses.contains('a1')) {
            message = "You have no upcoming bookings.";
          } else if (statuses.contains('b2')) {
            message = "You have no pending booking requests.";
          } else {
            message = "You have no past bookings.";
          }

          return Center(child: Text(message));
        }

        List<DocumentSnapshot> docs = snapshot.data!.docs;

        docs.sort((a, b) {
          Map<String, dynamic> dataA = a.data() as Map<String, dynamic>;
          Map<String, dynamic> dataB = b.data() as Map<String, dynamic>;
          Timestamp timeA = dataA['bookingDate'] ?? dataA['createdAt'];
          Timestamp timeB = dataB['bookingDate'] ?? dataB['createdAt'];

          if (statuses.contains('a1')) {
            return timeA.compareTo(timeB); 
          }

          return timeB.compareTo(timeA); 
        });

        return ListView.builder(
          padding: const EdgeInsets.all(8),
          itemCount: docs.length,
          itemBuilder: (context, idx) {
            final booking = docs[idx];
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
}