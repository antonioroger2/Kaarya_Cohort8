import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../core/theme.dart';
import '../../core/design_tokens.dart';
import '../../core/api_client.dart';
import './otp_viewer_screen.dart';
import './otp_input_screen.dart';
import './rating_dialog.dart';

// ─────────────────────────────────────────────
//  Status helpers
// ─────────────────────────────────────────────
class _StatusConfig {
  final String label;
  final Color color;
  final IconData icon;
  const _StatusConfig(this.label, this.color, this.icon);
}

_StatusConfig _resolveStatus(String code) {
  switch (code.toLowerCase()) {
    case 'b1': return const _StatusConfig('Request Sent',   Color(0xFFFF8F00), Icons.send_rounded);
    case 'b2': return const _StatusConfig('Booking Pending',Color(0xFFFF8F00), Icons.hourglass_top_rounded);
    case 'a1': return const _StatusConfig('Scheduled',      Color(0xFF1E88E5), Icons.event_available_rounded);
    case 'w1': return const _StatusConfig('Worker Arrived', Color(0xFF8E24AA), Icons.directions_walk_rounded);
    case 'w2': return const _StatusConfig('In Progress',    Color(0xFF00ACC1), Icons.construction_rounded);
    case 'e1': return const _StatusConfig('Payment Due',    Color(0xFFFF8F00), Icons.payment_rounded);
    case 'e2': return const _StatusConfig('Payment Due',    Color(0xFFFF8F00), Icons.payment_rounded);
    case 'e3': return const _StatusConfig('Completed',      Color(0xFF43A047), Icons.check_circle_rounded);
    case 'cancelled': return const _StatusConfig('Cancelled', Color(0xFFEF5350), Icons.block_rounded);
    case 'rejected':  return const _StatusConfig('Declined',  Color(0xFFEF5350), Icons.cancel_rounded);
    default: return _StatusConfig(code, Colors.grey, Icons.info_rounded);
  }
}

// ─────────────────────────────────────────────
//  Main Screen
// ─────────────────────────────────────────────
class BookingDetailsScreen extends StatefulWidget {
  final String bookingId;
  final String userId;
  final bool isWorker;

  const BookingDetailsScreen({
    super.key,
    required this.bookingId,
    required this.userId,
    required this.isWorker,
  });

  @override
  State<BookingDetailsScreen> createState() => _BookingDetailsScreenState();
}

class _BookingDetailsScreenState extends State<BookingDetailsScreen> {
  bool _isLoading = false;
  late Stream<DocumentSnapshot> _bookingStream;

  @override
  void initState() {
    super.initState();
    _bookingStream = _buildBookingStream();
  }

