import 'package:flutter/material.dart';
import 'package:intl/intl.dart'; 
import '../../features/user/booking_creation_screen.dart';
import '../auth/auth_screen.dart'; import 'worker_profile_view_screen.dart';

class WorkerCard extends StatelessWidget {
  final Map<String, dynamic> worker;
  final String workerId;
  final String userId;
  final String userPin; 

  const WorkerCard({
    super.key,
    required this.worker,
    required this.workerId,
    required this.userId,
    required this.userPin,
  });

  static const Color _primaryAccent = Color(0xFF00695C); 
  static const Color _primaryAccentLight = Color(0xFFF3F4F6);
  static const Color _localAccent = Color.fromARGB(255, 254, 119, 78);

  String _getPrimarySkill(Map<String, dynamic> cwData) {
    if (cwData.isEmpty) return 'Generalist';
    final primarySkill = cwData.keys.first;
    final count = cwData.length;
    if (count > 1) return "$primarySkill (+${count - 1})";
    return primarySkill;
  }

  String _getHourlyRate(Map<String, dynamic> cwData) {
    double sum = 0;
    int count = 0;
    cwData.forEach((key, value) {
      if (value is Map<String, dynamic> && value.containsKey('perHourCharge')) {
        sum += (value['perHourCharge'] as num?)?.toDouble() ?? 0;
        count++;
      }
    });

    if (count > 0) {
      final rate = sum / count;
      final formatter = NumberFormat.currency(locale: 'en_IN', symbol: '₹', decimalDigits: 0);
      return "${formatter.format(rate)}/hr";
    }

    final fallback = (worker['perHourCharge'] as num?)?.toInt() ?? 0;
    return fallback > 0 ? "₹$fallback/hr" : "Rate Varies";
  }

  double _getAverageRating() {
    return (worker['avgRating'] as num? ?? 0).toDouble();
  }

  String _normalizePin(String pin) {
    if (pin.isEmpty) return '';
    return pin.trim().replaceAll(RegExp(r"\s+"), "");
  }

  Widget _buildAvatar(String name, String? imageUrl) {
    const radius = 28.0;
    
    final parts = name.trim().split(" ");
    String initials = "W";
    if (parts.isNotEmpty && parts.first.isNotEmpty) {
      initials = parts.first[0].toUpperCase();
      if (parts.length > 1 && parts[1].isNotEmpty) initials += parts[1][0].toUpperCase();
    }

    final initialsWidget = CircleAvatar(
      radius: radius,
      backgroundColor: _primaryAccentLight,
      child: Text(
        initials,
        style: TextStyle(
          fontSize: radius * 0.6,
          fontWeight: FontWeight.bold,
          color: _primaryAccent,
        ),
      ),
    );

    if (imageUrl != null && imageUrl.isNotEmpty) {
      return CircleAvatar(
        radius: radius,
        backgroundImage: NetworkImage(imageUrl),
        backgroundColor: Colors.grey.shade200,
        onBackgroundImageError: (exception, stackTrace) {
          return;
        },
        child: initialsWidget,
      );
    }
    return initialsWidget;
  }

