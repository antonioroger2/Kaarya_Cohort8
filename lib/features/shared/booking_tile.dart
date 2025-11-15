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
  // --- REMOVED: _isCompleting ---

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
      
      // --- MODIFIED: Use new status code ---
      final isAccepted = widget.bookingData['status'] == 'a1';

      // 1. Update booking status
      batch.update(bookingRef, {
        'status': 'Cancelled',
        'log.actions': FieldValue.arrayUnion([ // --- MODIFIED: Log to new structure ---
          {
            'log': 'Client cancelled the booking.',
            'timestamp': Timestamp.now(),
            'actor': widget.bookingData['userId'],
            'action': 'cancelled'
          }
        ])
      });

      // --- REMOVED: Worker availability update ---
      // This logic is now handled by the server's bitmask and is too
      // complex to replicate in the app during a cancellation.
      // A server-side "cancel" endpoint would be required to do this safely.

      // 3. Send notification to worker
      final notificationRef = FirebaseFirestore.instance.collection('notifications').doc();
      // --- MODIFIED: Get user name from booking data if available ---
      final userName = widget.bookingData['userInfo']?['name'] ?? widget.bookingData['userName'] ?? 'A client';
      final bookingDate = (widget.bookingData['bookingDate'] as Timestamp).toDate();

      batch.set(notificationRef, {
        'recipientId': widget.bookingData['workerId'],
        'senderId': widget.bookingData['userId'],
        'type': 'booking_cancelled',
        'title': 'Booking Cancelled',
        'message': '$userName has cancelled their booking scheduled for ${DateFormat('MMM d, yyyy \'at\' h:mm a').format(bookingDate)}.',
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

  // --- REMOVED: _completeJob function ---

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
    final workerName = widget.bookingData['workerInfo']?['name'] ?? widget.bookingData['workerName'] ?? 'Worker';
    final userName = widget.bookingData['userInfo']?['name'] ?? widget.bookingData['userName'] ?? 'User';
    final currentUserIsWorker = FirebaseAuth.instance.currentUser!.uid == widget.bookingData['workerId'];
    
    // Status visualization
    // --- MODIFIED: Updated status codes ---
    Color statusColor;
    IconData statusIcon;
    switch (status) {
      case 'e3': // Completed
        statusColor = Colors.green; 
        statusIcon = Icons.check_circle; 
        break;
      case 'Cancelled':
      case 'Rejected': 
        statusColor = Colors.red; 
        statusIcon = Icons.cancel; 
        break;
      case 'a1': // Accepted
        statusColor = Colors.blue; 
        statusIcon = Icons.thumb_up; 
        break;
      case 'w2': // In Progress
        statusColor = Colors.cyan; 
        statusIcon = Icons.construction; 
        break;
      case 'w1': // Start OTP Sent
      case 'e1': // End OTP Sent
      case 'e2': // End OTP Sent
        statusColor = Colors.deepPurple; 
        statusIcon = Icons.password; 
        break;
      case 'b1': // Created
      case 'b2': // Dispatched
      default: 
        statusColor = Colors.orange; 
        statusIcon = Icons.pending;
    }
    // --- END MODIFICATION ---

    return InkWell(
      onTap: () {
        if (_currentBookingId != null) {
            Navigator.of(context).push(
                MaterialPageRoute(
                    builder: (_) => BookingDetailsScreen(
                        bookingId: _currentBookingId!,
                        // --- MODIFICATION: Pass correct user ID ---
                        userId: FirebaseAuth.instance.currentUser!.uid,
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
                              // --- MODIFICATION: Use new hour fields ---
                              Text(
                                '${(widget.bookingData['endHour'] ?? 0) - (widget.bookingData['startHour'] ?? 0)} hours',
                                style: TextStyle(color: Colors.grey[600]),
                              ),
                              // --- END MODIFICATION ---
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
                  // --- MODIFIED: Updated status codes ---
                  if (!currentUserIsWorker && (status == 'b2' || status == 'a1') && !_isCancelling)
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
                    
                  // --- REMOVED: Worker "Complete" button ---
                    
                  // Loading Indicator
                  if (_isCancelling) // --- MODIFIED: Removed _isCompleting ---
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