  @override
  void didUpdateWidget(covariant BookingDetailsScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.bookingId != widget.bookingId) {
      _bookingStream = _buildBookingStream();
    }
  }

  Stream<DocumentSnapshot> _buildBookingStream() {
    return FirebaseFirestore.instance
        .collection('bookings')
        .doc(widget.bookingId)
        .snapshots();
  }

  void _showLoading(bool loading) => setState(() => _isLoading = loading);

  void _showError(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(children: [
          const Icon(Icons.error_outline, color: Colors.white, size: 18),
          const SizedBox(width: 8),
          Expanded(child: Text(message)),
        ]),
        backgroundColor: AppDesignTokens.danger,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    );
  }

  void _showSuccess(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(children: [
          const Icon(Icons.check_circle_outline, color: Colors.white, size: 18),
          const SizedBox(width: 8),
          Text(message),
        ]),
        backgroundColor: AppDesignTokens.success,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    );
  }

  // ── All original business logic preserved unchanged ──────────────────────

  Future<void> _attemptStartJob(Map<String, dynamic> bookingData) async {
    DateTime? date;
    if (bookingData['appointmentDate'] is Timestamp) {
      date = (bookingData['appointmentDate'] as Timestamp).toDate();
    } else if (bookingData['bookingDate'] is Timestamp) {
      date = (bookingData['bookingDate'] as Timestamp).toDate();
    } else if (bookingData['date'] is String) {
      try {
        date = DateFormat('yyyy-MM-dd').parse(bookingData['date']);
      } catch (_) {
        date = null;
      }
    }

    if (date == null) {
      _showError("Missing appointment date on booking.");
      return;
    }
    final startHour = bookingData['startHour'] ?? 0;
    final scheduledStart = DateTime(date.year, date.month, date.day, startHour);
    final now = DateTime.now();
    final allowedStart = scheduledStart.subtract(const Duration(hours: 1));
    final allowedEnd = scheduledStart.add(const Duration(hours: 1));

    if (now.isBefore(allowedStart)) {
      _showError("Too early! Job can start from ${DateFormat.jm().format(allowedStart)}.");
      return;
    }
    if (now.isAfter(allowedEnd)) {
      _showError("Job start time has expired.");
      return;
    }

    _showLoading(true);
    try {
      final response = await ApiClient.generateStartOtp(widget.bookingId);
      if (response['ok'] == true) {
        _showLoading(false);
        if (!mounted) return;
        Navigator.of(context).push(MaterialPageRoute(
          builder: (_) => OtpViewerScreen(
            bookingId: widget.bookingId,
            otpType: 'start',
            correlationId: response['correlationId'],
            otpCode: response['otp'] as String?,
          ),
        )).then((_) => setState(() {}));
      }
    } catch (e) {
      _showError(e.toString());
      _showLoading(false);
    }
  }

  Future<void> _generateEndOtp() async {
    bool paymentSuccess = await _processPayment();
    if (!paymentSuccess) return;

    _showLoading(true);
    try {
      final response = await ApiClient.generateEndOtp(widget.bookingId);
      if (response['ok'] == true) {
        _showLoading(false);
        if (!mounted) return;
        Navigator.of(context).push(MaterialPageRoute(
          builder: (_) => OtpViewerScreen(
            bookingId: widget.bookingId,
            otpType: 'end',
            correlationId: response['correlationId'],
            otpCode: response['otp'] as String?,
          ),
        )).then((_) => setState(() {}));
      }
    } catch (e) {
      _showError(e.toString());
      _showLoading(false);
    }
  }

  Future<bool> _processPayment() async {
    return await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('Confirm Payment'),
        content: const Text('Proceed with payment to complete the job?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Pay Now'),
          ),
        ],
      ),
    ) ?? false;
  }

  Future<void> _rateJob(Map<String, dynamic> bookingData) async {
    final workerName = bookingData['workerInfo']?['name'] ?? 'Worker';
    final workerId = bookingData['workerId'];
    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => RatingDialog(workerName: workerName),
    );
    if (result == null || workerId == null) return;

    final rating = result['rating'] as double;
    final review = result['review'] as String;

    _showLoading(true);
    try {
      await ApiClient.submitRating(widget.bookingId, rating, workerId, widget.userId, review);
      if (!mounted) return;
      _showSuccess('Rating submitted successfully!');
    } catch (e) {
      _showError(e.toString());
    } finally {
      if (mounted) _showLoading(false);
    }
  }

  Future<void> _launchMaps(String address, double? lat, double? lng) async {
    if (lat == null || lng == null) return;
    final uri = Uri.parse("https://www.google.com/maps/dir/?api=1&destination=$lat,$lng");
    try {
      if (!await launchUrl(uri, mode: LaunchMode.externalApplication)) {
        await launchUrl(uri, mode: LaunchMode.platformDefault);
      }
    } catch (_) {
      if (mounted) _showError('Could not open Maps');
    }
  }

  // ── Build ────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppDesignTokens.surface,
      appBar: _buildAppBar(),
      body: DoodleBackground(
        child: StreamBuilder<DocumentSnapshot>(
          stream: _bookingStream,
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Center(child: CircularProgressIndicator(color: AppDesignTokens.primary));
            }
            if (!snapshot.hasData || !snapshot.data!.exists) {
              return _buildEmptyState('Booking not found', Icons.search_off_rounded);
            }

            final bookingData = snapshot.data!.data() as Map<String, dynamic>;
            final status = (bookingData['status'] ?? '').toString().toLowerCase();

            if (status == 'cancelled' || status == 'rejected') {
              return _buildTerminalState(status == 'rejected');
            }

            final counterpartId = widget.isWorker ? bookingData['userId'] : bookingData['workerId'];
            final counterpartCollection = widget.isWorker ? 'users' : 'workers';

            return FutureBuilder<DocumentSnapshot>(
              future: counterpartId != null
                  ? FirebaseFirestore.instance.collection(counterpartCollection).doc(counterpartId).get()
                  : null,
              builder: (context, profileSnapshot) {
                Map<String, dynamic>? profileData;
                if (profileSnapshot.hasData && profileSnapshot.data!.exists) {
                  profileData = profileSnapshot.data!.data() as Map<String, dynamic>;
                }
                return _buildContent(bookingData, profileData,
                    (bookingData['createTime'] as Timestamp?)?.toDate());
              },
            );
          },
        ),
      ),
    );
  }

  PreferredSizeWidget _buildAppBar() {
    return AppBar(
      backgroundColor: Colors.white,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      scrolledUnderElevation: 1,
      shadowColor: Colors.black12,
      leading: IconButton(
        icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 20),
        color: AppDesignTokens.primary,
        onPressed: () => Navigator.pop(context),
      ),
      title: const Text(
        'Booking Details',
        style: TextStyle(
          fontWeight: FontWeight.w700,
          color: AppDesignTokens.primary,
          fontSize: 18,
          letterSpacing: -0.3,
        ),
      ),
      centerTitle: false,
    );
  }

  Widget _buildTerminalState(bool isRejected) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(40),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: AppDesignTokens.danger.withOpacity(0.08),
                shape: BoxShape.circle,
              ),
              child: Icon(
                isRejected ? Icons.cancel_rounded : Icons.block_rounded,
                size: 56,
                color: AppDesignTokens.danger.withOpacity(0.7),
              ),
            ),
            const SizedBox(height: 24),
            Text(
              isRejected ? 'Booking Declined' : 'Booking Cancelled',
              style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w700, color: Color(0xFF37474F)),
            ),
            const SizedBox(height: 10),
            Text(
              'This booking is no longer active.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.grey[500], fontSize: 15, height: 1.5),
            ),
            const SizedBox(height: 32),
            OutlinedButton.icon(
              onPressed: () => Navigator.pop(context),
              icon: const Icon(Icons.arrow_back_rounded, size: 18),
              label: const Text('Go Back'),
              style: OutlinedButton.styleFrom(
                foregroundColor: AppDesignTokens.primary,
                side: const BorderSide(color: AppDesignTokens.primary),
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyState(String message, IconData icon) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, size: 56, color: Colors.grey[300]),
          const SizedBox(height: 16),
          Text(message, style: TextStyle(color: Colors.grey[500], fontSize: 16)),
        ],
      ),
    );
  }

  // ── Content ───────────────────────────────────────────────────────────────

  Widget _buildContent(Map<String, dynamic> bookingData, Map<String, dynamic>? profileData, DateTime? createTime) {
    final dateStr = bookingData['date'] as String?;
    final startHour = bookingData['startHour'] ?? 0;
    final endHour = bookingData['endHour'] ?? 0;
    final statusCode = bookingData['status'] ?? 'Unknown';
    final wage = (bookingData['wage'] ?? 0).toInt();

    final scheduledDate = dateStr != null
        ? DateFormat('yyyy-MM-dd').parse(dateStr)
      : (bookingData['appointmentDate'] as Timestamp?
        ?? bookingData['bookingDate'] as Timestamp?
        ?? Timestamp.now())
          .toDate();

    final startDateTime = DateTime(scheduledDate.year, scheduledDate.month, scheduledDate.day, startHour);
    final endDateTime   = DateTime(scheduledDate.year, scheduledDate.month, scheduledDate.day, endHour);
    final timeRangeText = '${DateFormat.jm().format(startDateTime)} – ${DateFormat.jm().format(endDateTime)}';

    final now = DateTime.now();
    final statusLower = statusCode.toString().toLowerCase();
    final bool isJobActive = !['cancelled', 'rejected', 'e3'].contains(statusLower);
    final bool isWithinPrivacyWindow =
        now.isAfter(startDateTime.subtract(const Duration(hours: 1))) &&
        now.isBefore(endDateTime.add(const Duration(hours: 1)));
    final bool showContactDetails = isJobActive && isWithinPrivacyWindow;

    final String name  = profileData?['name']  ?? (widget.isWorker ? bookingData['userName']  : bookingData['workerName'])  ?? 'N/A';
    final String phone = profileData?['phone'] ?? (widget.isWorker ? bookingData['userPhone'] : bookingData['workerPhone']) ?? 'N/A';
    final double rating = (profileData?['avgRating'] ?? 0.0).toDouble();

    final locMap = bookingData['location'] ?? {};
    final address = locMap['address'] ?? locMap['locality'] ?? 'Unknown';
    final landmark = locMap['landmark'] ?? '';
    final lat = locMap['lat'];
    final lng = locMap['lng'];
    final displayAddress = landmark.isNotEmpty ? '$address\n(Landmark: $landmark)' : address;

    return SingleChildScrollView(
      padding: AppDesignTokens.pagePad,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Status banner ──
          _StatusBanner(statusCode: statusCode),
          const SizedBox(height: 14),

          // ── AI tag ──
          _AIBookingTag(bookingData: bookingData, statusLower: statusLower),

          // ── Service details ──
          _SectionCard(
            title: 'Service Details',
            icon: Icons.calendar_month_rounded,
            children: [
              _DetailRow(icon: Icons.tag_rounded, color: AppDesignTokens.primary, label: 'Booking ID: ${widget.bookingId}'),
              if (createTime != null)
                _DetailRow(icon: Icons.access_time_rounded, color: AppDesignTokens.primary, label: 'Requested on: ${DateFormat('MMM d, yyyy \'at\' h:mm a').format(createTime)}'),
              _DetailRow(icon: Icons.calendar_today_rounded, color: AppDesignTokens.primary, label: DateFormat('EEEE, MMMM d, yyyy').format(scheduledDate)),
              _DetailRow(icon: Icons.schedule_rounded, color: AppDesignTokens.primary, label: timeRangeText),
              _DetailRow(
                icon: Icons.currency_rupee_rounded,
                color: AppDesignTokens.success,
                label: '₹$wage',
                labelStyle: const TextStyle(color: AppDesignTokens.success, fontWeight: FontWeight.w700, fontSize: 16),
              ),
              if ((bookingData['serviceCategory'] ?? 'General') != 'General')
                _DetailRow(icon: Icons.category_rounded, color: AppDesignTokens.accent, label: 'Category: ${bookingData['serviceCategory']}'),
              if ((bookingData['requiredTools'] as List?)?.isNotEmpty == true)
                _DetailRow(
                  icon: Icons.build_rounded,
                  color: AppDesignTokens.accent,
                  label: 'Tools: ${(bookingData['requiredTools'] as List).join(", ")}',
                ),
              if ((bookingData['candidateWorkers'] as List?)?.isNotEmpty == true)
                _DetailRow(icon: Icons.group_rounded, color: AppDesignTokens.info, label: '${(bookingData['candidateWorkers'] as List).length} workers contacted'),
              if ((bookingData['lastEscalationLevel'] ?? 0) > 0)
                _DetailRow(icon: Icons.notifications_active_rounded, color: AppDesignTokens.warning, label: 'Notification escalations: Level ${bookingData['lastEscalationLevel']}'),
              // Worker-only address
              if (widget.isWorker) ...[
                const SizedBox(height: 4),
                const Divider(),
                const SizedBox(height: 4),
                _DetailRow(
                  icon: Icons.location_on_rounded,
                  color: showContactDetails ? AppDesignTokens.danger : Colors.grey,
                  label: showContactDetails ? displayAddress : 'Address hidden until job time',
                  labelStyle: TextStyle(
                    fontWeight: FontWeight.w500,
                    color: showContactDetails ? const Color(0xFF37474F) : Colors.grey,
                  ),
                ),
                if (showContactDetails)
                  Padding(
                    padding: const EdgeInsets.only(top: 12),
                    child: _ActionButton(
                      icon: Icons.map_rounded,
                      label: 'Navigate via Google Maps',
                      color: AppDesignTokens.info,
                      onPressed: () => _launchMaps(address, lat?.toDouble(), lng?.toDouble()),
                    ),
                  ),
              ],
            ],
          ),
          const SizedBox(height: 14),

          // ── Job description ──
          if ((bookingData['notes'] ?? '').toString().trim().isNotEmpty)
            _SectionCard(
              title: 'Job Description',
              icon: Icons.description_rounded,
              children: [
                Text(
                  bookingData['notes'],
                  style: TextStyle(fontSize: 14, color: Colors.grey[700], height: 1.55),
                ),
              ],
            ),
          if ((bookingData['notes'] ?? '').toString().trim().isNotEmpty)
            const SizedBox(height: 14),

          // ── Contact card ──
          _ContactCard(
            isWorker: widget.isWorker,
            name: name,
            phone: phone,
            rating: rating,
            showContactDetails: showContactDetails,
          ),
          const SizedBox(height: 14),

          // ── Worker request status ──
          if (widget.isWorker && bookingData['workerId'] == widget.userId)
            _WorkerRequestStatus(bookingId: widget.bookingId, userId: widget.userId),

          // ── Rating & review card ──
          if (statusLower == 'e3' || statusLower == 'r1') ...[
            _RatingReviewCard(bookingData: bookingData),
            const SizedBox(height: 14),
          ],

          // ── Action buttons ──
          _buildActionButtons(bookingData, statusCode, (bookingData['rating'] ?? 0).toDouble(), startDateTime),
          const SizedBox(height: 28),
        ],
      ),
    );
  }

  // ── Action buttons (all original logic preserved) ────────────────────────

  Widget _buildActionButtons(Map<String, dynamic> bookingData, String status, double rating, DateTime scheduledStart) {
    if (_isLoading) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 24),
        child: Center(child: CircularProgressIndicator(color: AppDesignTokens.primary)),
      );
    }

    final now = DateTime.now();
    List<Widget> buttons = [];

    if (widget.isWorker) {
      switch (status) {
        case 'a1':
          buttons.add(_InfoChip(message: 'Waiting for the client to initiate the job…', color: AppDesignTokens.info, icon: Icons.hourglass_top_rounded));
          break;
        case 'w1':
          buttons.add(_InfoChip(message: 'Check your app notifications for the Start OTP. Share the code verbally with the client when asked.', color: Color(0xFF8E24AA), icon: Icons.lock_rounded));
          break;
        case 'w2':
          buttons.add(_InfoChip(message: 'Job in progress…', color: Color(0xFF00ACC1), icon: Icons.construction_rounded));
          break;
        case 'e1':
        case 'e2':
          buttons.add(_InfoChip(message: 'Check your app notifications for the End OTP. Share the code verbally with the client when asked.', color: Color(0xFF8E24AA), icon: Icons.lock_rounded));
          break;
        case 'e3':
          buttons.add(_InfoChip(message: 'Job completed. Thank you!', color: AppDesignTokens.success, icon: Icons.check_circle_rounded));
          break;
      }
    } else {
      switch (status) {
        case 'a1':
          final allowedStart = scheduledStart.subtract(const Duration(hours: 1));
          final allowedEnd   = scheduledStart.add(const Duration(hours: 1));

          if (now.isBefore(allowedStart)) {
            buttons.add(_ActionButton(
              icon: Icons.access_time_rounded,
              label: 'Available at ${DateFormat.jm().format(allowedStart)}',
              color: Colors.grey,
              enabled: false,
            ));
          } else if (now.isAfter(allowedEnd)) {
            buttons.add(_ActionButton(
              icon: Icons.error_outline_rounded,
              label: 'Job Time Expired',
              color: AppDesignTokens.danger,
              enabled: false,
            ));
          } else {
            buttons.add(_InfoChip(
              message: 'Initiate Start OTP only after agreeing on job terms, wage, and scope with the worker.',
              icon: Icons.tips_and_updates_rounded,
              color: AppDesignTokens.info,
            ));
            buttons.add(const SizedBox(height: 10));
            buttons.add(_ActionButton(
              icon: Icons.play_arrow_rounded,
              label: 'Start Job — Get Worker OTP',
              color: AppDesignTokens.success,
              onPressed: () => _attemptStartJob(bookingData),
            ));
          }
          break;

        case 'w1':
          buttons.add(_ActionButton(
            icon: Icons.password_rounded,
            label: 'Verify Worker\'s Start OTP',
            color: const Color(0xFF8E24AA),
            onPressed: () async {
              final result = await Navigator.of(context).push(MaterialPageRoute(
                builder: (_) => OtpInputScreen(
                  bookingId: widget.bookingId,
                  otpType: 'start',
                  correlationId: bookingData['startOTPCorrelationId'] ?? '',
                ),
              ));
              if (result == true) setState(() {});
            },
          ));
          break;

        case 'w2':
          buttons.add(_InfoChip(
            message: 'Initiate End OTP only after work is completed, inspected, and you are ready to make payment.',
            icon: Icons.tips_and_updates_rounded,
            color: AppDesignTokens.warning,
          ));
          buttons.add(const SizedBox(height: 10));
          buttons.add(_ActionButton(
            icon: Icons.stop_rounded,
            label: 'End Job — Get Worker OTP',
            color: AppDesignTokens.danger,
            onPressed: _generateEndOtp,
          ));
          break;

        case 'e1':
        case 'e2':
          buttons.add(_ActionButton(
            icon: Icons.password_rounded,
            label: 'Verify Worker\'s End OTP',
            color: const Color(0xFF8E24AA),
            onPressed: () async {
              final result = await Navigator.of(context).push(MaterialPageRoute(
                builder: (_) => OtpInputScreen(
                  bookingId: widget.bookingId,
                  otpType: 'end',
                  correlationId: bookingData['endOTPCorrelationId'] ?? '',
                ),
              ));
              if (result == true) setState(() {});
            },
          ));
          break;

        case 'e3':
          if (rating == 0) {
            buttons.add(_ActionButton(
              icon: Icons.star_rounded,
              label: 'Rate This Service',
              color: Colors.amber[700]!,
              onPressed: () => _rateJob(bookingData),
            ));
          } else {
            buttons.add(_InfoChip(message: 'Job completed and rated. Thank you!', color: AppDesignTokens.success, icon: Icons.verified_rounded));
          }
          break;
      }
    }

    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: buttons);
  }
}

