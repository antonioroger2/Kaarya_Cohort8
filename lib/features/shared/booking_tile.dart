import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import '../../features/shared/booking_details_screen.dart';
import '../../features/user/worker_profile_view_screen.dart';
import '../../core/api_client.dart';


class _BT {
  static const Color primary = Color(0xFF00897B);
  static const Color surface = Colors.white;
  static const Color success = Color(0xFF43A047);
  static const Color danger  = Color(0xFFEF5350);
  static const Color warning = Color(0xFFFF8F00);
  static const Color info    = Color(0xFF1E88E5);

  static const Radius cardRadius = Radius.circular(18);

  static BoxDecoration cardDecoration() => BoxDecoration(
    color: surface,
    borderRadius: BorderRadius.all(cardRadius),
    boxShadow: const [BoxShadow(color: Color(0x0D000000), blurRadius: 14, offset: Offset(0, 4))],
  );
}

// ─────────────────────────────────────────────
//  Status config (mirrors BookingDetailsScreen)
// ─────────────────────────────────────────────
class _StatusCfg {
  final String label;
  final Color color;
  final IconData icon;
  const _StatusCfg(this.label, this.color, this.icon);
}

_StatusCfg _resolveStatus(String code) {
  switch (code.toLowerCase()) {
    case 'b1': return const _StatusCfg('Request Sent',    Color(0xFFFF8F00), Icons.send_rounded);
    case 'b2': return const _StatusCfg('Pending Approval',Color(0xFFFF8F00), Icons.hourglass_top_rounded);
    case 'a1': return const _StatusCfg('Scheduled',       Color(0xFF1E88E5), Icons.event_available_rounded);
    case 'w1': return const _StatusCfg('Worker Arrived',  Color(0xFF8E24AA), Icons.directions_walk_rounded);
    case 'w2': return const _StatusCfg('In Progress',     Color(0xFF00ACC1), Icons.construction_rounded);
    case 'e1': return const _StatusCfg('Payment Due',     Color(0xFFFF8F00), Icons.payment_rounded);
    case 'e2': return const _StatusCfg('Payment Due',     Color(0xFFFF8F00), Icons.payment_rounded);
    case 'e3': return const _StatusCfg('Completed',       Color(0xFF43A047), Icons.check_circle_rounded);
    case 'cancelled': return const _StatusCfg('Cancelled',Color(0xFFEF5350), Icons.block_rounded);
    case 'rejected':  return const _StatusCfg('Declined', Color(0xFFEF5350), Icons.cancel_rounded);
    default: return _StatusCfg(code, Colors.grey, Icons.info_rounded);
  }
}

// ─────────────────────────────────────────────
//  BookingTile
// ─────────────────────────────────────────────
class BookingTile extends StatefulWidget {
  final Map<String, dynamic> bookingData;
  final String? bookingId;

  const BookingTile({super.key, required this.bookingData, this.bookingId});

  @override
  State<BookingTile> createState() => _BookingTileState();
}

class _BookingTileState extends State<BookingTile> {
  bool _isCancelling = false;
  late String _displayStatus;

  Future<DocumentSnapshot>? _profileFuture;
  String? _counterpartId;

  String? get _currentBookingId => widget.bookingId ?? widget.bookingData['id'];

  // ── All original logic unchanged ─────────────────────────────────────────

  @override
  void initState() {
    super.initState();
    _displayStatus = widget.bookingData['status'] ?? 'Unknown';
    _initializeProfileFetch();
  }

