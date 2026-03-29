// lib/features/shared/inbox_screen.dart
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import '../../core/theme.dart';
import '../../features/shared/booking_details_screen.dart';

class InboxScreen extends StatefulWidget {
  final String userId;
  final bool isWorker;

  const InboxScreen({super.key, required this.userId, required this.isWorker});

  @override
  State<InboxScreen> createState() => _InboxScreenState();
}

class _InboxScreenState extends State<InboxScreen> {
  late Stream<QuerySnapshot> _notificationsStream;

  @override
  void initState() {
    super.initState();
    _notificationsStream = _buildNotificationsStream();
  }

  @override
  void didUpdateWidget(covariant InboxScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.userId != widget.userId) {
      _notificationsStream = _buildNotificationsStream();
    }
  }

  Stream<QuerySnapshot> _buildNotificationsStream() {
    return FirebaseFirestore.instance
        .collection('notifications')
        .where('recipientId', isEqualTo: widget.userId)
        .orderBy('createdAt', descending: true)
        .snapshots();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Inbox',
          style: TextStyle(
            fontWeight: FontWeight.w900,
            color: Colors.teal,
            fontSize: 18,
          ),
        ),
        foregroundColor: Colors.white,
      ),
      body: DoodleBackground(
        child: StreamBuilder<QuerySnapshot>(
          stream: _notificationsStream,
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

                // Map server notification types to Icons
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
                        // Mark as read
                        if (!isRead) {
                          await FirebaseFirestore.instance
                              .collection('notifications')
                              .doc(notification.id)
                              .update({'isRead': true});
                        }

                        // Navigate to booking details if ID is present
                        if (bookingId != null) {
                          // ignore: use_build_context_synchronously
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
}