// ─────────────────────────────────────────────
//  Reusable sub-widgets
// ─────────────────────────────────────────────

/// Coloured pill banner at the top showing booking status.
class _StatusBanner extends StatelessWidget {
  final String statusCode;
  const _StatusBanner({required this.statusCode});

  @override
  Widget build(BuildContext context) {
    final cfg = _resolveStatus(statusCode);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
      decoration: BoxDecoration(
        color: cfg.color.withOpacity(0.08),
        borderRadius: const BorderRadius.all(AppDesignTokens.cardRadius),
        border: Border.all(color: cfg.color.withOpacity(0.25), width: 1.2),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(color: cfg.color.withOpacity(0.15), shape: BoxShape.circle),
            child: Icon(cfg.icon, color: cfg.color, size: 20),
          ),
          const SizedBox(width: 14),
          Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('Booking Status', style: TextStyle(fontSize: 11, color: Colors.grey, letterSpacing: .5)),
            const SizedBox(height: 2),
            Text(cfg.label, style: TextStyle(fontWeight: FontWeight.w700, color: cfg.color, fontSize: 16)),
          ]),
        ],
      ),
    );
  }
}

/// Highlighted AI-generated booking tag.
class _AIBookingTag extends StatelessWidget {
  final Map<String, dynamic> bookingData;
  final String statusLower;
  const _AIBookingTag({required this.bookingData, required this.statusLower});