  @override
  void didUpdateWidget(BookingTile oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.bookingData['status'] != oldWidget.bookingData['status']) {
      _displayStatus = widget.bookingData['status'] ?? 'Unknown';
    }
    if (oldWidget.bookingData['workerId'] != widget.bookingData['workerId'] ||
        oldWidget.bookingData['userId'] != widget.bookingData['userId']) {
      _initializeProfileFetch();
    }
  }

  void _initializeProfileFetch() {
    final currentUserId = FirebaseAuth.instance.currentUser?.uid;
    final workerId = widget.bookingData['workerId'];
    final currentUserIsWorker = (currentUserId == workerId);

    final idToFetch = currentUserIsWorker
        ? widget.bookingData['userId']
        : widget.bookingData['workerId'];

    _counterpartId = idToFetch;

    if (_counterpartId != null) {
      final collection = currentUserIsWorker ? 'users' : 'workers';
      _profileFuture = FirebaseFirestore.instance.collection(collection).doc(_counterpartId).get();
    } else {
      _profileFuture = null;
    }
  }

  String _capitalize(String s) => s.isEmpty ? s : s[0].toUpperCase() + s.substring(1);

  Future<void> _cancelBooking() async {
    if (_currentBookingId == null) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('Cancel Booking', style: TextStyle(fontWeight: FontWeight.w700)),
        content: const Text('Are you sure you want to cancel this booking?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('No')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: _BT.danger),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Yes, Cancel'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;
    setState(() => _isCancelling = true);

    try {
      final response = await ApiClient.post('/cancel-booking', {
        'bookingId': _currentBookingId,
        'userId': FirebaseAuth.instance.currentUser!.uid,
      });

      if (response['ok'] == true && mounted) {
        setState(() => _displayStatus = 'cancelled');
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: const Row(children: [
            Icon(Icons.check_circle_outline, color: Colors.white, size: 18),
            SizedBox(width: 8),
            Text('Booking cancelled.'),
          ]),
          backgroundColor: _BT.success,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Row(children: [
            const Icon(Icons.error_outline, color: Colors.white, size: 18),
            const SizedBox(width: 8),
            Expanded(child: Text('Error: $e')),
          ]),
          backgroundColor: _BT.danger,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ));
      }
    } finally {
      if (mounted) setState(() => _isCancelling = false);
    }
  }

  // ── Build ────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    DateTime date;
    try {
      if (widget.bookingData['date'] is String) {
        date = DateFormat('yyyy-MM-dd').parse(widget.bookingData['date']);
      } else if (widget.bookingData['bookingDate'] is Timestamp) {
        date = (widget.bookingData['bookingDate'] as Timestamp).toDate();
      } else {
        date = DateTime.now();
      }
    } catch (_) {
      date = DateTime.now();
    }

    final wage = (widget.bookingData['wage'] ?? 0).toInt();
    final rawService = widget.bookingData['serviceType'] ?? 'Service';
    final serviceType = _capitalize(rawService.toString());
    final isAI = widget.bookingData['isAIGenerated'] == true;
    final startHour = widget.bookingData['startHour'] ?? 0;
    final endHour   = widget.bookingData['endHour']   ?? 0;
    final duration  = endHour - startHour;
    final startTime = DateFormat.jm().format(DateTime(date.year, date.month, date.day, startHour));

    final currentUserId = FirebaseAuth.instance.currentUser?.uid;
    final workerId = widget.bookingData['workerId'];
    final currentUserIsWorker = (currentUserId == workerId);

    final cfg = _resolveStatus(_displayStatus);
    final canCancel = !currentUserIsWorker &&
        (_displayStatus == 'b2' || _displayStatus == 'b1' || _displayStatus == 'a1') &&
        !_isCancelling;

    return GestureDetector(
      onTap: () {
        if (_currentBookingId != null && currentUserId != null) {
          Navigator.of(context).push(MaterialPageRoute(
            builder: (_) => BookingDetailsScreen(
              bookingId: _currentBookingId!,
              userId: currentUserId,
              isWorker: currentUserIsWorker,
            ),
          ));
        }
      },
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
        decoration: _BT.cardDecoration(),
        clipBehavior: Clip.antiAlias,
        child: Column(
          children: [
            // ── Status header bar ──
            _StatusHeader(cfg: cfg, date: date, isAI: isAI),

            // ── Body ──
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Profile row
                  _profileFuture == null
                      ? _PendingProfileRow(serviceType: serviceType, isAI: isAI, bookingData: widget.bookingData)
                      : FutureBuilder<DocumentSnapshot>(
                          future: _profileFuture,
                          builder: (context, snapshot) {
                            if (snapshot.connectionState == ConnectionState.waiting) {
                              return const _SkeletonRow();
                            }
                            String displayName = currentUserIsWorker
                                ? (widget.bookingData['userName'] ?? 'Client')
                                : (widget.bookingData['workerName'] ?? 'Pending Assignment');
                            double rating = 0.0;
                            Map<String, dynamic>? profileData;

                            if (snapshot.hasData && snapshot.data!.exists) {
                              profileData = snapshot.data!.data() as Map<String, dynamic>;
                              displayName = profileData['name'] ?? displayName;
                              rating = (profileData['avgRating'] ?? 0.0).toDouble();
                            }

                            return _ProfileRow(
                              name: displayName,
                              subLabel: currentUserIsWorker ? 'Client' : 'Service Provider',
                              rating: rating,
                              showRating: !currentUserIsWorker,
                              onTap: (!currentUserIsWorker && widget.bookingData['workerId'] != null)
                                  ? () => Navigator.of(context).push(MaterialPageRoute(
                                        builder: (_) => WorkerProfileViewScreen(
                                          worker: profileData ?? {'name': displayName},
                                          userId: currentUserId!,
                                          workerId: widget.bookingData['workerId'],
                                        ),
                                      ))
                                  : null,
                            );
                          },
                        ),

                  const SizedBox(height: 12),
                  // Booking ID
                  if (_currentBookingId != null)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                      decoration: BoxDecoration(
                        color: _BT.primary.withOpacity(0.08),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: _BT.primary.withOpacity(0.2)),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.tag_rounded, size: 14, color: _BT.primary),
                          const SizedBox(width: 6),
                          Text(
                            'ID: ${_currentBookingId!}',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: _BT.primary,
                              letterSpacing: -0.2,
                            ),
                          ),
                        ],
                      ),
                    ),
                  const SizedBox(height: 16),
                  const Divider(height: 1),
                  const SizedBox(height: 14),

                  // Time + wage row
                  Row(
                    children: [
                      Expanded(
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          _MetaChip(icon: Icons.schedule_rounded, label: 'Start $startTime'),
                          const SizedBox(height: 8),
                          _MetaChip(icon: Icons.timelapse_rounded, label: '$duration hr${duration != 1 ? 's' : ''} duration'),
                        ]),
                      ),
                      // Wage badge
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                        decoration: BoxDecoration(
                          color: _BT.success.withOpacity(0.08),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: _BT.success.withOpacity(0.25)),
                        ),
                        child: Text(
                          '₹$wage',
                          style: const TextStyle(
                            fontWeight: FontWeight.w800,
                            fontSize: 20,
                            color: _BT.success,
                            letterSpacing: -0.5,
                          ),
                        ),
                      ),
                    ],
                  ),

                  // Cancel button
                  if (canCancel) ...[
                    const SizedBox(height: 16),
                    SizedBox(
                      width: double.infinity,
                      child: OutlinedButton.icon(
                        onPressed: _cancelBooking,
                        icon: const Icon(Icons.cancel_outlined, size: 18),
                        label: const Text('Cancel Booking', style: TextStyle(fontWeight: FontWeight.w600)),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: _BT.danger,
                          side: BorderSide(color: _BT.danger.withOpacity(0.6)),
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        ),
                      ),
                    ),
                  ],

                  if (_isCancelling)
                    const Padding(
                      padding: EdgeInsets.only(top: 16),
                      child: Center(child: CircularProgressIndicator(color: _BT.primary, strokeWidth: 2.5)),
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

// ─────────────────────────────────────────────
//  Sub-widgets
// ─────────────────────────────────────────────

/// Coloured header strip with status + date.
class _StatusHeader extends StatelessWidget {
  final _StatusCfg cfg;
  final DateTime date;
  final bool isAI;
  const _StatusHeader({required this.cfg, required this.date, required this.isAI});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [cfg.color.withOpacity(0.12), cfg.color.withOpacity(0.04)],
          begin: Alignment.centerLeft,
          end: Alignment.centerRight,
        ),
      ),
      child: Row(children: [
        Container(
          padding: const EdgeInsets.all(6),
          decoration: BoxDecoration(color: cfg.color.withOpacity(0.15), shape: BoxShape.circle),
          child: Icon(cfg.icon, color: cfg.color, size: 16),
        ),
        const SizedBox(width: 10),
        Text(cfg.label, style: TextStyle(color: cfg.color, fontWeight: FontWeight.w700, fontSize: 13.5)),
        if (isAI) ...[
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.all(3),
            decoration: BoxDecoration(color: const Color(0xFF1E88E5).withOpacity(0.15), shape: BoxShape.circle),
            child: const Icon(Icons.smart_toy_rounded, color: Color(0xFF1E88E5), size: 13),
          ),
        ],
        const Spacer(),
        Text(
          DateFormat('EEE, MMM d').format(date),
          style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13, color: Color(0xFF546E7A)),
        ),
      ]),
    );
  }
}

