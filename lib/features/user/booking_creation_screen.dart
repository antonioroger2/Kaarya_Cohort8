// lib/features/user/booking_creation_screen.dart
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';

class BookingCreationScreen extends StatefulWidget {
  final String userId;
  final String workerId;
  final String workerName;
  final String workerPhone;

  const BookingCreationScreen({
    super.key, 
    required this.userId, 
    required this.workerId, 
    required this.workerName,
    required this.workerPhone,
  });

  @override
  State<BookingCreationScreen> createState() => _BookingCreationScreenState();
}

class _BookingCreationScreenState extends State<BookingCreationScreen> {
  DateTime _selectedDate = DateTime.now().add(const Duration(days: 1));
  TimeOfDay _selectedTime = const TimeOfDay(hour: 9, minute: 0);
  int _hours = 2;
  bool _isLoading = false;

  Future<void> _confirmBooking() async {
    setState(() => _isLoading = true);

    try {
      final workerSnap = await FirebaseFirestore.instance.collection('workers').doc(widget.workerId).get();
      final userSnap = await FirebaseFirestore.instance.collection('users').doc(widget.userId).get();

      if (!workerSnap.exists || !userSnap.exists) {
        throw Exception("User or worker not found.");
      }

      final workerData = workerSnap.data()!;
      final userData = userSnap.data()!;
      
      final hourlyRate = (workerData['perHourCharge'] ?? 500).toDouble();
      final wage = hourlyRate * _hours;
      
      final bookingDateTime = DateTime(
          _selectedDate.year, 
          _selectedDate.month, 
          _selectedDate.day, 
          _selectedTime.hour, 
          _selectedTime.minute
      );
      
      final newBookingRef = FirebaseFirestore.instance.collection('bookings').doc();

      // Create Booking
      await newBookingRef.set({
        'id': newBookingRef.id,
        'userId': widget.userId,
        'workerId': widget.workerId,
        'userInfo': {
          'name': userData['name'],
          'phone': userData['phone'],
        },
        'workerInfo': {
          'name': workerData['name'],
          'phone': workerData['phone'],
        },
        'bookingDate': Timestamp.fromDate(bookingDateTime),
        'timeSlot': _hours,
        'bookingType': 'Hourly',
        'wage': wage,
        'status': 'Scheduled', // Initial status: Awaiting worker acceptance
        'createdAt': Timestamp.now(),
        'remarks': [
          { 'log': 'Booking created by user.', 'timestamp': Timestamp.now() }
        ],
        'rating': 0,
        'review': ''
      });

      // Send Notification to Worker
      await FirebaseFirestore.instance.collection('notifications').add({
          'recipientId': widget.workerId,
          'senderId': widget.userId,
          'type': 'new_booking_request',
          'title': 'New Booking Request!',
          'message': 'You have a new job request from ${userData['name']} for ${DateFormat('MMM d, h:mm a').format(bookingDateTime)}.',
          'bookingId': newBookingRef.id,
          'isRead': false,
          'createdAt': Timestamp.now(),
      });

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Booking request sent to worker!'), backgroundColor: Colors.green,));
      Navigator.of(context).pop();

    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e'), backgroundColor: Colors.redAccent,));
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('Book ${widget.workerName}')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Select Date', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
            const SizedBox(height: 12),
            Card(
              child: ListTile(
                leading: const Icon(Icons.calendar_today),
                title: Text(DateFormat('MMMM dd, yyyy').format(_selectedDate)),
                trailing: const Icon(Icons.arrow_drop_down),
                onTap: () async {
                  final picked = await showDatePicker(
                    context: context,
                    initialDate: _selectedDate,
                    firstDate: DateTime.now(),
                    lastDate: DateTime.now().add(const Duration(days: 30)),
                  );
                  if (picked != null) {
                    setState(() => _selectedDate = picked);
                  }
                },
              ),
            ),
            
            const SizedBox(height: 20),
            
            const Text('Select Start Time', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
            const SizedBox(height: 12),
            Card(
              child: ListTile(
                leading: const Icon(Icons.schedule),
                title: Text(_selectedTime.format(context)),
                trailing: const Icon(Icons.arrow_drop_down),
                onTap: () async {
                  final picked = await showTimePicker(
                    context: context,
                    initialTime: _selectedTime,
                  );
                  if (picked != null) {
                    setState(() => _selectedTime = picked);
                  }
                },
              ),
            ),
            
            const SizedBox(height: 20),
            
            const Text('Select Duration (Hours)', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
            const SizedBox(height: 12),
            Card(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                child: Row(
                  children: [
                    IconButton(
                      onPressed: _hours > 1 ? () => setState(() => _hours--) : null,
                      icon: const Icon(Icons.remove_circle_outline),
                    ),
                    Expanded(
                      child: Text('$_hours hours', textAlign: TextAlign.center, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                    ),
                    IconButton(
                      onPressed: () => setState(() => _hours++),
                      icon: const Icon(Icons.add_circle_outline),
                    ),
                  ],
                ),
              ),
            ),
            
            const SizedBox(height: 40),
            
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _isLoading ? null : _confirmBooking,
                style: ElevatedButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 16)),
                child: _isLoading
                    ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white,))
                    : const Text('Send Booking Request'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