    void _handleBookNow(BuildContext context) {
                    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => BookingCreationScreen(
          userId: userId,           preSelectedWorker: worker, 
        ),
      ),
    );
  }

  void _navigateToWorkerProfile(BuildContext context) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => WorkerProfileViewScreen(
          worker: worker,
          userId: userId,
          workerId: workerId,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final rating = _getAverageRating();
    final name = worker['name'] ?? "Worker";
    final cwData = worker['cw_data'] as Map<String, dynamic>? ?? {};
    final primarySkill = _getPrimarySkill(cwData);
    final hourlyRate = _getHourlyRate(cwData);
    final completedJobs = (worker['completedBookings'] as num?)?.toInt() ?? 0;
    final isVerified = worker['isVerified'] ?? false;
    final locality = worker['locality'] ?? "";
    final tools = (worker['tools'] as List?) ?? [];

    final workerPin = _normalizePin(worker['pincode'] ?? "");
    final userPinNorm = _normalizePin(userPin);
    final isLocal = userPinNorm.isNotEmpty && userPinNorm == workerPin;

    return Card(
      elevation: 0,
      margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      color: Colors.white, 
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: Colors.grey.shade100, width: 1.5),
      ),
      child: InkWell(
        onTap: () => _navigateToWorkerProfile(context),
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
                                                        Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Stack(
                    children: [
                      _buildAvatar(name, worker['profilePicUrl']),
                      if (isVerified)
                        Positioned(
                          bottom: 0,
                          right: 0,
                          child: Container(
                            padding: EdgeInsets.zero,
                            decoration: BoxDecoration(
                              color: Colors.blue.shade600, 
                              shape: BoxShape.circle,
                              border: Border.all(color: Colors.white, width: 2),
                            ),
                            child: const Icon(Icons.check_circle, size: 14, color: Colors.white),
                          ),
                        ),
                    ],
                  ),

                  const SizedBox(width: 14),

                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                                                Text(name,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w700,
                                color: Colors.black87)),

                        const SizedBox(height: 4),

                                                Container(
                          padding:
                              const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(
                            color: _primaryAccentLight,
                            borderRadius: BorderRadius.circular(6),
                            border: Border.all(color: Colors.grey.shade200),
                          ),
                          child: Text(primarySkill,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                                color: _primaryAccent,
                              )),
                        ),
                      ],
                    ),
                  ),

                                    Column(
                    children: [
                      Text(hourlyRate,
                          style: TextStyle(
                              color: _primaryAccent,
                              fontWeight: FontWeight.w800,
                              fontSize: 15)),
                      const SizedBox(height: 6),
                      ElevatedButton(
                        onPressed: () => _handleBookNow(context),                         style: ElevatedButton.styleFrom(
                            backgroundColor: _primaryAccent,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(
                                horizontal: 14, vertical: 8),
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(8)),
                            elevation: 0),
                        child: const Text("Book",
                            style: TextStyle(
                                fontSize: 12, fontWeight: FontWeight.bold)),
                      )
                    ],
                  )
                ],
              ),

              const SizedBox(height: 10),

                                                        Row(
                children: [
                                    Icon(Icons.star_rounded, size: 14, color: Colors.amber.shade700),
                  const SizedBox(width: 3),
                  Text(rating.toStringAsFixed(1),
                      style: const TextStyle(
                          fontSize: 12, fontWeight: FontWeight.w600)),
                  const SizedBox(width: 12),

                  Text("$completedJobs jobs",
                      style: TextStyle(fontSize: 12, color: Colors.grey[700])),

                  if (isLocal) ...[
                    const SizedBox(width: 12),
                    Container(
                      padding:
                          const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                      decoration: BoxDecoration(
                        color: _localAccent.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Row(
                        children: [
                          Icon(Icons.location_on,
                              size: 10, color: _localAccent),
                          const SizedBox(width: 2),
                          Text("Local",
                              style: TextStyle(
                                  fontSize: 10,
                                  fontWeight: FontWeight.w700,
                                  color: _localAccent))
                        ],
                      ),
                    ),
                  ],
                  
                                    const SizedBox(width: 12),
                  Icon(Icons.location_on_outlined,
                      size: 14, color: Colors.grey.shade700),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(locality.isNotEmpty ? locality : "Unknown Locality",
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: 12, color: Colors.grey[800])),
                  ),
                ],
              ),

              const SizedBox(height: 6),

                                                        if (tools.isNotEmpty)
                Row(
                  children: [
                    Icon(Icons.construction_rounded,
                        size: 14, color: Colors.grey.shade700),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        tools.take(2).join(", ") +
                            (tools.length > 2
                                ? " (+${tools.length - 2})"
                                : ""),
                        style: TextStyle(fontSize: 12, color: Colors.grey[800]),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
            ],
          ),
        ),
      ),
    );
  }
}