/// Profile row when a worker/client is assigned.
class _ProfileRow extends StatelessWidget {
  final String name, subLabel;
  final double rating;
  final bool showRating;
  final VoidCallback? onTap;
  const _ProfileRow({required this.name, required this.subLabel, required this.rating, required this.showRating, this.onTap});

  @override
  Widget build(BuildContext context) {
    final row = Row(children: [
      CircleAvatar(
        radius: 22,
        backgroundColor: const Color(0xFF00897B).withOpacity(0.1),
        child: Text(
          name.isNotEmpty ? name[0].toUpperCase() : '?',
          style: const TextStyle(color: Color(0xFF00897B), fontWeight: FontWeight.w700, fontSize: 18),
        ),
      ),
      const SizedBox(width: 12),
      Expanded(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(subLabel, style: const TextStyle(fontSize: 11, color: Colors.grey, letterSpacing: .4)),
          const SizedBox(height: 2),
          Row(children: [
            Flexible(
              child: Text(name,
                  style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16, color: Color(0xFF263238)),
                  overflow: TextOverflow.ellipsis),
            ),
            if (onTap != null) ...[
              const SizedBox(width: 6),
              const Icon(Icons.chevron_right_rounded, size: 18, color: Color(0xFF00897B)),
            ],
          ]),
          if (showRating && rating > 0)
            Row(children: [
              const Icon(Icons.star_rounded, size: 14, color: Colors.amber),
              const SizedBox(width: 3),
              Text(rating.toStringAsFixed(1), style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Color(0xFF546E7A))),
            ]),
        ]),
      ),
    ]);

    if (onTap != null) {
      return InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: row,
      );
    }
    return row;
  }
}