  @override
  Widget build(BuildContext context) {
    final bool isAI = bookingData['isAIGenerated'] ?? false;
    if (!isAI) return const SizedBox.shrink();

    final int count = bookingData['requestedWorkerCount'] ?? 0;
    final List discovered = bookingData['discoveredSkills'] as List? ?? [];
    final bool showSkills = discovered.isNotEmpty && (statusLower == 'e3' || statusLower == 'r1');

    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [AppDesignTokens.info.withOpacity(0.07), AppDesignTokens.accent.withOpacity(0.07)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: const BorderRadius.all(AppDesignTokens.cardRadius),
        border: Border.all(color: AppDesignTokens.info.withOpacity(0.25), width: 1.2),
      ),
      child: Row(children: [
        Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(color: AppDesignTokens.info.withOpacity(0.15), shape: BoxShape.circle),
          child: const Icon(Icons.smart_toy_rounded, color: AppDesignTokens.info, size: 20),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('KaaryaAI – Smart Booking Agent',
                style: TextStyle(fontWeight: FontWeight.w700, color: AppDesignTokens.info.withOpacity(0.9), fontSize: 13.5)),
            const SizedBox(height: 2),
            Text('Requested $count workers', style: const TextStyle(color: Colors.blueGrey, fontSize: 12)),
            if (showSkills) ...[
              const SizedBox(height: 2),
              Text('✨ Learned ${discovered.length} new skills',
                  style: TextStyle(color: AppDesignTokens.info, fontSize: 11, fontWeight: FontWeight.w600)),
            ],
          ]),
        ),
        Icon(Icons.auto_awesome_rounded, color: AppDesignTokens.info.withOpacity(0.45), size: 18),
      ]),
    );
  }
}

