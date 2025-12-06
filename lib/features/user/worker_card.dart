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

  // Helper to extract top 3 categories from nested data
  List<String> _getTopCategories(Map<String, dynamic> cwData) {
    if (cwData.isEmpty) return ['Generalist'];
    return cwData.keys.toList().take(3).toList();
  }

  @override
  Widget build(BuildContext context) {
    final rating = (worker['avgRating'] as num?)?.toDouble() ?? 0.0;
    final hourlyRate = (worker['perHourCharge'] as num?)?.toInt() ?? 0;
    final name = worker['name'] ?? 'N/A';
    final completedJobs = (worker['completedBookings'] as num?)?.toInt() ?? 0;
    
    // NEW: Access nested data
    final cwData = worker['cw_data'] as Map<String, dynamic>? ?? {};
    final displayCategories = _getTopCategories(cwData);

    // Placeholder or legacy fields
    final experience = worker['experience'] ?? 0; 

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // --- HEADER: Name, Multi-Skills, Hourly Rate ---
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
                      Text(
                        displayCategories.join(' / '), // Display top categories
                        style: const TextStyle(color: Colors.white70, fontSize: 13),
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
                // Hourly Rate Container (Restored)
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
          // --- BODY: Expertise Chips, Stats, Button ---
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Display specific skills as chips (Restored new logic)
                if (cwData.isNotEmpty) ...[
                  const Text('Expertise', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: cwData.entries.expand((catEntry) {
                      final tasks = catEntry.value as Map<String, dynamic>;
                      return tasks.entries.map((taskEntry) {
                        return Chip(
                          label: Text(taskEntry.value['name'] ?? 'Task'),
                          backgroundColor: Colors.teal.shade50,
                          labelStyle: TextStyle(color: Colors.teal.shade800, fontSize: 12),
                        );
                      });
                    }).take(4).toList(), // Limit visible skills
                  ),
                  const SizedBox(height: 16),
                ],
                // Stats Row (Restored)
                Row(
                  children: [
                    Expanded(
                      child: Column(
                        children: [
                          Text(
                            '${experience}+',
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
                // Book Now Button (Restored)
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: () {
                      // Navigate to booking screen, passing the full worker map
                      Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => BookingCreationScreen(
                            // This assumes BookingCreationScreen is refactored
                            // to accept the full worker map.
                            userId: userId,
                            preSelectedWorker: worker, 
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