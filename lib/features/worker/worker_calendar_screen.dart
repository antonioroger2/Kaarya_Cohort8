import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import '../../core/theme.dart';
import '../../features/shared/inbox_screen.dart';
import '../../features/shared/booking_details_screen.dart'; 

class WorkerCalendarScreen extends StatefulWidget {
  final String workerId;
  const WorkerCalendarScreen({super.key, required this.workerId});

  @override
  State<WorkerCalendarScreen> createState() => _WorkerCalendarScreenState();
}

class _WorkerCalendarScreenState extends State<WorkerCalendarScreen> {
  DateTime _selectedDate = DateTime.now();

  // --- MODIFIED SECTION ---
  // Helper: Generate dates starting from Yesterday (Today - 1)
  List<DateTime> _getDaysInWindow() {
    final now = DateTime.now();
    // Generate 31 days total (Yesterday + Today + 29 future days)
    // index 0 = now - 1 day (Yesterday)
    return List.generate(31, (index) => now.subtract(const Duration(days: 1)).add(Duration(days: index)));
  }
  // ------------------------

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Calendar',
              style: TextStyle(
                fontWeight: FontWeight.w900,
                color: Colors.teal,
                fontSize: 18,
              ),
            ),
            Text(
              DateFormat('MMMM yyyy').format(_selectedDate),
              style: TextStyle(fontSize: 12, color: Colors.grey[600]),
            ),
          ],
        ),
        elevation: 0,
        backgroundColor: Colors.white,
        iconTheme: IconThemeData(color: Colors.black),
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
                  child: const Icon(Icons.notifications_outlined),
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
      ),
      body: DoodleBackground(
        child: Column(
          children: [
            // 1. Horizontal Calendar (Sits on top of doodle)
            _buildHorizontalCalendar(),

            // 2. Job List
            Expanded(
              child: StreamBuilder<QuerySnapshot>(
                stream: FirebaseFirestore.instance
                    .collection('bookings')
                    .where('workerId', isEqualTo: widget.workerId)
                    .where('status', whereIn: ['Accepted', 'Completed', 'a1', 'w1', 'w2', 'e1', 'e2', 'e3']) 
                    .snapshots(),
                builder: (context, snapshot) {
                  if (snapshot.hasError) {
                    return Center(child: Text("Error: ${snapshot.error}"));
                  }
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return const Center(child: CircularProgressIndicator());
                  }

                  final allBookings = snapshot.data?.docs ?? [];

                  // Filter locally for the selected date
                  final selectedDayBookings = allBookings.where((doc) {
                    final data = doc.data() as Map<String, dynamic>;
                    
                    DateTime? jobDate;
                    
                    if (data['appointmentDate'] is Timestamp) {
                      jobDate = (data['appointmentDate'] as Timestamp).toDate();
                    } else if (data['bookingDate'] is Timestamp) {
                      jobDate = (data['bookingDate'] as Timestamp).toDate();
                    } else if (data['date'] is String) {
                      try {
                        jobDate = DateFormat('yyyy-MM-dd').parse(data['date']);
                      } catch (e) { return false; }
                    }

                    if (jobDate == null) return false;
                    return DateUtils.isSameDay(jobDate, _selectedDate);
                  }).toList();

                  // Sort by time
                  selectedDayBookings.sort((a, b) {
                     final dataA = a.data() as Map<String, dynamic>;
                     final dataB = b.data() as Map<String, dynamic>;
                     int hourA = dataA['startHour'] ?? 0;
                     int hourB = dataB['startHour'] ?? 0;
                     return hourA.compareTo(hourB); 
                  });

                  if (selectedDayBookings.isEmpty) {
                    return _buildEmptyState();
                  }

                  return ListView.builder(
                    padding: const EdgeInsets.fromLTRB(16, 16, 16, 80),
                    itemCount: selectedDayBookings.length,
                    itemBuilder: (context, idx) {
                      return _buildJobCard(selectedDayBookings[idx]);
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

  // --- WIDGET: Horizontal Calendar Strip ---
  Widget _buildHorizontalCalendar() {
    final days = _getDaysInWindow();
    
    return Container(
      height: 100,
      decoration: BoxDecoration(
        color: Colors.white, 
        boxShadow: [
          BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 10, offset: const Offset(0, 5)),
        ],
      ),
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        itemCount: days.length,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 16),
        itemBuilder: (context, index) {
          final date = days[index];
          final isSelected = DateUtils.isSameDay(date, _selectedDate);
          final isToday = DateUtils.isSameDay(date, DateTime.now());

          return GestureDetector(
            onTap: () {
              setState(() => _selectedDate = date);
            },
            child: Container(
              width: 60,
              margin: const EdgeInsets.symmetric(horizontal: 4),
              decoration: BoxDecoration(
                color: isSelected ? Colors.black : (isToday ? Colors.grey[100] : Colors.transparent),
                borderRadius: BorderRadius.circular(16),
                border: isToday && !isSelected ? Border.all(color: Colors.grey.shade300) : null,
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    DateFormat('E').format(date).toUpperCase(),
                    style: TextStyle(
                      fontSize: 12,
                      color: isSelected ? Colors.white70 : Colors.grey,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    DateFormat('d').format(date),
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: isSelected ? Colors.white : Colors.black87,
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  // --- WIDGET: Job Card ---
  Widget _buildJobCard(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    
    DateTime date;
    if (data['appointmentDate'] is Timestamp) {
      date = (data['appointmentDate'] as Timestamp).toDate();
    } else if (data['bookingDate'] is Timestamp) {
      date = (data['bookingDate'] as Timestamp).toDate();
    } else if (data['date'] is String) {
      try {
        date = DateFormat('yyyy-MM-dd').parse(data['date']);
      } catch (_) {
        date = DateTime.now();
      }
    } else {
      date = DateTime.now(); 
    }

    if (data.containsKey('startHour')) {
      date = DateTime(date.year, date.month, date.day, data['startHour']);
    }

    final userName = data['userInfo']?['name'] ?? data['userName'] ?? 'Client';
    final rawStatus = data['status'] ?? 'Unknown';
    final wage = data['wage'] ?? 0;
    
    bool isCompleted = (rawStatus == 'Completed' || rawStatus == 'e3');
    String displayStatus = isCompleted ? 'Completed' : 'Scheduled';
    Color statusColor = isCompleted ? Colors.green : Colors.blue.shade700;
    Color bgColor = isCompleted ? Colors.green.shade50 : Colors.blue.shade50;

    return GestureDetector(
      onTap: () {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => BookingDetailsScreen(
              bookingId: doc.id,
              userId: data['userId'],
              isWorker: true,
            ),
          ),
        );
      },
      child: Container(
        margin: const EdgeInsets.only(bottom: 16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: Colors.grey.shade200),
          boxShadow: [
            BoxShadow(color: Colors.grey.withOpacity(0.08), blurRadius: 15, offset: const Offset(0, 4)),
          ],
        ),
        child: Column(
          children: [
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: bgColor,
                borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    children: [
                      Icon(Icons.access_time_filled, size: 18, color: statusColor),
                      const SizedBox(width: 8),
                      Text(
                        DateFormat('hh:mm a').format(date),
                        style: TextStyle(fontWeight: FontWeight.bold, color: statusColor, fontSize: 15),
                      ),
                    ],
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      displayStatus.toUpperCase(),
                      style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: statusColor),
                    ),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  CircleAvatar(
                    radius: 24,
                    backgroundColor: Colors.grey[200],
                    child: const Icon(Icons.person, color: Colors.grey),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(userName, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                        const SizedBox(height: 4),
                        Text("Payment: ₹$wage", style: TextStyle(color: Colors.grey[600], fontSize: 13)),
                      ],
                    ),
                  ),
                  const Icon(Icons.chevron_right, color: Colors.grey),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.9), 
              shape: BoxShape.circle,
            ),
            child: Icon(Icons.event_available_rounded, size: 48, color: Colors.grey[400]),
          ),
          const SizedBox(height: 24),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.9),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text(
              'No jobs on ${DateFormat('MMM d').format(_selectedDate)}',
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.black54),
            ),
          ),
        ],
      ),
    );
  }
}