/// Generic section card with a title + icon header and arbitrary children.
class _SectionCard extends StatelessWidget {
  final String title;
  final IconData icon;
  final List<Widget> children;
  const _SectionCard({required this.title, required this.icon, required this.children});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: AppDesignTokens.cardDecoration(),
      child: Padding(
        padding: AppDesignTokens.cardPad,
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Icon(icon, color: AppDesignTokens.primary, size: 18),
            const SizedBox(width: 8),
            Text(title, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15, color: Color(0xFF263238))),
          ]),
          const SizedBox(height: 14),
          const Divider(height: 1),
          const SizedBox(height: 14),
          ...children,
        ]),
      ),
    );
  }
}

/// Icon + text row used inside section cards.
class _DetailRow extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String label;
  final TextStyle? labelStyle;
  const _DetailRow({required this.icon, required this.color, required this.label, this.labelStyle});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Icon(icon, color: color, size: 18),
        const SizedBox(width: 10),
        Expanded(
          child: Text(label, style: labelStyle ?? const TextStyle(fontSize: 14, color: Color(0xFF37474F), height: 1.4)),
        ),
      ]),
    );
  }
}

/// Profile + contact card.
class _ContactCard extends StatelessWidget {
  final bool isWorker;
  final String name, phone;
  final double rating;
  final bool showContactDetails;
  const _ContactCard({required this.isWorker, required this.name, required this.phone, required this.rating, required this.showContactDetails});

