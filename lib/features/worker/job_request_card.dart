// lib/features/worker/job_request_card.dart
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import '../../features/worker/user_details_screen.dart';
import '../../core/api_client.dart'; 

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

  Future<void> _handleJobAction(String action) async {
    setState(() => _isLoading = true);

    final endpoint = action == 'Accepted' ? '/worker-accept' : '/worker-reject';
    final payload = {
      'workerId': widget.workerId,
      'bookingId': widget.bookingId,
    };

    try {
      final response = await ApiClient.post(endpoint, payload);

      if (!mounted) return;

      if (response['ok'] == true) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Job has been $action.'),
            backgroundColor: action == 'Accepted' ? Colors.green : Colors.orange,
          ),
        );
      } else {
        throw Exception(response['error'] ?? 'Failed to $action job');
      }
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

    final date = (widget.bookingData['bookingDate'] as Timestamp? ?? widget.bookingData['createdAt'] as Timestamp).toDate();
    final wage = (widget.bookingData['wage'] ?? 0).toInt();
    final userId = widget.bookingData['userId'] ?? '';

    final location = widget.bookingData['location'] ?? {};
    final locality = location['locality'] ?? 'Unknown';

    final userName = widget.bookingData['userName'] ?? 'A user'; 
    final userPhone = widget.bookingData['userPhone'] ?? '';
    final timeSlot = (widget.bookingData['endHour'] ?? 0) - (widget.bookingData['startHour'] ?? 0);

    return InkWell(
      onTap: () {

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

            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [Colors.blue.shade100, Colors.blue.shade50],
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

            Padding(
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

                            onPressed: () => _handleJobAction('Rejected'),
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

                            onPressed: () => _handleJobAction('Accepted'),
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