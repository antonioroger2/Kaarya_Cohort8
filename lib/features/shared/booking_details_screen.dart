// lib/features/shared/booking_details_screen.dart
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import '../../core/theme.dart';

class BookingDetailsScreen extends StatelessWidget {
  final String bookingId;
  final String userId;
  final bool isWorker;

  const BookingDetailsScreen({
    super.key,
    required this.bookingId,
    required this.userId,
    required this.isWorker,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Booking Details'),
      ),
      body: DoodleBackground(
        child: StreamBuilder<DocumentSnapshot>(
          stream: FirebaseFirestore.instance.collection('bookings').doc(bookingId).snapshots(),
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Center(child: CircularProgressIndicator());
            }
            if (!snapshot.hasData || !snapshot.data!.exists) {
              return const Center(child: Text('Booking not found'));
            }

            final bookingData = snapshot.data!.data() as Map<String, dynamic>;
            final date = (bookingData['bookingDate'] as Timestamp).toDate();
            final status = bookingData['status'] ?? 'Unknown';
            final wage = (bookingData['wage'] ?? 0).toInt();
            final workerName = bookingData['workerInfo']?['name'] ?? 'Worker';
            final userName = bookingData['userInfo']?['name'] ?? 'User';
            final timeSlot = bookingData['timeSlot'] ?? 1;

            Color statusColor;
            switch (status) {
              case 'Completed': statusColor = Colors.green; break;
              case 'Cancelled':
              case 'Rejected': statusColor = Colors.red; break;
              case 'Accepted': statusColor = Colors.blue; break;
              default: statusColor = Colors.orange;
            }

            return SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Status Card
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Booking Status', style: Theme.of(context).textTheme.titleMedium),
                          const SizedBox(height: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                            decoration: BoxDecoration(
                              color: statusColor.withOpacity(0.1),
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: Text(
                              status,
                              style: TextStyle(
                                color: statusColor,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),

                  // Service Details
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Service Details', style: Theme.of(context).textTheme.titleMedium),
                          const SizedBox(height: 12),
                          Row(
                            children: [
                              const Icon(Icons.calendar_today, color: Colors.teal),
                              const SizedBox(width: 8),
                              Text(DateFormat('EEEE, MMMM d, yyyy').format(date)),
                            ],
                          ),
                          const SizedBox(height: 8),
                          Row(
                            children: [
                              const Icon(Icons.schedule, color: Colors.teal),
                              const SizedBox(width: 8),
                              Text(DateFormat.jm().format(date)),
                            ],
                          ),
                          const SizedBox(height: 8),
                          Row(
                            children: [
                              const Icon(Icons.timer, color: Colors.teal),
                              const SizedBox(width: 8),
                              Text('$timeSlot hours'),
                            ],
                          ),
                          const SizedBox(height: 8),
                          Row(
                            children: [
                              const Icon(Icons.currency_rupee, color: Colors.green),
                              const SizedBox(width: 8),
                              Text('₹$wage', style: const TextStyle(color: Colors.green, fontWeight: FontWeight.bold)),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),

                  // User/Worker Information
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(isWorker ? 'Client Information' : 'Worker Information', style: Theme.of(context).textTheme.titleMedium),
                          const SizedBox(height: 12),
                          Row(
                            children: [
                              CircleAvatar(
                                backgroundColor: Colors.teal.withOpacity(0.1),
                                child: Icon(isWorker ? Icons.person : Icons.engineering, color: Colors.teal),
                              ),
                              const SizedBox(width: 12),
                              Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    isWorker ? userName : workerName,
                                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                                  ),
                                  Text(
                                    isWorker ? 'Client' : 'Service Provider',
                                    style: TextStyle(color: Colors.grey[600]),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}