  @override
  Widget build(BuildContext context) {
    final isHidden = !showContactDetails;
    return Container(
      decoration: AppDesignTokens.cardDecoration(),
      child: Padding(
        padding: AppDesignTokens.cardPad,
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Icon(isWorker ? Icons.person_rounded : Icons.engineering_rounded, color: AppDesignTokens.primary, size: 18),
            const SizedBox(width: 8),
            Text(isWorker ? 'Client Information' : 'Service Provider',
                style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15, color: Color(0xFF263238))),
          ]),
          const SizedBox(height: 16),
          Row(children: [
            CircleAvatar(
              radius: 26,
              backgroundColor: AppDesignTokens.primary.withOpacity(0.1),
              child: Text(
                name.isNotEmpty ? name[0].toUpperCase() : '?',
                style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w700, color: AppDesignTokens.primary),
              ),
            ),
            const SizedBox(width: 14),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(name, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 17, color: Color(0xFF263238))),
              if (!isWorker)
                Row(children: [
                  const Icon(Icons.star_rounded, size: 16, color: Colors.amber),
                  const SizedBox(width: 4),
                  Text(rating.toStringAsFixed(1), style: const TextStyle(fontSize: 13, color: Colors.blueGrey)),
                ]),
            ])),
          ]),
          const SizedBox(height: 16),
          const Divider(height: 1),
          const SizedBox(height: 14),
          Row(children: [
            Icon(Icons.phone_rounded, color: isHidden ? Colors.grey[400] : AppDesignTokens.primary, size: 18),
            const SizedBox(width: 10),
            Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text('Phone', style: TextStyle(fontSize: 11, color: Colors.grey, letterSpacing: .4)),
              const SizedBox(height: 2),
              Text(
                isHidden ? 'Hidden until job time' : phone,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: isHidden ? FontWeight.normal : FontWeight.w600,
                  color: isHidden ? Colors.grey[400] : const Color(0xFF263238),
                ),
              ),
            ]),
          ]),
        ]),
      ),
    );
  }
}

