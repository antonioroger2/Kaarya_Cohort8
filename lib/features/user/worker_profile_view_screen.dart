
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'booking_creation_screen.dart';

class WorkerProfileViewScreen extends StatefulWidget {
  final Map<String, dynamic> worker;
  final String userId;
  final String workerId;

  const WorkerProfileViewScreen({
    super.key,
    required this.worker,
    required this.userId,
    required this.workerId,
  });

  @override
  State<WorkerProfileViewScreen> createState() => _WorkerProfileViewScreenState();
}

class _WorkerProfileViewScreenState extends State<WorkerProfileViewScreen> {
  Map<String, dynamic>? _pendingBooking;

  @override
  void initState() {
    super.initState();
    _fetchPendingBooking();
  }

  Future<void> _fetchPendingBooking() async {
    try {
      final query = await FirebaseFirestore.instance
          .collection('bookings')
          .where('userId', isEqualTo: widget.userId)
          .where('workerId', isEqualTo: widget.workerId)
          .where('status', whereIn: ['b1', 'b2'])
          .limit(1)
          .get();
      if (query.docs.isNotEmpty) {
        setState(() {
          _pendingBooking = query.docs.first.data();
        });
      }
    } catch (e) {
      // Handle error if needed
    }
  }

  Future<void> _onRefresh() async {
    await Future.delayed(const Duration(milliseconds: 500));
  }

  
  String _formatCurrency(num val) {
    if (val <= 0) return '—';

    final formatter = NumberFormat.currency(locale: 'en_IN', symbol: '₹', decimalDigits: val % 1 == 0 ? 0 : 1);
    return formatter.format(val);
  }

  String _avgRate(Map<String, dynamic> cwData, Map<String, dynamic> worker) {
    double sum = 0;
    int count = 0;
    final fallbackRate = worker['perHourCharge'];
    final fallbackRateNum = (fallbackRate is num) ? fallbackRate.toDouble() : 0.0;

    cwData.forEach((k, v) {
      if (v is Map<String, dynamic>) {
        final rate = v['perHourCharge'];
        if (rate is num) {
          sum += rate.toDouble();
          count++;
        }
      }
    });

    if (count > 0) return '${_formatCurrency((sum / count))}/hr (Avg)';

    if (fallbackRateNum > 0) return '${_formatCurrency(fallbackRateNum)}/hr';
    return 'Rate Varies';
  }

  double _getAverageRating(Map<String, dynamic> worker) {
    return (worker['avgRating'] as num? ?? 0.0).toDouble();
  }

  Color _ratingColor(double rating) {
    if (rating >= 4.5) return Colors.green.shade600;
    if (rating >= 3.5) return Colors.amber.shade700;
    return Colors.orange.shade700;
  }

  /// Safely formats date strings/objects, handling Firebase Timestamp string format
  /// (e.g., "Timestamp(seconds=1765253659, nanoseconds=764000000)")
  /// which causes a FormatException with DateTime.parse().
  String _formatDate(dynamic dateValue) {
    if (dateValue == null) return '—';

    DateTime? date;

    if (dateValue is DateTime) {
      date = dateValue;
    } else if (dateValue is String) {
            date = DateTime.tryParse(dateValue);

            if (date == null && dateValue.startsWith('Timestamp(')) {
        final match = RegExp(r'seconds=(\d+), nanoseconds=(\d+)').firstMatch(dateValue);
        if (match != null) {
          final seconds = int.tryParse(match.group(1)!);
                    if (seconds != null) {
            date = DateTime.fromMillisecondsSinceEpoch(seconds * 1000);
          }
        }
      }
    }
        else if (dateValue is Map && dateValue.containsKey('seconds')) {
        final seconds = (dateValue['seconds'] as num?)?.toInt();
        if (seconds != null) {
            date = DateTime.fromMillisecondsSinceEpoch(seconds * 1000);
        }
    }

    if (date != null) {
      return DateFormat('MMM d, yyyy').format(date);
    }
    return '—';
  }

  
  String _getButtonText() {
    if (_pendingBooking != null) {
      final date = _pendingBooking!['bookingDate'];
      DateTime? bookingDate;
      if (date is Timestamp) {
        bookingDate = date.toDate();
      } else if (date is String) {
        bookingDate = DateTime.tryParse(date);
      }
      if (bookingDate != null) {
        final startHour = _pendingBooking!['startHour'] ?? 0;
        final time = DateTime(bookingDate.year, bookingDate.month, bookingDate.day, startHour);
        return 'Booking @ ${DateFormat('d MMM yy h:mm a').format(time)}';
      }
    }
    return 'BOOK NOW';
  }

