// lib/features/worker/user_details_screen.dart
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import '../../core/theme.dart';

class UserDetailsScreen extends StatelessWidget {
  final String userId;
  final String userName;
  final String userPhone;

  const UserDetailsScreen({
    super.key,
    required this.userId,
    required this.userName,
    required this.userPhone,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('$userName\'s Profile'),
        backgroundColor: Colors.teal,
        foregroundColor: Colors.white,
      ),
      body: DoodleBackground(
        child: StreamBuilder<DocumentSnapshot>(
          stream: FirebaseFirestore.instance.collection('users').doc(userId).snapshots(),
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Center(child: CircularProgressIndicator());
            }
            if (!snapshot.hasData || !snapshot.data!.exists) {
              return const Center(
                child: Text('User information not available'),
              );
            }

            final userData = snapshot.data!.data() as Map<String, dynamic>;
            final name = userData['name'] ?? 'N/A';
            final phone = userData['phone'] ?? 'N/A';
            final altPhone = userData['altPhone'] ?? '';
            final pin = userData['pin'] ?? 'N/A';
            final email = userData['email'] ?? '';
            final locality = userData['locality'] ?? '';
            final trustScore = (userData['trustScore'] ?? 0.0).toDouble();
            final userType = userData['userType'] ?? 'Standard';
            final createdAt = userData['createdAt'] as Timestamp?;
            final memberSince = createdAt != null ? DateFormat('MMM yyyy').format(createdAt.toDate()) : 'N/A';

            return SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Profile Header
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Row(
                        children: [
                          CircleAvatar(
                            radius: 40,
                            backgroundColor: Colors.teal.withOpacity(0.1),
                            child: Text(
                              name.isNotEmpty ? name[0].toUpperCase() : 'U',
                              style: const TextStyle(
                                fontSize: 24,
                                fontWeight: FontWeight.bold,
                                color: Colors.teal,
                              ),
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
                                    fontSize: 20,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Row(
                                  children: [
                                    const Icon(Icons.verified_user, color: Colors.green, size: 16),
                                    const SizedBox(width: 4),
                                    Text(
                                      'Trust Score: ${trustScore.toStringAsFixed(1)}',
                                      style: const TextStyle(
                                        color: Colors.green,
                                        fontWeight: FontWeight.w500,
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 4),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                  decoration: BoxDecoration(
                                    color: Colors.teal.withOpacity(0.1),
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  child: Text(
                                    userType,
                                    style: const TextStyle(
                                      color: Colors.teal,
                                      fontSize: 12,
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),

                  // Contact Information
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Contact Information',
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                              color: Colors.teal,
                            ),
                          ),
                          const SizedBox(height: 12),
                          _buildInfoRow(Icons.phone, 'Primary Phone', phone),
                          if (altPhone.isNotEmpty) ...[
                            const SizedBox(height: 8),
                            _buildInfoRow(Icons.phone_android, 'Alternate Phone', altPhone),
                          ],
                          if (email.isNotEmpty) ...[
                            const SizedBox(height: 8),
                            _buildInfoRow(Icons.email, 'Email', email),
                          ],
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),

                  // Location Information
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Location',
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                              color: Colors.teal,
                            ),
                          ),
                          const SizedBox(height: 12),
                          _buildInfoRow(Icons.location_on, 'Pincode', pin),
                          if (locality.isNotEmpty) ...[
                            const SizedBox(height: 8),
                            _buildInfoRow(Icons.place, 'Locality', locality),
                          ],
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),

                  // Account Information and Trust Score
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Account Information',
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                              color: Colors.teal,
                            ),
                          ),
                          const SizedBox(height: 12),
                          _buildInfoRow(Icons.calendar_today, 'Member Since', memberSince),
                          const SizedBox(height: 8),
                          _buildInfoRow(Icons.account_circle, 'User Type', userType),
                          const Divider(height: 32),
                          const Text(
                            'Trust Score',
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                              color: Colors.teal,
                            ),
                          ),
                          const SizedBox(height: 12),
                          LinearProgressIndicator(
                            value: trustScore / 10,
                            backgroundColor: Colors.grey[300],
                            valueColor: AlwaysStoppedAnimation<Color>(
                              trustScore >= 7 ? Colors.green : trustScore >= 5 ? Colors.orange : Colors.red,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            _getTrustScoreDescription(trustScore),
                            style: TextStyle(
                              color: Colors.grey[600],
                              fontSize: 14,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _buildInfoRow(IconData icon, String label, String value) {
    return Row(
      children: [
        Icon(icon, color: Colors.teal, size: 20),
        const SizedBox(width: 12),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label,
              style: TextStyle(
                color: Colors.grey[600],
                fontSize: 12,
              ),
            ),
            Text(
              value,
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ],
    );
  }

  String _getTrustScoreDescription(double score) {
    if (score >= 9) return 'Excellent reputation - Highly reliable user';
    if (score >= 7) return 'Good reputation - Reliable user with positive history';
    if (score >= 5) return 'Average reputation - Standard user';
    if (score >= 3) return 'Below average - May need extra caution';
    return 'Low reputation - Exercise caution with this user';
  }
}