/// Worker request status sub-card.
class _WorkerRequestStatus extends StatefulWidget {
  final String bookingId, userId;
  const _WorkerRequestStatus({required this.bookingId, required this.userId});

  @override
  State<_WorkerRequestStatus> createState() => _WorkerRequestStatusState();
}

class _WorkerRequestStatusState extends State<_WorkerRequestStatus> {
  late Stream<QuerySnapshot> _workerRequestStream;

  @override
  void initState() {
    super.initState();
    _workerRequestStream = _buildWorkerRequestStream();
  }

  @override
  void didUpdateWidget(covariant _WorkerRequestStatus oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.bookingId != widget.bookingId || oldWidget.userId != widget.userId) {
      _workerRequestStream = _buildWorkerRequestStream();
    }
  }

  Stream<QuerySnapshot> _buildWorkerRequestStream() {
    return FirebaseFirestore.instance
        .collection('bookings')
        .doc(widget.bookingId)
        .collection('workerRequests')
        .where('workerId', isEqualTo: widget.userId)
        .snapshots();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: StreamBuilder<QuerySnapshot>(
        stream: _workerRequestStream,
        builder: (context, snapshot) {
          if (!snapshot.hasData || snapshot.data!.docs.isEmpty) return const SizedBox.shrink();

          final data = snapshot.data!.docs.first.data() as Map<String, dynamic>;
          final reqStatus = data['status'] ?? 'unknown';
          final createdAt = data['createdAt'] as Timestamp?;
          final updatedAt = data['updatedAt'] as Timestamp?;

          Color statusColor;
          IconData statusIcon;
          switch (reqStatus) {
            case 'accepted': statusColor = AppDesignTokens.success; statusIcon = Icons.check_circle_rounded; break;
            case 'rejected': statusColor = AppDesignTokens.danger;  statusIcon = Icons.cancel_rounded; break;
            case 'pending':  statusColor = AppDesignTokens.warning; statusIcon = Icons.pending_rounded; break;
            default:         statusColor = Colors.grey; statusIcon = Icons.help_rounded;
          }

          return Container(
            decoration: AppDesignTokens.cardDecoration(borderColor: statusColor),
            child: Padding(
              padding: AppDesignTokens.cardPad,
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Text('Your Request Status',
                    style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15, color: Color(0xFF263238))),
                const SizedBox(height: 12),
                Row(children: [
                  Icon(statusIcon, color: statusColor, size: 22),
                  const SizedBox(width: 8),
                  Text(
                    reqStatus == 'accepted' ? 'Accepted' :
                    reqStatus == 'rejected' ? 'Declined'  :
                    reqStatus == 'pending'  ? 'Pending Response' :
                    '${reqStatus[0].toUpperCase()}${reqStatus.substring(1)}',
                    style: TextStyle(fontWeight: FontWeight.w700, color: statusColor),
                  ),
                ]),
                if (createdAt != null) ...[
                  const SizedBox(height: 8),
                  Text('Requested: ${DateFormat('MMM d, h:mm a').format(createdAt.toDate())}',
                      style: TextStyle(color: Colors.grey[500], fontSize: 12)),
                ],
                if (updatedAt != null && updatedAt != createdAt) ...[
                  const SizedBox(height: 4),
                  Text('Updated: ${DateFormat('MMM d, h:mm a').format(updatedAt.toDate())}',
                      style: TextStyle(color: Colors.grey[500], fontSize: 12)),
                ],
              ]),
            ),
          );
        },
      ),
    );
  }
}