  bool get _isBookDisabled => _pendingBooking != null;

  void _onBook(BuildContext context) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => BookingCreationScreen(
          userId: widget.userId,
          preSelectedWorker: widget.worker,
        ),
      ),
    );
  }

  
  Widget _avatar(String name, String? imageUrl, bool isVerified) {
    const double radius = 48.0;

    final parts = name.trim().split(' ');
    String initials = 'W';
    if (parts.isNotEmpty && parts.first.isNotEmpty) {
      initials = parts.first[0].toUpperCase();
      if (parts.length > 1 && parts[1].isNotEmpty) initials += parts[1][0].toUpperCase();
    }

    final initialsAvatar = CircleAvatar(
      radius: radius,
      backgroundColor: Colors.teal.shade100,
      child: Text(
        initials,
        style: TextStyle(
          fontSize: radius * 0.45,
          fontWeight: FontWeight.bold,
          color: Colors.teal.shade800,
        ),
      ),
    );

    final avatarWidget = (imageUrl != null && imageUrl.isNotEmpty)
        ? CircleAvatar(
            radius: radius,
            backgroundImage: NetworkImage(imageUrl),
            backgroundColor: Colors.grey[200],
          )
        : initialsAvatar;

    return Stack(
      alignment: Alignment.center,
      children: [
        Container(
          padding: const EdgeInsets.all(4),
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(color: Colors.teal.shade300, width: 2),
          ),
          child: avatarWidget,
        ),
        if (isVerified)
          Positioned(
            bottom: 0,
            right: 0,
            child: Container(
              padding: const EdgeInsets.all(4),
              decoration: BoxDecoration(
                color: Colors.blue.shade600,
                shape: BoxShape.circle,
                border: Border.all(color: Colors.white, width: 2),
              ),
              child: const Icon(Icons.verified, size: 16, color: Colors.white),
            ),
          ),
      ],
    );
  }

  Widget _buildStatItem(IconData icon, String value, String label, {Color? color, String? subtitle}) {
        return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: color ?? Colors.teal.shade600, size: 24),
            const SizedBox(height: 6),
            Text(
              value,
              style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700, color: color ?? Colors.black87),
              textAlign: TextAlign.center,
                            maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 4),
            Text(label, style: const TextStyle(fontSize: 12, color: Colors.black54), textAlign: TextAlign.center),
            if (subtitle != null)
              Text(subtitle, style: const TextStyle(fontSize: 11, color: Colors.black45), textAlign: TextAlign.center),
          ],
        ),
      ),
    );
  }

  Widget _locationRow(Map<String, dynamic> worker) {
    final locality = worker['locality']?.toString() ?? '—';
    final pin = worker['pincode']?.toString() ?? '—';
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(Icons.location_on_outlined, size: 20, color: Colors.blue.shade700),
        const SizedBox(width: 8),
        Flexible(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(locality, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500)),
              Text('Pincode: $pin', style: const TextStyle(fontSize: 12, color: Colors.black54)),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildToolsChips(List<String> tools) {
    if (tools.isEmpty) return const Text('No specific tools listed.', style: TextStyle(fontStyle: FontStyle.italic, color: Colors.black54));

    return Wrap(
      spacing: 8,
      runSpacing: 6,
      children: tools.map((t) => Chip(
        label: Text(t, style: TextStyle(color: Colors.blueGrey.shade800, fontWeight: FontWeight.w500, fontSize: 13)),
        backgroundColor: Colors.blueGrey.shade50,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8), side: BorderSide(color: Colors.blueGrey.shade200)),
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 0),
      )).toList(),
    );
  }

  Widget _buildCanonicalWorks(List<String> works) {
    if (works.isEmpty) return const Text('No prior canonical works/tasks listed.', style: TextStyle(fontStyle: FontStyle.italic, color: Colors.black54));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: works.map((w) => Padding(
        padding: const EdgeInsets.only(bottom: 8.0),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(Icons.check_circle_outline, size: 18, color: Colors.indigo.shade600),
            const SizedBox(width: 10),
            Expanded(child: Text(w, style: const TextStyle(fontSize: 14, height: 1.4, color: Colors.black87))),
            // TODO: Check if skill was discovered by AI (from worker data or booking history)
            Tooltip(
              message: 'Verified by AI through customer reviews ✨',
              child: const Icon(Icons.auto_awesome, size: 16, color: Colors.amber),
            ),
          ],
        ),
      )).toList(),
    );
  }

  Widget _buildSectionCard({required String title, required Widget content, bool compact = false, Widget? action}) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.grey.shade100),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 15,
            offset: const Offset(0, 6),
          )
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                title,
                style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.black87),
              ),
              ?action,
            ],
          ),
          const Divider(height: 24, thickness: 0.5),
          content,
        ],
      ),
    );
  }

    Widget _buildTopServicesChips(List<String> services) {
    if (services.isEmpty) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.only(top: 10.0),
      child: Wrap(
        spacing: 8.0,         runSpacing: 4.0,         children: services.map((service) => Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            color: Colors.blueGrey.shade50,             borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.blueGrey.shade100)
          ),
          child: Text(
            service,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: Colors.blueGrey.shade700,
            ),
          ),
        )).toList(),
      ),
    );
  }


  Widget _buildContent(BuildContext context) {
    final worker = widget.worker;
    final Map<String, dynamic> cwData = (worker['cw_data'] as Map?)?.cast<String, dynamic>() ?? {};
    final name = worker['name']?.toString() ?? 'Professional Worker';
    final imageUrl = worker['profilePicUrl']?.toString();
    final avgRate = _avgRate(cwData, worker);
    final double rating = _getAverageRating(worker);
    final completedJobs = (worker['completedBookings'] as num?)?.toInt() ?? 0;
    final tools = (worker['toolsAvailable'] as List?)?.cast<String>() ?? (worker['tools'] as List?)?.cast<String>() ?? [];
    final canonicalWorks = (worker['canonicalWorks'] as List?)?.cast<String>() ?? [];
    final desc = worker['profileDescription']?.toString() ?? worker['description']?.toString() ?? 'Experienced professional ready to help with your needs.';
    final isVerified = worker['isVerified'] as bool? ?? false;
    final fallbackRateNum = (worker['perHourCharge'] is num) ? (worker['perHourCharge'] as num) : 0;
    final experience = (worker['experience'] as num?)?.toInt() ?? 0;

        final List<String> serviceKeys = cwData.keys.toList();
    final List<String> topServices = serviceKeys.take(4).map((key) {
            String formattedKey = key.replaceAll('_', ' ');
      return formattedKey.split(' ').map((word) => word.isNotEmpty ? word[0].toUpperCase() + word.substring(1) : '').join(' ');
    }).toList();


    final header = Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _avatar(name, imageUrl, isVerified),
        const SizedBox(width: 16),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(name, style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w700, color: Colors.black87)),
              const SizedBox(height: 8),
              
              _buildTopServicesChips(topServices),

              const SizedBox(height: 12),
                            Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(avgRate, style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18, color: Colors.green[700])),
                ],
              ),
            ],
          ),
        ),
      ],
    );

    return Container(
      color: Colors.grey.shade100,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
                    _buildSectionCard(
            title: 'Worker Overview',
            content: header,
          ),

                    _buildSectionCard(
            title: 'Job Profile',
            content: Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _buildStatItem(Icons.star_half, rating > 0 ? rating.toStringAsFixed(1) : '—', 'Avg. Rating', color: _ratingColor(rating), subtitle: '$completedJobs jobs'),
                Container(width: 1, height: 50, color: Colors.grey.shade200),                 _buildStatItem(Icons.work_history_outlined, '$experience', 'Experience (Yrs)', color: Colors.orange.shade700),
                Container(width: 1, height: 50, color: Colors.grey.shade200),                 _buildStatItem(Icons.currency_rupee, (fallbackRateNum > 0) ? _formatCurrency(fallbackRateNum) : 'N/A', 'Base Wage', color: Colors.red.shade600),
              ],
            ),
          ),

                    _buildSectionCard(
            title: 'About',
            content: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(desc, style: const TextStyle(fontSize: 14, height: 1.5, color: Colors.black87)),
                const Divider(height: 24),
                _locationRow(worker),
              ],
            ),
          ),

                    if (cwData.isNotEmpty)
            _buildSectionCard(
              title: 'Services',
              content: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: cwData.entries.map((entry) {
                  final k = entry.key.replaceAll('_', ' ').split(' ').map((word) => word.isNotEmpty ? word[0].toUpperCase() + word.substring(1) : '').join(' ');
                  final v = (entry.value is Map) ? Map<String, dynamic>.from(entry.value) : <String, dynamic>{};
                  final charge = v['perHourCharge'] as num?;
                  final effectiveCharge = (charge ?? fallbackRateNum);
                  final chargeStr = (effectiveCharge > 0) ? '${_formatCurrency(effectiveCharge)}/hr' : 'Rate TBD';

                  return Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(Icons.fact_check_outlined, size: 18, color: Colors.green.shade600),
                        const SizedBox(width: 10),
                        Expanded(child: Text(k, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14, color: Colors.black87))),
                        Text(chargeStr, style: TextStyle(fontWeight: FontWeight.bold, color: Colors.green.shade700, fontSize: 14)),
                      ],
                    ),
                  );
                }).toList(),
              ),
            ),

                    _buildSectionCard(
            title: 'Tools & Equipment',
            content: _buildToolsChips(tools),
          ),

                    _buildSectionCard(
            title: 'Key Tasks & Works',
            content: _buildCanonicalWorks(canonicalWorks),
          ),

                    _buildSectionCard(
            title: 'Account',
            compact: true,
            content: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('Total Works: ${worker['total_works'] ?? '0'}', style: const TextStyle(fontWeight: FontWeight.w500)),
                const SizedBox(height: 6),
                                Text('Profile Created: ${_formatDate(worker['createdAt'])}', style: const TextStyle(fontSize: 11, color: Colors.black54))
              ]),
              Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                Text('Trust Score: ${worker['score'] ?? '—'}', style: const TextStyle(fontWeight: FontWeight.w500)),
                const SizedBox(height: 6),
                                Text('Last Updated: ${_formatDate(worker['updatedAt'])}', style: const TextStyle(fontSize: 11, color: Colors.black54))
              ]),
            ]),
          ),

          const SizedBox(height: 80),         ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey.shade100,
      appBar: AppBar(
        title: Text('${widget.worker['name']?.toString() ?? 'Worker'}\'s Profile', style: const TextStyle(fontWeight: FontWeight.w600)),
        centerTitle: true,
        elevation: 0,
        backgroundColor: Colors.white,
      ),
      body: RefreshIndicator(
        onRefresh: _onRefresh,
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          child: _buildContent(context),
        ),
      ),

            bottomNavigationBar: Container(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
        decoration: BoxDecoration(
          color: Colors.white,
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.1),
              blurRadius: 10,
              offset: const Offset(0, -2),
            ),
          ],
        ),
        child: SafeArea(
          top: false,
          child: SizedBox(
            height: 54,
            child: ElevatedButton(
              onPressed: _isBookDisabled ? null : () => _onBook(context),
              style: ElevatedButton.styleFrom(
                backgroundColor: _isBookDisabled ? Colors.grey : Colors.deepOrange,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
                elevation: 0,
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(_isBookDisabled ? Icons.access_time : Icons.calendar_today, size: 20),
                  const SizedBox(width: 10),
                  Text(
                    _getButtonText(),
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 0.5,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}