/// Profile row for bookings not yet assigned (pending / AI matching).
class _PendingProfileRow extends StatelessWidget {
  final String serviceType;
  final bool isAI;
  final Map<String, dynamic> bookingData;
  const _PendingProfileRow({required this.serviceType, required this.isAI, required this.bookingData});

  @override
  Widget build(BuildContext context) {
    final subText = isAI
        ? 'AI Matching ${bookingData['requestedWorkerCount'] ?? 0} Workers'
        : 'Pending Assignment';

    return Row(children: [
      CircleAvatar(
        radius: 22,
        backgroundColor: Colors.grey.withOpacity(0.12),
        child: Icon(
          isAI ? Icons.smart_toy_rounded : Icons.search_rounded,
          color: isAI ? const Color(0xFF1E88E5) : Colors.grey[500],
          size: 20,
        ),
      ),
      const SizedBox(width: 12),
      Expanded(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(serviceType,
              style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16, color: Color(0xFF263238)),
              overflow: TextOverflow.ellipsis),
          const SizedBox(height: 2),
          Text(
            subText,
            style: TextStyle(
              color: isAI ? const Color(0xFF1E88E5) : Colors.orange[800],
              fontSize: 12,
              fontStyle: FontStyle.italic,
              fontWeight: FontWeight.w500,
            ),
          ),
        ]),
      ),
    ]);
  }
}

/// Small icon + label metadata chip.
class _MetaChip extends StatelessWidget {
  final IconData icon;
  final String label;
  const _MetaChip({required this.icon, required this.label});

  @override
  Widget build(BuildContext context) {
    return Row(children: [
      Icon(icon, size: 16, color: Colors.grey[500]),
      const SizedBox(width: 6),
      Text(label, style: TextStyle(fontSize: 13.5, color: Colors.grey[700], fontWeight: FontWeight.w500)),
    ]);
  }
}

/// Loading state skeleton.
class _SkeletonRow extends StatelessWidget {
  const _SkeletonRow();

  @override
  Widget build(BuildContext context) {
    return Row(children: [
      CircleAvatar(radius: 22, backgroundColor: Colors.grey[200]),
      const SizedBox(width: 12),
      Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Container(width: 70, height: 10, decoration: BoxDecoration(color: Colors.grey[200], borderRadius: BorderRadius.circular(4))),
        const SizedBox(height: 6),
        Container(width: 120, height: 14, decoration: BoxDecoration(color: Colors.grey[300], borderRadius: BorderRadius.circular(4))),
      ]),
    ]);
  }
}