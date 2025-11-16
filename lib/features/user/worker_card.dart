// lib/features/user/worker_card.dart
import 'package:flutter/material.dart';
import '../../features/user/booking_creation_screen.dart';

class WorkerCard extends StatelessWidget {
  final Map<String, dynamic> worker;
  final String workerId;
  final String userId;

  const WorkerCard({
    super.key, 
    required this.worker, 
    required this.workerId, 
    required this.userId
  });

  @override
  Widget build(BuildContext context) {
    final rating = (worker['avgRating'] ?? 0.0).toDouble();
    final hourlyRate = (worker['perHourCharge'] ?? 0).toInt();
    final name = worker['name'] ?? 'N/A';
    final phone = worker['phone'] ?? ''; 
    final categories = worker['workCategories'] as List? ?? [];
    final experience = worker['experience'] ?? 0;
    final completedJobs = worker['completedBookings'] ?? 0;

    final List<Map<String, dynamic>> workCategories = categories
        .map((category) => Map<String, dynamic>.from(category as Map))
        .toList();

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [

          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [Colors.teal, Colors.teal[700]!],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
            ),
            child: Row(
              children: [

                CircleAvatar(
                  radius: 30,
                  backgroundColor: Colors.white,
                  child: Text(
                    name.isNotEmpty ? name[0].toUpperCase() : 'W',
                    style: const TextStyle(color: Colors.teal, fontSize: 24, fontWeight: FontWeight.bold),
                  ),
                ),
                const SizedBox(width: 16),

                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        name,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          const Icon(Icons.star, size: 16, color: Colors.amber),
                          const SizedBox(width: 4),
                          Text(
                            '${rating.toStringAsFixed(1)} ($completedJobs jobs)',
                            style: const TextStyle(color: Colors.white70),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),

                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    '₹$hourlyRate/hr',
                    style: const TextStyle(
                      color: Colors.teal,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ),
          ),

          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [

                if (categories.isNotEmpty) ...[
                  const Text(
                    'Skills',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,

                    children: workCategories.take(3).map((c) {
                      return Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                        decoration: BoxDecoration(
                          color: Colors.grey[100],
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(color: Colors.grey[300]!),
                        ),
                        child: Text(c['mainCategory'] ?? 'Skill'),
                      );
                    }).toList(),
                  ),
                ],
                const SizedBox(height: 16),

                Row(
                  children: [
                    Expanded(
                      child: Column(
                        children: [
                          Text(
                            '$experience+',
                            style: const TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                              color: Colors.teal,
                            ),
                          ),
                          const Text('Years Exp.'),
                        ],
                      ),
                    ),
                    Container(
                      width: 1,
                      height: 40,
                      color: Colors.grey[300],
                    ),
                    Expanded(
                      child: Column(
                        children: [
                          Text(
                            '$completedJobs',
                            style: const TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                              color: Colors.teal,
                            ),
                          ),
                          const Text('Jobs Done'),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),

                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: () {
                      Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => BookingCreationScreen(
                            userId: userId,
                            workerId: workerId,
                            workerName: name,
                            workerPhone: phone,

                            workCategories: workCategories,
                          ),
                        ),
                      );
                    },
                    icon: const Icon(Icons.calendar_today),
                    label: const Text('Book Now'),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}