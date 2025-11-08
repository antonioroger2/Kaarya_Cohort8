// lib/features/worker/job_request_card.dart
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import '../../features/worker/user_details_screen.dart';

class JobRequestCard extends StatefulWidget {
  final Map<String, dynamic> bookingData;
  final String bookingId;
  final String workerId;
  
  const JobRequestCard({
    super.key, 
    required this.bookingData, 
    required this.bookingId, 
    required this.workerId
  });

  @override
  State<JobRequestCard> createState() => _JobRequestCardState();
}

class _JobRequestCardState extends State<JobRequestCard> {
  bool _isLoading = false;

  Future<void> _updateJobStatus(String status) async {
    setState(() => _isLoading = true);
    
    final batch = FirebaseFirestore.instance.batch();
    final bookingRef = FirebaseFirestore.instance.collection('bookings').doc(widget.bookingId);
    final workerRef = FirebaseFirestore.instance.collection('workers').doc(widget.workerId);

    try {
      batch.update(bookingRef, {
        'status': status,
        'remarks': FieldValue.arrayUnion([
          { 'log': 'Worker $status the job.', 'timestamp': Timestamp.now() }
        ])
      });

      // Update worker availability based on status
      if (status == 'Accepted') {
        // Worker is now busy
        batch.update(workerRef, {'availability': 'N'});
        
        // Send acceptance notification to user
        await FirebaseFirestore.instance.collection('notifications').add({
            'recipientId': widget.bookingData['userId'],
            'senderId': widget.workerId,
            'type': 'booking_accepted',
            'title': 'Booking Accepted!',
            'message': '${widget.bookingData['workerInfo']?['name']} has accepted your booking for ${DateFormat('MMM d, h:mm a').format((widget.bookingData['bookingDate'] as Timestamp).toDate())}.',
            'bookingId': widget.bookingId,
            'isRead': false,
            'createdAt': Timestamp.now(),
        });
      } else if (status == 'Rejected') {
        // Worker remains available
        batch.update(workerRef, {'availability': 'Y'});
        
        // Send rejection notification to user
        await FirebaseFirestore.instance.collection('notifications').add({
            'recipientId': widget.bookingData['userId'],
            'senderId': widget.workerId,
            'type': 'booking_rejected',
            'title': 'Booking Rejected',
            'message': '${widget.bookingData['workerInfo']?['name']} has rejected your booking request for ${DateFormat('MMM d, h:mm a').format((widget.bookingData['bookingDate'] as Timestamp).toDate())}.',
            'bookingId': widget.bookingId,
            'isRead': false,
            'createdAt': Timestamp.now(),
        });
      }

      await batch.commit();

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Job has been $status.'),
          backgroundColor: status == 'Accepted' ? Colors.green : Colors.orange,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error: $e'),
          backgroundColor: Colors.redAccent,
        ),
      );
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final date = (widget.bookingData['bookingDate'] as Timestamp).toDate();
    final wage = (widget.bookingData['wage'] ?? 0).toInt();
    final userId = widget.bookingData['userId'] ?? '';
    final userName = widget.bookingData['userInfo']?['name'] ?? 'A user';
    final userPhone = widget.bookingData['userInfo']?['phone'] ?? '';
    final timeSlot = widget.bookingData['timeSlot'] ?? 1;

    return InkWell(
      onTap: () {
        // Navigate to show client details
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => UserDetailsScreen(
              userId: userId,
              userName: userName,
              userPhone: userPhone,
            ),
          ),
        );
      },
      child: Card(
        margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        child: Column(
          children: [
            // Header: New Job Request Banner
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [Colors.blue.shade100!, Colors.blue.shade50!],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
              ),
              child: Row(
                children: [
                  const Icon(Icons.notifications_active, color: Colors.blue),
                  const SizedBox(width: 8),
                  const Text(
                    'New Job Request',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      color: Colors.blue,
                    ),
                  ),
                  const Spacer(),
                  Text(
                    DateFormat('EEE, MMM d').format(date),
                    style: const TextStyle(fontWeight: FontWeight.w500),
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
                  // Client Info
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
                            if (userPhone.isNotEmpty)
                              Text(
                                userPhone,
                                style: TextStyle(
                                  color: Colors.grey[600],
                                  fontSize: 14,
                                ),
                              ),
                          ],
                        ),
                      ),
                      Icon(Icons.chevron_right, color: Colors.grey[400]),
                    ],
                  ),
                  const SizedBox(height: 20),
                  
                  // Job Time/Wage Info
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.grey[50],
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.grey[200]!),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceAround,
                      children: [
                        Column(
                          children: [
                            const Icon(Icons.schedule, color: Colors.indigo),
                            const SizedBox(height: 4),
                            Text(
                              DateFormat.jm().format(date),
                              style: const TextStyle(fontWeight: FontWeight.w500),
                            ),
                            Text(
                              'Start Time',
                              style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                            ),
                          ],
                        ),
                        Container(height: 40, width: 1, color: Colors.grey[300]),
                        Column(
                          children: [
                            const Icon(Icons.timer, color: Colors.indigo),
                            const SizedBox(height: 4),
                            Text(
                              '$timeSlot',
                              style: const TextStyle(fontWeight: FontWeight.w500),
                            ),
                            Text(
                              'Hours',
                              style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                            ),
                          ],
                        ),
                        Container(height: 40, width: 1, color: Colors.grey[300]),
                        Column(
                          children: [
                            const Icon(Icons.currency_rupee, color: Colors.green),
                            const SizedBox(height: 4),
                            Text(
                              '₹$wage',
                              style: const TextStyle(
                                fontWeight: FontWeight.w500,
                                color: Colors.green,
                              ),
                            ),
                            Text(
                              'Earning',
                              style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 20),

                  // Action Buttons
                  if (_isLoading)
                    const Center(
                      child: Padding(
                        padding: EdgeInsets.all(8.0),
                        child: CircularProgressIndicator(),
                      ),
                    )
                  else
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: () => _updateJobStatus('Rejected'),
                            style: OutlinedButton.styleFrom(
                              foregroundColor: Colors.red,
                              padding: const EdgeInsets.symmetric(vertical: 12),
                            ),
                            icon: const Icon(Icons.close),
                            label: const Text('Decline'),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: ElevatedButton.icon(
                            onPressed: () => _updateJobStatus('Accepted'),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.green,
                              padding: const EdgeInsets.symmetric(vertical: 12),
                            ),
                            icon: const Icon(Icons.check),
                            label: const Text('Accept'),
                          ),
                        ),
                      ],
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
