// lib/features/user/worker_card.dart
import 'package:flutter/material.dart';
import '../../features/user/booking_creation_screen.dart'; 
import '../auth/auth_screen.dart'; // Needed for potential auth redirection

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

  String _getTaskDisplayName(Map<String, dynamic> taskEntryValue) {
    return taskEntryValue['name'] ?? 'Task';
  }
  
  void _showBookingOptions(BuildContext context) {
    final bool isGuest = userId.isEmpty;
    final String workerName = worker['name'] ?? 'The Professional';

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) {
        return Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                "Book $workerName",
                style: Theme.of(context).textTheme.titleLarge!.copyWith(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 16),
              
              // OPTION 1: Direct Request to this Professional (Individual flow)
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.person_pin, color: Colors.teal),
                title: Text("Request $workerName Directly"),
                subtitle: const Text("Send a job request only to this specific professional."),
                onTap: () {
                  Navigator.pop(context); // Close sheet
                  if (isGuest) {
                    Navigator.of(context).push(MaterialPageRoute(builder: (_) => const AuthScreen()));
                  } else {
                    Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => BookingCreationScreen(
                          userId: userId,
                          preSelectedWorker: worker, 
                        ),
                      ),
                    );
                  }
                },
              ),
              const Divider(),

              // OPTION 2: General Request to Best Matches (Multi-Match flow)
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.search, color: Colors.blue),
                title: const Text("General Request (Multi-Match)"),
                subtitle: const Text("Use the search bar to describe your job and find the top 5 matches."),
                onTap: () {
                   Navigator.pop(context); // Close sheet
                   ScaffoldMessenger.of(context).showSnackBar(
                     const SnackBar(content: Text("Use the Search bar at the top of the Home Screen to find the best match."))
                   );
                },
              ),
              const SizedBox(height: 10),
            ],
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final rating = (worker['avgRating'] as num?)?.toDouble() ?? 0.0;
    final hourlyRate = (worker['perHourCharge'] as num?)?.toInt() ?? 0;
    final name = worker['name'] ?? 'N/A';
    final completedJobs = (worker['completedBookings'] as num?)?.toInt() ?? 0;
    
    final cwData = worker['cw_data'] as Map<String, dynamic>? ?? {};
    final displayCategories = _getTopCategories(cwData);
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
                // Hourly Rate Container 
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
                // Display specific skills as chips 
                if (cwData.isNotEmpty) ...[
                  const Text('Expertise', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: cwData.entries.expand((catEntry) {
                      final tasks = catEntry.value as Map<String, dynamic>;
                      return List<Map<String, dynamic>>.from(tasks.values).map((taskData) {
                        return Chip(
                          label: Text(_getTaskDisplayName(taskData)),
                          backgroundColor: Colors.teal.shade50,
                          labelStyle: TextStyle(color: Colors.teal.shade800, fontSize: 12),
                        );
                      });
                    }).take(4).toList(), // Limit visible skills
                  ),
                  const SizedBox(height: 16),
                ],
                // Stats Row 
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
                // Book Now Button 
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    // CRITICAL FIX: Changed action to show options
                    onPressed: () => _showBookingOptions(context),
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