/// Rating & review card shown after job completion.
class _RatingReviewCard extends StatelessWidget {
  final Map<String, dynamic> bookingData;
  const _RatingReviewCard({required this.bookingData});

  @override
  Widget build(BuildContext context) {
    final List discovered = bookingData['discoveredSkills'] as List? ?? [];

    return Container(
      decoration: AppDesignTokens.cardDecoration(borderColor: AppDesignTokens.success),
      child: Padding(
        padding: AppDesignTokens.cardPad,
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Row(children: [
            Icon(Icons.star_rounded, color: Colors.amber, size: 18),
            SizedBox(width: 8),
            Text('Your Rating & Review',
                style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15, color: Color(0xFF263238))),
          ]),
          const SizedBox(height: 14),
          Row(children: [
            ...List.generate(5, (i) => Icon(
              Icons.star_rounded,
              size: 22,
              color: i < (bookingData['rating'] ?? 0) ? Colors.amber : Colors.grey[200],
            )),
            const SizedBox(width: 10),
            Text('${bookingData['rating'] ?? 'Not rated'}',
                style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
            if (bookingData['aiAdjustedRating'] != null && bookingData['aiAdjustedRating'] != bookingData['rating']) ...[
              const SizedBox(width: 8),
              Text('(AI adjusted: ${bookingData['aiAdjustedRating']})',
                  style: const TextStyle(fontSize: 12, color: Colors.grey)),
            ],
          ]),
          if ((bookingData['aiProfessionalismScore'] ?? 0) > 0) ...[
            const SizedBox(height: 6),
            Text('Professionalism score: ${bookingData['aiProfessionalismScore']}',
                style: const TextStyle(fontSize: 12, color: AppDesignTokens.info)),
          ],
          if ((bookingData['review'] ?? '').toString().trim().isNotEmpty) ...[
            const SizedBox(height: 14),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.grey.shade50,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: Colors.grey.shade200),
              ),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Text('Review', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 11, color: Colors.grey, letterSpacing: .5)),
                const SizedBox(height: 6),
                Text('"${bookingData['review']}"', style: const TextStyle(fontStyle: FontStyle.italic, fontSize: 14, height: 1.45)),
              ]),
            ),
          ],
          if (discovered.isNotEmpty) ...[
            const SizedBox(height: 14),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppDesignTokens.info.withOpacity(0.06),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: AppDesignTokens.info.withOpacity(0.2)),
              ),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Row(children: [
                  Icon(Icons.lightbulb_rounded, color: AppDesignTokens.info, size: 15),
                  SizedBox(width: 6),
                  Text('AI-Discovered Skills',
                      style: TextStyle(fontWeight: FontWeight.w600, fontSize: 11, color: AppDesignTokens.info, letterSpacing: .4)),
                ]),
                const SizedBox(height: 6),
                Text(discovered.join(', '),
                    style: TextStyle(fontSize: 13, color: AppDesignTokens.info.withOpacity(0.85))),
              ]),
            ),
          ],
        ]),
      ),
    );
  }
}

/// Full-width primary action button.
class _ActionButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback? onPressed;
  final bool enabled;

  const _ActionButton({
    required this.icon,
    required this.label,
    required this.color,
    this.onPressed,
    this.enabled = true,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      child: ElevatedButton.icon(
        onPressed: enabled ? onPressed : null,
        icon: Icon(icon, size: 20),
        label: Text(label, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15)),
        style: ElevatedButton.styleFrom(
          backgroundColor: enabled ? color : Colors.grey[300],
          foregroundColor: enabled ? Colors.white : Colors.grey[500],
          disabledBackgroundColor: Colors.grey[200],
          disabledForegroundColor: Colors.grey[500],
          padding: const EdgeInsets.symmetric(vertical: 14),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          elevation: enabled ? 0 : 0,
        ),
      ),
    );
  }
}

/// Subtle info/hint chip used above action buttons.
class _InfoChip extends StatelessWidget {
  final String message;
  final Color color;
  final IconData icon;
  const _InfoChip({required this.message, required this.color, required this.icon});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: color.withOpacity(0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withOpacity(0.22), width: 1),
      ),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Icon(icon, color: color, size: 18),
        const SizedBox(width: 10),
        Expanded(
          child: Text(message,
              style: TextStyle(color: color.withOpacity(0.9), fontSize: 13.5, fontWeight: FontWeight.w500, height: 1.45)),
        ),
      ]),
    );
  }
}