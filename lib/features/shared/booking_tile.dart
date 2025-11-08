// lib/features/shared/booking_tile.dart
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import '../../features/shared/booking_details_screen.dart';
import '../../features/shared/report_dialog.dart';

class BookingTile extends StatefulWidget {
  final Map<String, dynamic> bookingData;
  final String? bookingId; 
  
  const BookingTile({super.key, required this.bookingData, this.bookingId});

  @override
  State<BookingTile> createState() => _BookingTileState();
}

class _BookingTileState extends State<BookingTile> {
  bool _isCancelling = false;
  bool _isCompleting = false;

  String? get _currentBookingId => widget.bookingId ?? widget.bookingData['id'];

  Future<void> _cancelBooking() async {
    if (_currentBookingId == null) return;
    
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Cancel Booking'),
        content: const Text('Are you sure you want to cancel this booking? The worker will be notified.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('No'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Yes, Cancel'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    setState(() => _isCancelling = true);

    try {
      final batch = FirebaseFirestore.instance.batch();
      final bookingRef = FirebaseFirestore.instance.collection('bookings').doc(_currentBookingId);
      final isAccepted = widget.bookingData['status'] == 'Accepted';

      // 1. Update booking status
      batch.update(bookingRef, {
        'status': 'Cancelled',
        'remarks': FieldValue.arrayUnion([
          {
            'log': 'Client cancelled the booking.',
            'timestamp': Timestamp.now(),
            'type': 'cancellation'
          }
        ])
      });

      // 2. Update worker availability only if it was an accepted job
      if (isAccepted) {
        final workerRef = FirebaseFirestore.instance.collection('workers').doc(widget.bookingData['workerId']);
        batch.update(workerRef, {'availability': 'Y'});
      }

      // 3. Send notification to worker
      final notificationRef = FirebaseFirestore.instance.collection('notifications').doc();
      batch.set(notificationRef, {
        'recipientId': widget.bookingData['workerId'],
        'senderId': widget.bookingData['userId'],
        'type': 'booking_cancelled',
        'title': 'Booking Cancelled',
        'message': '${widget.bookingData['userInfo']?['name'] ?? 'A client'} has cancelled their booking scheduled for ${DateFormat('MMM d, yyyy \'at\' h:mm a').format((widget.bookingData['bookingDate'] as Timestamp).toDate())}.',
        'bookingId': _currentBookingId,
        'isRead': false,
        'createdAt': Timestamp.now(),
      });

      await batch.commit();

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Booking cancelled successfully. The worker has been notified.'),
          backgroundColor: Colors.orange,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to cancel booking: $e'),
          backgroundColor: Colors.red,
        ),
      );
    } finally {
      if (mounted) setState(() => _isCancelling = false);
    }
  }

  Future<void> _completeJob() async {
    if (_currentBookingId == null) return;
    
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Mark Job as Complete'),
        content: const Text('Are you sure you want to mark this job as completed? This action cannot be undone.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('No'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: TextButton.styleFrom(foregroundColor: Colors.green),
            child: const Text('Yes, Complete'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    setState(() => _isCompleting = true);

    try {
      final batch = FirebaseFirestore.instance.batch();
      final bookingRef = FirebaseFirestore.instance.collection('bookings').doc(_currentBookingId);
      final workerRef = FirebaseFirestore.instance.collection('workers').doc(widget.bookingData['workerId']);

      // 1. Update booking status
      batch.update(bookingRef, {
        'status': 'Completed',
        'completedAt': Timestamp.now(),
        'remarks': FieldValue.arrayUnion([
          {
            'log': 'Worker marked the job as completed.',
            'timestamp': Timestamp.now(),
            'type': 'completion'
          }
        ])
      });

      // 2. Update worker's stats and availability
      batch.update(workerRef, {
        'completedBookings': FieldValue.increment(1),
        'availability': 'Y' // Make worker available again
      });

      // 3. Send notification to customer (to prompt rating/confirmation)
      final notificationRef = FirebaseFirestore.instance.collection('notifications').doc();
      batch.set(notificationRef, {
        'recipientId': widget.bookingData['userId'],
        'senderId': widget.bookingData['workerId'],
        'type': 'job_completed',
        'title': 'Job Completed',
        'message': '${widget.bookingData['workerInfo']?['name'] ?? 'Your worker'} has completed the job scheduled for ${DateFormat('MMM d, yyyy \'at\' h:mm a').format((widget.bookingData['bookingDate'] as Timestamp).toDate())}. Please rate the service if you haven\'t already.',
        'bookingId': _currentBookingId,
        'isRead': false,
        'createdAt': Timestamp.now(),
      });

      await batch.commit();

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Job marked as completed successfully. The customer has been notified.'),
          backgroundColor: Colors.green,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to complete job: $e'),
          backgroundColor: Colors.red,
        ),
      );
    } finally {
      if (mounted) setState(() => _isCompleting = false);
    }
  }

  Future<void> _reportIssue(String reportType) async {
    final reportReason = await showDialog<String>(
      context: context,
      builder: (context) => ReportDialog(reportType: reportType),
    );

    if (reportReason == null || reportReason.isEmpty || _currentBookingId == null) return;

    try {
      final currentUserId = FirebaseAuth.instance.currentUser!.uid;
      
      // Determine the user being reported
      final reportedUserId = widget.bookingData['workerId'] == currentUserId
          ? widget.bookingData['userId']
          : widget.bookingData['workerId'];

      // Create report document
      await FirebaseFirestore.instance.collection('reports').add({
        'bookingId': _currentBookingId,
        'reporterId': currentUserId,
        'reportedUserId': reportedUserId,
        'reportType': reportType,
        'reason': reportReason,
        'status': 'Pending',
        'createdAt': Timestamp.now(),
        'bookingData': widget.bookingData,
      });

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Report submitted successfully. Our team will review it.'),
          backgroundColor: Colors.orange,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to submit report: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    // Get booking data
    final date = (widget.bookingData['bookingDate'] as Timestamp).toDate();
    final status = widget.bookingData['status'] ?? 'Unknown';
    final wage = (widget.bookingData['wage'] ?? 0).toInt();
    final workerName = widget.bookingData['workerInfo']?['name'] ?? 'Worker';
    final userName = widget.bookingData['userInfo']?['name'] ?? 'User';
    final currentUserIsWorker = FirebaseAuth.instance.currentUser!.uid == widget.bookingData['workerId'];
    
    // Status visualization
    Color statusColor;
    IconData statusIcon;
    switch (status) {
      case 'Completed': statusColor = Colors.green; statusIcon = Icons.check_circle; break;
      case 'Cancelled':
      case 'Rejected': statusColor = Colors.red; statusIcon = Icons.cancel; break;
      case 'Accepted': statusColor = Colors.blue; statusIcon = Icons.thumb_up; break;
      default: statusColor = Colors.orange; statusIcon = Icons.pending;
    }

    return InkWell(
      onTap: () {
        if (_currentBookingId != null) {
            Navigator.of(context).push(
                MaterialPageRoute(
                    builder: (_) => BookingDetailsScreen(
                        bookingId: _currentBookingId!,
                        userId: currentUserIsWorker ? widget.bookingData['workerId'] : widget.bookingData['userId'],
                        isWorker: currentUserIsWorker,
                    ),
                ),
            );
        }
      },
      child: Card(
        margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        child: Column(
          children: [
            // Status Header
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    statusColor.withOpacity(0.1),
                    statusColor.withOpacity(0.05),
                  ],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
              ),
              child: Row(
                children: [
                  Icon(statusIcon, color: statusColor),
                  const SizedBox(width: 8),
                  Text(
                    status,
                    style: TextStyle(
                      color: statusColor,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const Spacer(),
                  Text(
                    DateFormat('EEE, MMM d').format(date),
                    style: const TextStyle(
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),
            
            // Details
            Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Other Party Info
                  Row(
                    children: [
                      CircleAvatar(
                        backgroundColor: Colors.teal.withOpacity(0.1),
                        child: Icon(
                          currentUserIsWorker ? Icons.person : Icons.engineering,
                          color: Colors.teal,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            currentUserIsWorker ? 'Client' : 'Worker',
                            style: TextStyle(
                              color: Colors.grey[600],
                              fontSize: 12,
                            ),
                          ),
                          Text(
                            currentUserIsWorker ? userName : workerName,
                            style: const TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 16,
                            ),
                          ),
                        ],
                      ),
                      const Spacer(),
                      Icon(Icons.chevron_right, color: Colors.grey[400]),
                    ],
                  ),
                  
                  const Divider(height: 24),
                  
                  // Time and Wage Info
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Icon(Icons.schedule, size: 16, color: Colors.grey[600]),
                              const SizedBox(width: 4),
                              Text(
                                DateFormat.jm().format(date),
                                style: const TextStyle(fontWeight: FontWeight.w500),
                              ),
                            ],
                          ),
                          const SizedBox(height: 4),
                          Row(
                            children: [
                              Icon(Icons.timer, size: 16, color: Colors.grey[600]),
                              const SizedBox(width: 4),
                              Text(
                                '${widget.bookingData['timeSlot']} hours',
                                style: TextStyle(color: Colors.grey[600]),
                              ),
                            ],
                          ),
                        ],
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 8,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.green.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Text(
                          '₹$wage',
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 18,
                            color: Colors.green,
                          ),
                        ),
                      ),
                    ],
                  ),
                  
                  // Conditional Buttons (Actions)
                  // Cancel & Report (Client/User View for Scheduled/Accepted)
                  if (!currentUserIsWorker && (status == 'Scheduled' || status == 'Accepted') && !_isCancelling)
                    Padding(
                      padding: const EdgeInsets.only(top: 16),
                      child: Row(
                        children: [
                          Expanded(
                            child: OutlinedButton.icon(
                              onPressed: _cancelBooking,
                              style: OutlinedButton.styleFrom(
                                foregroundColor: Colors.red,
                                side: const BorderSide(color: Colors.red),
                              ),
                              icon: const Icon(Icons.cancel),
                              label: const Text('Cancel'),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: OutlinedButton.icon(
                              onPressed: () => _reportIssue('Client reporting issue with worker'),
                              style: OutlinedButton.styleFrom(
                                foregroundColor: Colors.orange,
                                side: const BorderSide(color: Colors.orange),
                              ),
                              icon: const Icon(Icons.report),
                              label: const Text('Report'),
                            ),
                          ),
                        ],
                      ),
                    ),
                    
                  // Complete & Report (Worker View for Accepted)
                  if (currentUserIsWorker && status == 'Accepted' && !_isCompleting)
                    Padding(
                      padding: const EdgeInsets.only(top: 16),
                      child: Row(
                        children: [
                          Expanded(
                            child: ElevatedButton.icon(
                              onPressed: _completeJob,
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.green,
                                foregroundColor: Colors.white,
                              ),
                              icon: const Icon(Icons.check_circle),
                              label: const Text('Complete'),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: OutlinedButton.icon(
                              onPressed: () => _reportIssue('Worker reporting issue with client'),
                              style: OutlinedButton.styleFrom(
                                foregroundColor: Colors.orange,
                                side: const BorderSide(color: Colors.orange),
                              ),
                              icon: const Icon(Icons.report),
                              label: const Text('Report'),
                            ),
                          ),
                        ],
                      ),
                    ),
                    
                  // Loading Indicator
                  if (_isCancelling || _isCompleting)
                    const Padding(
                      padding: EdgeInsets.only(top: 16),
                      child: Center(
                        child: CircularProgressIndicator(),
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
