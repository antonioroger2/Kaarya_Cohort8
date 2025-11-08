// lib/features/worker/worker_calendar_screen.dart
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import '../../core/theme.dart';
import '../../features/shared/inbox_screen.dart';

class WorkerCalendarScreen extends StatefulWidget {
  final String workerId;
  const WorkerCalendarScreen({super.key, required this.workerId});

  @override
  State<WorkerCalendarScreen> createState() => _WorkerCalendarScreenState();
}

class _WorkerCalendarScreenState extends State<WorkerCalendarScreen> {
  DateTime _selectedDate = DateTime.now();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('My Schedule'),
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
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(4),
          child: Container(
            height: 4,
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                colors: [Colors.teal, Colors.blue],
                begin: Alignment.centerLeft,
                end: Alignment.centerRight,
              ),
            ),
          ),
        ),
      ),
      body: DoodleBackground(
        child: Column(
          children: [
            // CalendarDatePicker Widget
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white,
                boxShadow: [
                  BoxShadow(
                    color: Colors.grey.withOpacity(0.1),
                    blurRadius: 10,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: CalendarDatePicker(
                initialDate: _selectedDate,
                firstDate: DateTime(2020),
                lastDate: DateTime(2030),
                onDateChanged: (newDate) => setState(() => _selectedDate = newDate),
              ),
            ),

            // Daily Schedule List
            Expanded(
              child: StreamBuilder<QuerySnapshot>(
                // Fetch all relevant bookings for the worker
                stream: FirebaseFirestore.instance
                    .collection('bookings')
                    .where('workerId', isEqualTo: widget.workerId)
                    .where('status', whereIn: ['Accepted', 'Completed']) // Show accepted and completed jobs
                    .snapshots(),
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return const Center(child: CircularProgressIndicator());
                  }

                  final bookings = snapshot.data?.docs ?? [];
                  
                  // Filter bookings for the selected day
                  final selectedDayBookings = bookings.where((doc) {
                    final data = doc.data() as Map<String, dynamic>;
                    final bookingDate = (data['bookingDate'] as Timestamp).toDate();
                    return DateUtils.isSameDay(bookingDate, _selectedDate);
                  }).toList();
                  
                  // Sort by time
                  selectedDayBookings.sort((a, b) {
                      final timeA = (a.data() as Map<String, dynamic>)['bookingDate'] as Timestamp;
                      final timeB = (b.data() as Map<String, dynamic>)['bookingDate'] as Timestamp;
                      return timeA.compareTo(timeB);
                  });

                  if (selectedDayBookings.isEmpty) {
                    return Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.event_available, size: 64, color: Colors.grey[400]),
                          const SizedBox(height: 16),
                          Text(
                            'No jobs scheduled for\n${DateFormat('EEEE, MMMM d').format(_selectedDate)}',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontSize: 16,
                              color: Colors.grey[600],
                            ),
                          ),
                        ],
                      ),
                    );
                  }

                  return ListView.builder(
                    padding: const EdgeInsets.all(16),
                    itemCount: selectedDayBookings.length,
                    itemBuilder: (context, idx) {
                      final data = selectedDayBookings[idx].data() as Map<String, dynamic>;
                      final bookingDate = (data['bookingDate'] as Timestamp).toDate();
                      final userName = data['userInfo']?['name'] ?? 'Client';
                      final status = data['status'];
                      final wage = (data['wage'] ?? 0).toInt();
                      final timeSlot = data['timeSlot'];
                      
                      Color statusColor = status == 'Completed' ? Colors.green : Colors.blue;

                      // Display a simplified card for the schedule view
                      return Card(
                        margin: const EdgeInsets.only(bottom: 12),
                        child: Container(
                          decoration: BoxDecoration(
                            border: Border(
                              left: BorderSide(
                                color: statusColor,
                                width: 4,
                              ),
                            ),
                          ),
                          child: Padding(
                            padding: const EdgeInsets.all(16),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    CircleAvatar(
                                      backgroundColor: Colors.indigo.withOpacity(0.1),
                                      child: const Icon(Icons.person, color: Colors.indigo),
                                    ),
                                    const SizedBox(width: 12),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            userName,
                                            style: const TextStyle(
                                              fontWeight: FontWeight.bold,
                                              fontSize: 16,
                                            ),
                                          ),
                                          Text(
                                            status,
                                            style: TextStyle(
                                              color: statusColor,
                                              fontSize: 14,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 12,
                                        vertical: 6,
                                      ),
                                      decoration: BoxDecoration(
                                        color: Colors.green.withOpacity(0.1),
                                        borderRadius: BorderRadius.circular(20),
                                      ),
                                      child: Text(
                                        '₹$wage',
                                        style: const TextStyle(
                                          color: Colors.green,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                                const Divider(height: 24),
                                Row(
                                  children: [
                                    Icon(Icons.schedule,
                                        size: 16, color: Colors.grey[600]),
                                    const SizedBox(width: 8),
                                    Text(
                                      DateFormat.jm().format(bookingDate),
                                      style: const TextStyle(
                                        fontWeight: FontWeight.w500,
                                      ),
                                    ),
                                    const SizedBox(width: 16),
                                    Icon(Icons.timer,
                                        size: 16, color: Colors.grey[600]),
                                    const SizedBox(width: 8),
                                    Text(
                                      '$timeSlot hours',
                                      style: TextStyle(color: Colors.grey[600]),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        ),
                      );
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}
