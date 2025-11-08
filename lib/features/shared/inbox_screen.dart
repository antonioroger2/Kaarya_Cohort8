// lib/features/shared/inbox_screen.dart
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import '../../core/theme.dart';
import '../../features/shared/booking_details_screen.dart';
import '../../features/shared/rating_dialog.dart';

class InboxScreen extends StatefulWidget {
  final String userId;
  final bool isWorker;

  const InboxScreen({super.key, required this.userId, required this.isWorker});

  @override
  State<InboxScreen> createState() => _InboxScreenState();
}

class _InboxScreenState extends State<InboxScreen> {

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Inbox'),
      ),
      body: DoodleBackground(
        child: StreamBuilder<QuerySnapshot>(
          stream: FirebaseFirestore.instance
              .collection('notifications')
              .where('recipientId', isEqualTo: widget.userId)
              // Order by creation time in descending order (newest first)
              .orderBy('createdAt', descending: true)
              .snapshots(),
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Center(child: CircularProgressIndicator());
            }
            if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
              return const Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.inbox, size: 64, color: Colors.grey),
                    SizedBox(height: 16),
                    Text('No notifications yet', style: TextStyle(fontSize: 18, color: Colors.grey)),
                  ],
                ),
              );
            }

            final notifications = snapshot.data!.docs;

            return ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: notifications.length,
              itemBuilder: (context, index) {
                final notification = notifications[index];
                final data = notification.data() as Map<String, dynamic>;
                final isRead = data['isRead'] ?? false;
                final type = data['type'] ?? 'general';
                final title = data['title'] ?? 'Notification';
                final message = data['message'] ?? '';
                final createdAt = (data['createdAt'] as Timestamp?)?.toDate();
                final bookingId = data['bookingId'];

                IconData icon;
                Color color;

                switch (type) {
                  case 'booking_cancelled':
                  case 'booking_rejected':
                    icon = Icons.cancel;
                    color = Colors.red;
                    break;
                  case 'booking_accepted':
                  case 'job_confirmed':
                    icon = Icons.check_circle;
                    color = Colors.green;
                    break;
                  case 'job_completed':
                    icon = Icons.done_all;
                    color = Colors.blue;
                    break;
                  case 'new_booking_request':
                    icon = Icons.work_history;
                    color = Colors.orange;
                    break;
                  default:
                    icon = Icons.notifications;
                    color = Colors.grey;
                }

                return Card(
                  margin: const EdgeInsets.only(bottom: 12),
                  elevation: isRead ? 1 : 3,
                  child: Container(
                    decoration: BoxDecoration(
                      border: Border(
                        left: BorderSide(
                          color: isRead ? Colors.grey : color,
                          width: 4,
                        ),
                      ),
                    ),
                    child: ListTile(
                      leading: CircleAvatar(
                        backgroundColor: color.withOpacity(0.1),
                        child: Icon(icon, color: color),
                      ),
                      title: Text(
                        title,
                        style: TextStyle(
                          fontWeight: isRead ? FontWeight.normal : FontWeight.bold,
                        ),
                      ),
                      subtitle: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(message),
                          const SizedBox(height: 4),
                          Text(
                            createdAt != null ? DateFormat('MMM d, h:mm a').format(createdAt) : '',
                            style: TextStyle(
                              fontSize: 12,
                              color: Colors.grey[600],
                            ),
                          ),
                        ],
                      ),
                      trailing: !isRead
                          ? Container(
                              width: 8,
                              height: 8,
                              decoration: const BoxDecoration(
                                color: Colors.blue,
                                shape: BoxShape.circle,
                              ),
                            )
                          : null,
                      onTap: () async {
                        // 1. Mark as read
                        if (!isRead) {
                          await FirebaseFirestore.instance
                              .collection('notifications')
                              .doc(notification.id)
                              .update({'isRead': true});
                        }

                        // 2. Handle job completion confirmation for clients (User)
                        if (type == 'job_completed' && !widget.isWorker) {
                          _showJobCompletionDialog(context, notification, data);
                          return;
                        }

                        // 3. Navigate to booking details for other booking-related notifications
                        if (bookingId != null) {
                          Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (_) => BookingDetailsScreen(
                                bookingId: bookingId,
                                userId: widget.userId,
                                isWorker: widget.isWorker,
                              ),
                            ),
                          );
                        }
                      },
                    ),
                  ),
                );
              },
            );
          },
        ),
      ),
    );
  }

  // --- Job Confirmation/Rating Logic (Client-side) ---

  void _showJobCompletionDialog(BuildContext context, DocumentSnapshot notification, Map<String, dynamic> data) async {
    final bookingId = data['bookingId'];
    if (bookingId == null) return;

    // Get booking details
    final bookingDoc = await FirebaseFirestore.instance.collection('bookings').doc(bookingId).get();
    if (!bookingDoc.exists) return;
    
    final bookingData = bookingDoc.data() as Map<String, dynamic>;
    final workerName = bookingData['workerInfo']?['name'] ?? 'Worker';
    final wage = (bookingData['wage'] ?? 0).toInt();

    if (!mounted) return;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Job Completion Confirmation'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('Did $workerName complete the job satisfactorily?'),
            const SizedBox(height: 8),
            Text(
              'Amount: ₹$wage',
              style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.green),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Not Yet'),
          ),
          ElevatedButton(
            onPressed: () async {
              Navigator.of(dialogContext).pop();
              await _confirmJobCompletion(bookingId, bookingDoc, data['senderId']);
            },
            child: const Text('Yes, Completed'),
          ),
        ],
      ),
    );
  }

  Future<void> _confirmJobCompletion(String bookingId, DocumentSnapshot bookingDoc, String workerId) async {
    try {
      final bookingData = bookingDoc.data() as Map<String, dynamic>;
      final workerName = bookingData['workerInfo']?['name'] ?? 'Worker';

      // 1. Show rating dialog
      if (!mounted) return;
      final rating = await showDialog<double>(
        context: context,
        barrierDismissible: false,
        builder: (dialogContext) => RatingDialog(workerName: workerName),
      );

      if (rating == null) return; // User cancelled rating

      // 2. Update booking with rating
      await FirebaseFirestore.instance.collection('bookings').doc(bookingId).update({
        'rating': rating,
        'review': 'Rated $rating stars',
        'status': 'Completed', // Finalized completion status by user
      });

      // 3. Update worker's rating and stats
      final workerDoc = await FirebaseFirestore.instance.collection('workers').doc(workerId).get();
      if (workerDoc.exists) {
        final workerData = workerDoc.data() as Map<String, dynamic>;
        final currentRating = (workerData['avgRating'] ?? 0.0).toDouble();
        final completedBookings = (workerData['completedBookings'] ?? 0); // Already incremented by worker
        final fourPlusRatings = (workerData['fourPlusRatings'] ?? 0) + (rating >= 4 ? 1 : 0);

        // Calculate new average rating - be careful to only average once per job.
        // Assuming 'completedBookings' is the count *before* the current job is considered "rated".
        // A better approach would be to track ratings in a subcollection, but modifying based on current structure.
        final totalRatedJobs = completedBookings; // Assuming the job status update happens only once.
        final newAvgRating = ((currentRating * totalRatedJobs) + rating) / (totalRatedJobs + 1);

        await FirebaseFirestore.instance.collection('workers').doc(workerId).set({
          'avgRating': newAvgRating,
          'fourPlusRatings': fourPlusRatings,
        }, SetOptions(merge: true));
      }

      // 4. Send confirmation notification to worker
      await FirebaseFirestore.instance.collection('notifications').add({
        'recipientId': workerId,
        'senderId': widget.userId,
        'type': 'job_confirmed',
        'title': 'Job Confirmed & Rated',
        'message': 'Your job has been confirmed as completed. You received $rating star${rating != 1.0 ? 's' : ''} rating.',
        'bookingId': bookingId,
        'isRead': false,
        'createdAt': Timestamp.now(),
      });

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Job confirmed and $workerName rated successfully!')),
      );

    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error confirming job: $e'), backgroundColor: Colors.red),
      );
    }
  }
}
