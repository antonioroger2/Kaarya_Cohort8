import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:intl/intl.dart';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;
import '../../core/api_client.dart';
import '../../core/design_tokens.dart';
import '../../core/footer.dart';

// ─────────────────────────────────────────────
//  Chat message model
// ─────────────────────────────────────────────
enum _MsgSender { bot, user }

class _ChatMsg {
  final String text;
  final _MsgSender sender;
  const _ChatMsg(this.text, this.sender);
}

// ─────────────────────────────────────────────
//  Main Screen
// ─────────────────────────────────────────────
class GeneralBookingScreen extends StatefulWidget {
  final String userId;
  const GeneralBookingScreen({super.key, required this.userId});

  @override
  State<GeneralBookingScreen> createState() => _GeneralBookingScreenState();
}

class _GeneralBookingScreenState extends State<GeneralBookingScreen>
    with TickerProviderStateMixin {

  // ── Config ───────────────────────────────────────────────────────────────
  final double _defaultHourlyRate = 400.0;
  final int _minNotesLength       = 20;
  final int _baseTA               = 38;

  // ── Wizard state ─────────────────────────────────────────────────────────
  int _currentStep = 0; // 0=Job, 1=Schedule, 2=Location, 3=Rate, 4=Review
  final List<_ChatMsg> _messages = [
    const _ChatMsg('Hey! 👋 What kind of job do you need help with today?', _MsgSender.bot),
  ];
  bool _botTyping = false;

  // ── Step 0 – Job ──────────────────────────────────────────────────────────
  final _notesController = TextEditingController();

  // ── Step 1 – Schedule ─────────────────────────────────────────────────────
  DateTime _selectedDate     = DateTime.now();
  int?     _selectedStartHour;
  int      _hours            = 2;
  final Set<int> _availableSlots = List.generate(24, (i) => i).toSet();

  // ── Step 2 – Location ─────────────────────────────────────────────────────
  final _addressController  = TextEditingController();
  final _landmarkController = TextEditingController();
  final _doorController     = TextEditingController();
  final _streetController   = TextEditingController();
  final _pinController      = TextEditingController();
  String? _selectedLocality;
  List<String> _localities = [];
  bool _isFetchingLocalities = false;
  Position? _currentPosition;
  String?   _nominatimAddress;
  bool      _isGettingLocation = false;

  // ── Step 3 – Rate ─────────────────────────────────────────────────────────
  final _rateController = TextEditingController();
  int _selectedRatePreset = 1; // 0=budget,1=standard,2=premium

  // ── Submission ────────────────────────────────────────────────────────────
  bool _isLoading = false;
  Map<String, dynamic>? _userData;
  Map<String, dynamic>? _selectedJob;

  // ── Animation ─────────────────────────────────────────────────────────────
  late final ScrollController _chatScrollController = ScrollController();

  // ── Step labels & progress ────────────────────────────────────────────────
  static const _stepLabels = ['Job', 'Schedule', 'Location', 'Rate', 'Review'];

  @override
  void initState() {
    super.initState();
    _rateController.text = _defaultHourlyRate.toStringAsFixed(0);
    _fetchUserData();
  }

  @override
  void dispose() {
    _notesController.dispose();
    _addressController.dispose();
    _landmarkController.dispose();
    _doorController.dispose();
    _streetController.dispose();
    _pinController.dispose();
    _rateController.dispose();
    _chatScrollController.dispose();
    super.dispose();
  }

  // ── Data fetching ─────────────────────────────────────────────────────────

  Future<void> _fetchUserData() async {
    if (widget.userId.isEmpty) return;
    try {
      final doc = await FirebaseFirestore.instance
          .collection('users')
          .doc(widget.userId)
          .get();
      if (doc.exists) {
        setState(() {
          _userData = doc.data();
          if (_addressController.text.isEmpty) {
            _addressController.text =
                _userData?['locality'] ?? _userData?['address'] ?? '';
          }
        });
      }
    } catch (e) {
      debugPrint('Error fetching user: $e');
    }
  }

  // ── Chat helpers ──────────────────────────────────────────────────────────

  void _addUserMsg(String text) {
    setState(() => _messages.add(_ChatMsg(text, _MsgSender.user)));
    _scrollChat();
  }

  Future<void> _addBotMsg(String text) async {
    setState(() => _botTyping = true);
    _scrollChat();
    await Future.delayed(const Duration(milliseconds: 700));
    if (!mounted) return;
    setState(() {
      _botTyping = false;
      _messages.add(_ChatMsg(text, _MsgSender.bot));
    });
    _scrollChat();
  }

  void _scrollChat() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_chatScrollController.hasClients) {
        _chatScrollController.animateTo(
          _chatScrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  // ── Step navigation ───────────────────────────────────────────────────────

  Future<void> _advanceStep() async {
    switch (_currentStep) {
      case 0:
        if (_notesController.text.trim().length < _minNotesLength) {
          _showError('Please describe your job in more detail (min $_minNotesLength characters).');
          return;
        }
        _addUserMsg(_notesController.text.trim());
        // Predict job category from notes
        try {
          final response = await ApiClient.post('/cw/predict', {'text': _notesController.text.trim()});
          if (response['category'] != null) {
            _selectedJob = {
              'label': response['category'],
              'emoji': '🔧', // Default emoji, can be customized per category
            };
          } else {
            _selectedJob = {
              'label': 'General Service',
              'emoji': '🔧',
            };
          }
        } catch (e) {
          debugPrint('Error predicting job: $e');
          _selectedJob = {
            'label': 'General Service',
            'emoji': '🔧',
          };
        }
        await _addBotMsg('Great choice! When do you need this done, and for how long?');
        break;
      case 1:
        if (_selectedStartHour == null) { _showError('Please select a start time.'); return; }
        final dateStr = DateFormat('EEE, MMM d').format(_selectedDate);
        final timeStr = _formatTime(_selectedStartHour!);
        _addUserMsg('$dateStr · $timeStr · ${_hours}h');
        await _addBotMsg('Got it! Where should the worker come to?');
        break;
      case 2:
        if (_doorController.text.trim().isEmpty ||
            _streetController.text.trim().isEmpty ||
            _pinController.text.trim().isEmpty ||
            _selectedLocality == null) {
          _showError('Please fill in all address fields.');
          return;
        }
        final addressSummary = '${_doorController.text.trim()}, ${_streetController.text.trim()}, $_selectedLocality, ${_pinController.text.trim()}';
        _addUserMsg(addressSummary);
        await _addBotMsg('Almost there! Set your hourly rate and I\'ll find the best matches for you.');
        break;
      case 3:
        final r = double.tryParse(_rateController.text) ?? _defaultHourlyRate;
        _addUserMsg('₹${r.toStringAsFixed(0)}/hr · Total ₹${(r * _hours).toStringAsFixed(0)}');
        await _addBotMsg('Here\'s your full request. Ready to send it to the top workers? 🚀');
        break;
      case 4:
        await _confirmBooking();
        return;
    }
    setState(() => _currentStep++);
  }

  void _goBack() {
    if (_currentStep > 0) setState(() => _currentStep--);
  }

  // ── Slot helpers ──────────────────────────────────────────────────────────

  List<int> _getAvailableStartSlots() {
    final slots = <int>[];
    final now   = DateTime.now();
    final minBookingTime = now.add(const Duration(hours: 1));
    for (int hour = 0; hour < 24; hour++) {
      if (hour + _hours > 24) continue;
      bool ok = true;
      for (int i = 0; i < _hours; i++) {
        if (!_availableSlots.contains(hour + i)) { ok = false; break; }
      }
      if (!ok) continue;
      final slotDt = DateTime(_selectedDate.year, _selectedDate.month, _selectedDate.day, hour);
      if (DateUtils.isSameDay(_selectedDate, now) && slotDt.isBefore(minBookingTime)) continue;
      slots.add(hour);
    }
    return slots;
  }

  String _formatTime(int hour) {
    if (hour == 0 || hour == 24) return '12 AM';
    final dt = DateTime(DateTime.now().year, 1, 1, hour % 24);
    return DateFormat.j().format(dt);
  }

  // ── GPS ───────────────────────────────────────────────────────────────────

  Future<void> _fetchLocalities(String pin) async {
    if (pin.length != 6) return;
    setState(() => _isFetchingLocalities = true);
    try {
      final url = Uri.parse('https://api.postalpincode.in/pincode/$pin');
      final res = await http.get(url);
      if (res.statusCode == 200) {
        final data = json.decode(res.body);
        if (data[0]['Status'] == 'Success') {
          final posts = data[0]['PostOffice'] as List;
          setState(() {
            _localities = posts.map((p) => p['Name'] as String).toList();
            _selectedLocality = null;
          });
        } else {
          setState(() => _localities = []);
        }
      }
    } catch (e) {
      debugPrint('Error fetching localities: $e');
      setState(() => _localities = []);
    } finally {
      setState(() => _isFetchingLocalities = false);
    }
  }

  Future<void> _getCurrentLocation() async {
    setState(() => _isGettingLocation = true);
    try {
      if (!await Geolocator.isLocationServiceEnabled()) {
        throw Exception('Location services are disabled. Please enable GPS.');
      }
      LocationPermission perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied) {
        perm = await Geolocator.requestPermission();
        if (perm == LocationPermission.denied) throw Exception('Location permissions are denied');
      }
      final position = await Geolocator.getCurrentPosition(desiredAccuracy: LocationAccuracy.high);
      setState(() => _currentPosition = position);
      try {
        final url = Uri.parse(
            'https://nominatim.openstreetmap.org/reverse?format=json&lat=${position.latitude}&lon=${position.longitude}&addressdetails=1');
        final res = await http.get(url, headers: {'User-Agent': 'FlutterWorkerApp/1.0'});
        if (res.statusCode == 200) {
          final data = json.decode(res.body);
          setState(() {
            _nominatimAddress = data['display_name'];
            final postcode = data['address']['postcode'];
            if (postcode != null) {
              _pinController.text = postcode;
              _fetchLocalities(postcode);
            }
          });
        }
      } catch (_) {}
      if (mounted) _showSuccess('Location fetched successfully!');
    } catch (e) {
      if (mounted) _showError('$e');
    } finally {
      if (mounted) setState(() => _isGettingLocation = false);
    }
  }

  // ── Booking submission ────────────────────────────────────────────────────

  Future<void> _confirmBooking() async {
    final currentUser = FirebaseAuth.instance.currentUser;
    if (currentUser == null) { _showError('Please login to submit a job request.'); return; }
    setState(() => _isLoading = true);
    try {
      if (_userData == null && widget.userId.isNotEmpty) {
        final doc = await FirebaseFirestore.instance.collection('users').doc(widget.userId).get();
        if (doc.exists) _userData = doc.data();
      }
      final userName   = _userData?['name']  ?? 'Anonymous User';
      final userPhone  = _userData?['phone'] ?? '';
      final rate       = double.tryParse(_rateController.text) ?? _defaultHourlyRate;
      final wage       = (rate * _hours).toInt();
      final payload = {
        'userId': currentUser.uid,
        'userPhone': userPhone,
        'userName': userName,
        'candidateWorkers': [],
        'userInfo': {'name': userName, 'phone': userPhone, 'email': _userData?['email'] ?? ''},
        'date': DateFormat('yyyy-MM-dd').format(_selectedDate),
        'startHour': _selectedStartHour!,
        'endHour': _selectedStartHour! + _hours,
        'wage': wage,
        'ta': _baseTA,
        'serviceType': _notesController.text.trim(),
        'serviceCategory': _selectedJob?['label'] ?? 'AI Booking',
        'location': {
          'locality': _selectedLocality,
          'pin': _pinController.text.trim(),
          'address': '${_doorController.text.trim()}, ${_streetController.text.trim()}',
          'db_address': _nominatimAddress ?? '${_doorController.text.trim()}, ${_streetController.text.trim()}, $_selectedLocality, ${_pinController.text.trim()}',
          'landmark': _landmarkController.text.trim(),
          'lat': _currentPosition?.latitude,
          'lng': _currentPosition?.longitude,
          'source': _currentPosition != null ? 'gps' : 'manual',
        },
        'notes': _notesController.text.trim(),
      };
      final response = await ApiClient.post('/create-booking', payload);
      if (response['ok'] == true) {
        if (!mounted) return;
        final matched = response['matched'] ?? 0;
        if (matched > 0) {
          _showSuccess('Request sent to top $matched matches!');
        } else {
          _showSuccess('No active workers found at this time. Next available in 2 hours with 5 workers.');
        }
        Navigator.of(context).pop();
      } else {
        throw Exception(response['error'] ?? 'Failed');
      }
    } catch (e) {
      if (mounted) _showError('Error: $e');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  // ── Snackbars ─────────────────────────────────────────────────────────────

  void _showError(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Row(children: [
        const Icon(Icons.error_outline, color: Colors.white, size: 18),
        const SizedBox(width: 8),
        Expanded(child: Text(msg)),
      ]),
      backgroundColor: AppDesignTokens.danger,
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    ));
  }

  void _showSuccess(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Row(children: [
        const Icon(Icons.check_circle_outline, color: Colors.white, size: 18),
        const SizedBox(width: 8),
        Text(msg),
      ]),
      backgroundColor: AppDesignTokens.success,
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    ));
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppDesignTokens.surface,
      appBar: _buildAppBar(),
      body: Column(
        children: [
          _ProgressBar(step: _currentStep, labels: _stepLabels),
          Expanded(
            child: ListView(
              controller: _chatScrollController,
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
              children: [
                ..._messages.map((m) => _ChatBubble(msg: m)),
                if (_botTyping) const _TypingBubble(),
                const SizedBox(height: 12),
                _buildStepPanel(),
                const SizedBox(height: 24),
                // Footer
                const AppFooter(),
              ],
            ),
          ),
        ],
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
        icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 20, color: AppDesignTokens.primary),
        onPressed: () => Navigator.pop(context),
      ),
      title: FittedBox(
        child: Row(children: [
          const Text('Kaarya', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 14, color: Color(0xFF1565C0), letterSpacing: -0.3)),
          const Text('Orchestrated AI',    style: TextStyle(fontWeight: FontWeight.w900, fontSize: 14, color: AppDesignTokens.primary,          letterSpacing: -0.3)),
          const SizedBox(width: 6),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: const Color(0xFF1E88E5).withOpacity(0.12),
              borderRadius: BorderRadius.circular(5),
            ),
            child: const Text('BETA', style: TextStyle(fontSize: 8, fontWeight: FontWeight.w800, color: Color(0xFF1565C0), letterSpacing: 1)),
          ),
        ]),
      ),
      actions: [
        Padding(
          padding: const EdgeInsets.only(right: 14),
          child: Icon(Icons.smart_toy_rounded, color: AppDesignTokens.aiBlue, size: 20),
        ),
      ],
    );
  }

  // ── Step panels ───────────────────────────────────────────────────────────

  Widget _buildStepPanel() {
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 280),
      transitionBuilder: (child, anim) => FadeTransition(
        opacity: anim,
        child: SlideTransition(
          position: Tween<Offset>(begin: const Offset(0, 0.06), end: Offset.zero).animate(anim),
          child: child,
        ),
      ),
      child: KeyedSubtree(
        key: ValueKey(_currentStep),
        child: switch (_currentStep) {
          0 => _buildStep0(),
          1 => _buildStep1(),
          2 => _buildStep2(),
          3 => _buildStep3(),
          4 => _buildStep4(),
          _ => const SizedBox.shrink(),
        },
      ),
    );
  }

  // ── Step 0 : Job type + description ──────────────────────────────────────

  Widget _buildStep0() {
    return _StepCard(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const SizedBox(height: 20),
        const _StepLabel('Describe the job'),
        const SizedBox(height: 8),
        TextField(
          controller: _notesController,
          decoration: AppDesignTokens.fieldDecoration(
            label: 'More details (min $_minNotesLength chars)',
            hint: 'e.g. My kitchen tap is leaking and needs a new washer...',
          ),
          maxLines: 3,
          onChanged: (_) => setState(() {}),
        ),
        const SizedBox(height: 6),
        Align(
          alignment: Alignment.centerRight,
          child: Text(
            '${_notesController.text.trim().length} / $_minNotesLength min',
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w500,
              color: _notesController.text.trim().length >= _minNotesLength
                  ? AppDesignTokens.success
                  : Colors.grey[500],
            ),
          ),
        ),
        const SizedBox(height: 16),
        _NextButton(onTap: _advanceStep),
      ]),
    );
  }

  // ── Step 1 : Date + Duration + Slot ──────────────────────────────────────

  Widget _buildStep1() {
    final availableSlots = _getAvailableStartSlots();
    return _StepCard(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const _StepLabel('Pick a date'),
        const SizedBox(height: 10),
        _DateStrip(
          selectedDate: _selectedDate,
          onDateSelected: (d) => setState(() {
            _selectedDate = d;
            _selectedStartHour = null;
          }),
        ),
        const SizedBox(height: 18),
        const _StepLabel('Duration'),
        const SizedBox(height: 10),
        _DurationStepper(
          hours: _hours,
          onChanged: (h) => setState(() {
            _hours = h;
            _selectedStartHour = null;
          }),
        ),
        const SizedBox(height: 18),
        const _StepLabel('Start time'),
        const SizedBox(height: 10),
        if (availableSlots.isEmpty)
          _InfoChip(
            message: 'No slots available for this date. Try another date or reduce duration.',
            icon: Icons.info_outline_rounded,
            color: AppDesignTokens.aiBlue,
          )
        else
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: availableSlots.map((h) {
              final sel = _selectedStartHour == h;
              return _TimeSlotChip(
                label: _formatTime(h),
                selected: sel,
                onTap: () => setState(() => _selectedStartHour = sel ? null : h),
              );
            }).toList(),
          ),
        if (_selectedStartHour != null) ...[
          const SizedBox(height: 12),
          _TimeSummaryPill(
            start: _formatTime(_selectedStartHour!),
            end: _formatTime(_selectedStartHour! + _hours),
            hours: _hours,
          ),
        ],
        const SizedBox(height: 16),
        _NavRow(onBack: _goBack, onNext: _advanceStep),
      ]),
    );
  }

  // ── Step 2 : Location ─────────────────────────────────────────────────────

  Widget _buildStep2() {
    return _StepCard(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const _StepLabel('Where do you need help?'),
        const SizedBox(height: 10),
        TextField(
          controller: _doorController,
          decoration: AppDesignTokens.fieldDecoration(
            label: 'Door No / House No',
            hint: 'e.g. 123A',
            prefix: const Icon(Icons.home_rounded, size: 18),
          ),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _streetController,
          decoration: AppDesignTokens.fieldDecoration(
            label: 'Street / Apartment',
            hint: 'e.g. MG Road, Sunshine Apartments',
            prefix: const Icon(Icons.location_city_rounded, size: 18),
          ),
        ),
        const SizedBox(height: 12),
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Expanded(
            child: TextField(
              controller: _pinController,
              keyboardType: TextInputType.number,
              maxLength: 6,
              decoration: AppDesignTokens.fieldDecoration(
                label: 'PIN Code',
                hint: 'e.g. 110001',
                prefix: const Icon(Icons.pin_drop_rounded, size: 18),
              ),
              onChanged: (value) => _fetchLocalities(value),
            ),
          ),
          const SizedBox(width: 10),
          Column(children: [
            const SizedBox(height: 4),
            Container(
              decoration: BoxDecoration(
                color: AppDesignTokens.aiBlue.withOpacity(0.08),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: AppDesignTokens.aiBlue.withOpacity(0.25)),
              ),
              child: IconButton(
                onPressed: _isGettingLocation ? null : _getCurrentLocation,
                icon: _isGettingLocation
                    ? const SizedBox(
                        width: 20, height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2, color: AppDesignTokens.aiBlue))
                    : const Icon(Icons.my_location_rounded, color: AppDesignTokens.aiBlue, size: 22),
                tooltip: 'Fetch PIN from GPS',
              ),
            ),
            const SizedBox(height: 4),
            Text('GPS', style: TextStyle(fontSize: 10, color: Colors.grey[600], fontWeight: FontWeight.w500)),
          ]),
        ]),
        const SizedBox(height: 12),
        if (_isFetchingLocalities)
          const Center(child: CircularProgressIndicator())
        else if (_localities.isNotEmpty)
          DropdownButtonFormField<String>(
            value: _selectedLocality,
            decoration: AppDesignTokens.fieldDecoration(
              label: 'Locality',
              prefix: const Icon(Icons.location_on_rounded, size: 18),
            ),
            items: _localities.map((loc) => DropdownMenuItem(value: loc, child: Text(loc))).toList(),
            onChanged: (value) => setState(() => _selectedLocality = value),
          )
        else if (_pinController.text.length == 6)
          const _InfoChip(
            message: 'No localities found for this PIN code.',
            icon: Icons.info_outline_rounded,
            color: AppDesignTokens.danger,
          ),
        if (_currentPosition != null) ...[
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: AppDesignTokens.success.withOpacity(0.08),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: AppDesignTokens.success.withOpacity(0.25)),
            ),
            child: Row(children: [
              const Icon(Icons.gps_fixed_rounded, color: AppDesignTokens.success, size: 16),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  '${_currentPosition!.latitude.toStringAsFixed(5)}, ${_currentPosition!.longitude.toStringAsFixed(5)}',
                  style: const TextStyle(fontSize: 12, color: AppDesignTokens.success, fontWeight: FontWeight.w600),
                ),
              ),
            ]),
          ),
        ],
        const SizedBox(height: 12),
        TextField(
          controller: _landmarkController,
          decoration: AppDesignTokens.fieldDecoration(
            label: 'Landmark (optional)',
            hint: 'Near SBI Bank...',
            prefix: const Icon(Icons.flag_rounded, size: 18),
          ),
        ),
        const SizedBox(height: 16),
        _NavRow(onBack: _goBack, onNext: _advanceStep),
      ]),
    );
  }

  // ── Step 3 : Rate ─────────────────────────────────────────────────────────

  Widget _buildStep3() {
    final rate = double.tryParse(_rateController.text) ?? _defaultHourlyRate;
    final total = (rate * _hours).toInt();
    final presets = [
      ('₹350', 'Budget',   350.0),
      ('₹400', 'Standard', 400.0),
      ('₹500', 'Premium',  500.0),
    ];
    return _StepCard(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const _StepLabel('Set your hourly rate'),
        const SizedBox(height: 4),
        Text('Suggested: ₹350 – ₹500/hr for this job type',
            style: TextStyle(fontSize: 12, color: Colors.grey[500])),
        const SizedBox(height: 12),
        Row(children: List.generate(presets.length, (i) {
          final (label, sub, val) = presets[i];
          final sel = _selectedRatePreset == i;
          return Expanded(
            child: GestureDetector(
              onTap: () => setState(() {
                _selectedRatePreset = i;
                _rateController.text = val.toStringAsFixed(0);
              }),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 160),
                margin: EdgeInsets.only(right: i < 2 ? 8 : 0),
                padding: const EdgeInsets.symmetric(vertical: 12),
                decoration: BoxDecoration(
                  color: sel ? AppDesignTokens.tileSelected : Colors.white,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: sel ? AppDesignTokens.primary : Colors.grey.shade200,
                    width: sel ? 1.5 : 1,
                  ),
                ),
                child: Column(children: [
                  Text(label, style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: sel ? AppDesignTokens.primary : AppDesignTokens.text1)),
                  const SizedBox(height: 2),
                  Text(sub, style: TextStyle(fontSize: 10, color: sel ? AppDesignTokens.accent : Colors.grey[500])),
                ]),
              ),
            ),
          );
        })),
        const SizedBox(height: 14),
        Row(children: [
          Expanded(
            child: TextFormField(
              controller: _rateController,
              keyboardType: TextInputType.number,
              decoration: AppDesignTokens.fieldDecoration(
                label: 'Custom rate (₹/hr)',
                prefix: const Icon(Icons.currency_rupee_rounded, size: 18, color: AppDesignTokens.success),
              ),
              onChanged: (_) => setState(() => _selectedRatePreset = -1),
            ),
          ),
          const SizedBox(width: 12),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            decoration: BoxDecoration(
              color: AppDesignTokens.success.withOpacity(0.08),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: AppDesignTokens.success.withOpacity(0.25)),
            ),
            child: Column(children: [
              Text('Total', style: TextStyle(fontSize: 10, color: Colors.grey[600], letterSpacing: .4)),
              const SizedBox(height: 2),
              Text('₹$total',
                  style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: AppDesignTokens.success, letterSpacing: -0.5)),
            ]),
          ),
        ]),
        const SizedBox(height: 8),
        Text('+ ₹$_baseTA travel allowance included',
            style: TextStyle(fontSize: 11, color: Colors.grey[500])),
        const SizedBox(height: 16),
        _NavRow(onBack: _goBack, onNext: _advanceStep, nextLabel: 'Review →'),
      ]),
    );
  }

  // ── Step 4 : Review & submit ──────────────────────────────────────────────

  Widget _buildStep4() {
    final rate  = double.tryParse(_rateController.text) ?? _defaultHourlyRate;
    final total = (rate * _hours).toInt() + _baseTA;
    return _StepCard(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const _StepLabel('Review your request'),
        const SizedBox(height: 12),
        _ReviewSummary(
          job:   '${_selectedJob?['emoji'] ?? ''} ${_selectedJob?['label'] ?? ''}',
          date:  DateFormat('EEE, MMM d, yyyy').format(_selectedDate),
          time:  _selectedStartHour != null
                 ? '${_formatTime(_selectedStartHour!)} – ${_formatTime(_selectedStartHour! + _hours)}'
                 : '—',
          hours: '${_hours}h',
          address: '${_doorController.text.trim()}, ${_streetController.text.trim()}, ${_selectedLocality ?? ''}, ${_pinController.text.trim()}',
          rate:   '₹${rate.toStringAsFixed(0)}/hr',
          ta:     '₹$_baseTA',
          total:  '₹$total',
        ),
        const SizedBox(height: 20),
        SizedBox(
          width: double.infinity,
          child: ElevatedButton(
            onPressed: _isLoading ? null : _advanceStep,
            style: ElevatedButton.styleFrom(
              backgroundColor: AppDesignTokens.primary,
              foregroundColor: Colors.white,
              disabledBackgroundColor: Colors.grey[200],
              padding: const EdgeInsets.symmetric(vertical: 16),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              elevation: 0,
            ),
            child: _isLoading
                ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2.5))
                : const Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                    Icon(Icons.auto_awesome_rounded, size: 18),
                    SizedBox(width: 8),
                    Text('Send to Top Matches', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
                  ]),
          ),
        ),
        const SizedBox(height: 10),
        TextButton(
          onPressed: _goBack,
          child: const Center(child: Text('← Edit request', style: TextStyle(color: AppDesignTokens.primary, fontWeight: FontWeight.w600))),
        ),
      ]),
    );
  }
}

// ─────────────────────────────────────────────
//  Progress bar widget
// ─────────────────────────────────────────────
class _ProgressBar extends StatelessWidget {
  final int step;
  final List<String> labels;
  const _ProgressBar({required this.step, required this.labels});

  @override
  Widget build(BuildContext context) {
    final pct = ((step + 1) / labels.length).clamp(0.0, 1.0);
    return Container(
      color: Colors.white,
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
      child: Column(children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: List.generate(labels.length, (i) {
            final active = i == step;
            final done   = i < step;
            return Row(children: [
              Text(
                labels[i],
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: active ? FontWeight.w700 : FontWeight.w400,
                  color: active ? AppDesignTokens.primary : done ? AppDesignTokens.accent : Colors.grey[400],
                ),
              ),
              if (done) ...[
                const SizedBox(width: 2),
                const Icon(Icons.check_circle_rounded, size: 10, color: AppDesignTokens.success),
              ],
            ]);
          }),
        ),
        const SizedBox(height: 6),
        ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: LinearProgressIndicator(
            value: pct,
            minHeight: 5,
            backgroundColor: Colors.grey[200],
            valueColor: const AlwaysStoppedAnimation<Color>(AppDesignTokens.primary),
          ),
        ),
        const SizedBox(height: 4),
        Align(
          alignment: Alignment.centerRight,
          child: Text(
            '${(pct * 100).round()}% complete',
            style: const TextStyle(fontSize: 10, color: AppDesignTokens.primary, fontWeight: FontWeight.w600),
          ),
        ),
      ]),
    );
  }
}

// ─────────────────────────────────────────────
//  Chat bubble
// ─────────────────────────────────────────────
class _ChatBubble extends StatelessWidget {
  final _ChatMsg msg;
  const _ChatBubble({required this.msg});

  @override
  Widget build(BuildContext context) {
    final isBot = msg.sender == _MsgSender.bot;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        mainAxisAlignment: isBot ? MainAxisAlignment.start : MainAxisAlignment.end,
        children: [
          if (isBot) ...[
            _BotAvatar(),
            const SizedBox(width: 8),
          ],
          Flexible(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: isBot ? Colors.white : AppDesignTokens.primary,
                borderRadius: BorderRadius.only(
                  topLeft:     const Radius.circular(16),
                  topRight:    const Radius.circular(16),
                  bottomLeft:  Radius.circular(isBot ? 4 : 16),
                  bottomRight: Radius.circular(isBot ? 16 : 4),
                ),
                border: isBot ? Border.all(color: Colors.grey.shade200) : null,
                boxShadow: [
                  BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 8, offset: const Offset(0, 2))
                ],
              ),
              child: Text(
                msg.text,
                style: TextStyle(
                  fontSize: 14,
                  height: 1.45,
                  color: isBot ? AppDesignTokens.text1 : Colors.white,
                ),
              ),
            ),
          ),
          if (!isBot) ...[
            const SizedBox(width: 8),
            _UserAvatar(),
          ],
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────
//  Typing indicator
// ─────────────────────────────────────────────
class _TypingBubble extends StatefulWidget {
  const _TypingBubble();
  @override
  State<_TypingBubble> createState() => _TypingBubbleState();
}

class _TypingBubbleState extends State<_TypingBubble> with TickerProviderStateMixin {
  late final List<AnimationController> _controllers;
  late final List<Animation<double>> _anims;

  @override
  void initState() {
    super.initState();
    _controllers = List.generate(3, (i) => AnimationController(
      vsync: this, duration: const Duration(milliseconds: 500))
      ..repeat(reverse: true, period: Duration(milliseconds: 600 + i * 150)));
    _anims = _controllers.map((c) => Tween<double>(begin: 0, end: -5).animate(
      CurvedAnimation(parent: c, curve: Curves.easeInOut))).toList();
  }

  @override
  void dispose() {
    for (final c in _controllers) {
      c.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
        _BotAvatar(),
        const SizedBox(width: 8),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: const BorderRadius.only(
              topLeft: Radius.circular(16), topRight: Radius.circular(16),
              bottomLeft: Radius.circular(4), bottomRight: Radius.circular(16),
            ),
            border: Border.all(color: Colors.grey.shade200),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: List.generate(3, (i) => AnimatedBuilder(
              animation: _anims[i],
              builder: (_, __) => Transform.translate(
                offset: Offset(0, _anims[i].value),
                child: Container(
                  width: 7, height: 7,
                  margin: EdgeInsets.only(right: i < 2 ? 4 : 0),
                  decoration: BoxDecoration(color: AppDesignTokens.text2.withOpacity(0.5), shape: BoxShape.circle),
                ),
              ),
            )),
          ),
        ),
      ]),
    );
  }
}

// ─────────────────────────────────────────────
//  Avatars
// ─────────────────────────────────────────────
class _BotAvatar extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      width: 28, height: 28,
      decoration: BoxDecoration(
        gradient: const LinearGradient(colors: [Color(0xFFE6F1FB), Color(0xFFE1F5EE)]),
        shape: BoxShape.circle,
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: const Icon(Icons.auto_awesome_rounded, size: 13, color: AppDesignTokens.aiBlue),
    );
  }
}

class _UserAvatar extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      width: 28, height: 28,
      decoration: BoxDecoration(
        color: AppDesignTokens.tileSelected,
        shape: BoxShape.circle,
        border: Border.all(color: AppDesignTokens.accent.withOpacity(0.3)),
      ),
      child: const Icon(Icons.person_rounded, size: 15, color: AppDesignTokens.primary),
    );
  }
}

// ─────────────────────────────────────────────
//  Step card wrapper
// ─────────────────────────────────────────────
class _StepCard extends StatelessWidget {
  final Widget child;
  const _StepCard({required this.child});
  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: AppDesignTokens.cardDecoration(),
      padding: AppDesignTokens.cardPad,
      child: child,
    );
  }
}

class _StepLabel extends StatelessWidget {
  final String text;
  const _StepLabel(this.text);
  @override
  Widget build(BuildContext context) {
    return Text(text, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: AppDesignTokens.text2, letterSpacing: .3));
  }
}



// ─────────────────────────────────────────────
//  Date strip
// ─────────────────────────────────────────────
class _DateStrip extends StatelessWidget {
  final DateTime selectedDate;
  final ValueChanged<DateTime> onDateSelected;
  const _DateStrip({required this.selectedDate, required this.onDateSelected});

  @override
  Widget build(BuildContext context) {
    final today = DateTime.now();
    return SizedBox(
      height: 68,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        itemCount: 14,
        itemBuilder: (_, i) {
          final d   = today.add(Duration(days: i));
          final sel = DateUtils.isSameDay(d, selectedDate);
          return GestureDetector(
            onTap: () => onDateSelected(d),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 160),
              width: 52,
              margin: EdgeInsets.only(right: i < 13 ? 8 : 0),
              decoration: BoxDecoration(
                color: sel ? AppDesignTokens.primary : Colors.white,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: sel ? AppDesignTokens.primary : Colors.grey.shade200, width: sel ? 1.5 : 1),
              ),
              child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                Text(
                  DateFormat('EEE').format(d).toUpperCase(),
                  style: TextStyle(fontSize: 9, fontWeight: FontWeight.w700, color: sel ? Colors.white70 : Colors.grey[500]),
                ),
                const SizedBox(height: 2),
                Text(
                  '${d.day}',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: sel ? Colors.white : AppDesignTokens.text1),
                ),
                Text(
                  DateFormat('MMM').format(d),
                  style: TextStyle(fontSize: 9, color: sel ? Colors.white70 : Colors.grey[500]),
                ),
              ]),
            ),
          );
        },
      ),
    );
  }
}

// ─────────────────────────────────────────────
//  Duration stepper
// ─────────────────────────────────────────────
class _DurationStepper extends StatelessWidget {
  final int hours;
  final ValueChanged<int> onChanged;
  const _DurationStepper({required this.hours, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: const Color(0xFFF4F8F8),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Row(children: [
        const Icon(Icons.timelapse_rounded, color: AppDesignTokens.primary, size: 20),
        const SizedBox(width: 10),
        const Text('Duration', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: AppDesignTokens.text2)),
        const Spacer(),
        _StepperBtn(icon: Icons.remove_rounded, enabled: hours > 1, onTap: () => onChanged(hours - 1)),
        SizedBox(width: 48, child: Center(child: Text('${hours}h', style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800, color: AppDesignTokens.text1)))),
        _StepperBtn(icon: Icons.add_rounded, enabled: true, onTap: () => onChanged(hours + 1)),
      ]),
    );
  }
}

class _StepperBtn extends StatelessWidget {
  final IconData icon;
  final bool enabled;
  final VoidCallback onTap;
  const _StepperBtn({required this.icon, required this.enabled, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: enabled ? onTap : null,
      child: Container(
        width: 36, height: 36,
        decoration: BoxDecoration(
          color: enabled ? AppDesignTokens.primary.withOpacity(0.1) : Colors.grey.withOpacity(0.08),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: enabled ? AppDesignTokens.primary.withOpacity(0.25) : Colors.grey.shade200),
        ),
        child: Icon(icon, size: 18, color: enabled ? AppDesignTokens.primary : Colors.grey[400]),
      ),
    );
  }
}

// ─────────────────────────────────────────────
//  Time slot chip
// ─────────────────────────────────────────────
class _TimeSlotChip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;
  const _TimeSlotChip({required this.label, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
        decoration: BoxDecoration(
          color: selected ? AppDesignTokens.primary : const Color(0xFFF4F8F8),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: selected ? AppDesignTokens.primary : Colors.grey.shade200, width: selected ? 1.5 : 1),
        ),
        child: Text(label, style: TextStyle(fontSize: 13, fontWeight: selected ? FontWeight.w700 : FontWeight.w500, color: selected ? Colors.white : AppDesignTokens.text2)),
      ),
    );
  }
}

// ─────────────────────────────────────────────
//  Time summary pill
// ─────────────────────────────────────────────
class _TimeSummaryPill extends StatelessWidget {
  final String start, end;
  final int hours;
  const _TimeSummaryPill({required this.start, required this.end, required this.hours});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: AppDesignTokens.primary.withOpacity(0.07),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppDesignTokens.primary.withOpacity(0.22)),
      ),
      child: Row(children: [
        const Icon(Icons.schedule_rounded, color: AppDesignTokens.primary, size: 16),
        const SizedBox(width: 8),
        Text('$start – $end', style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: AppDesignTokens.primary)),
        const SizedBox(width: 8),
        Text('(${hours}h)', style: TextStyle(fontSize: 13, color: Colors.grey[500])),
      ]),
    );
  }
}

// ─────────────────────────────────────────────
//  Review summary card
// ─────────────────────────────────────────────
class _ReviewSummary extends StatelessWidget {
  final String job, date, time, hours, address, rate, ta, total;
  const _ReviewSummary({
    required this.job, required this.date, required this.time,
    required this.hours, required this.address, required this.rate,
    required this.ta, required this.total,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppDesignTokens.primary.withOpacity(0.04),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppDesignTokens.primary.withOpacity(0.18)),
      ),
      child: Column(children: [
        _SummaryRow('Job',      job),
        _SummaryRow('Date',     date),
        _SummaryRow('Time',     time),
        _SummaryRow('Duration', hours),
        _SummaryRow('Location', address, small: true),
        const Padding(
          padding: EdgeInsets.symmetric(vertical: 8),
          child: Divider(height: 1, color: Color(0x1A00897B)),
        ),
        _SummaryRow('Hourly rate',       rate),
        _SummaryRow('Travel allowance',  ta),
        const Padding(
          padding: EdgeInsets.symmetric(vertical: 8),
          child: Divider(height: 1, color: Color(0x1A00897B)),
        ),
        Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          const Text('Total wage', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: AppDesignTokens.primary)),
          Text(total,              style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: AppDesignTokens.primary, letterSpacing: -0.5)),
        ]),
      ]),
    );
  }
}

class _SummaryRow extends StatelessWidget {
  final String label, value;
  final bool small;
  const _SummaryRow(this.label, this.value, {this.small = false});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
        Text(label, style: const TextStyle(fontSize: 13, color: AppDesignTokens.text2)),
        Flexible(
          child: Text(
            value,
            textAlign: TextAlign.right,
            style: TextStyle(fontSize: small ? 12 : 13, fontWeight: FontWeight.w600, color: AppDesignTokens.text1),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ]),
    );
  }
}

// ─────────────────────────────────────────────
//  Navigation row (Back + Next)
// ─────────────────────────────────────────────
class _NavRow extends StatelessWidget {
  final VoidCallback onBack;
  final VoidCallback onNext;
  final String nextLabel;
  const _NavRow({required this.onBack, required this.onNext, this.nextLabel = 'Next →'});

  @override
  Widget build(BuildContext context) {
    return Row(children: [
      Expanded(
        flex: 2,
        child: OutlinedButton(
          onPressed: onBack,
          style: OutlinedButton.styleFrom(
            foregroundColor: AppDesignTokens.text2,
            side: BorderSide(color: Colors.grey.shade300),
            padding: const EdgeInsets.symmetric(vertical: 13),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ),
          child: const Text('← Back', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
        ),
      ),
      const SizedBox(width: 10),
      Expanded(
        flex: 3,
        child: ElevatedButton(
          onPressed: onNext,
          style: ElevatedButton.styleFrom(
            backgroundColor: AppDesignTokens.primary,
            foregroundColor: Colors.white,
            elevation: 0,
            padding: const EdgeInsets.symmetric(vertical: 13),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ),
          child: Text(nextLabel, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700)),
        ),
      ),
    ]);
  }
}

// ─────────────────────────────────────────────
//  Next button (step 0 only)
// ─────────────────────────────────────────────
class _NextButton extends StatelessWidget {
  final VoidCallback onTap;
  const _NextButton({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      child: ElevatedButton(
        onPressed: onTap,
        style: ElevatedButton.styleFrom(
          backgroundColor: AppDesignTokens.primary,
          foregroundColor: Colors.white,
          elevation: 0,
          padding: const EdgeInsets.symmetric(vertical: 14),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        ),
        child: const Text('Next →', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
      ),
    );
  }
}

// ─────────────────────────────────────────────
//  Info chip
// ─────────────────────────────────────────────
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
      decoration: BoxDecoration(
        color: color.withOpacity(0.07),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withOpacity(0.2)),
      ),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Icon(icon, color: color, size: 17),
        const SizedBox(width: 10),
        Expanded(
          child: Text(message, style: TextStyle(color: color.withOpacity(0.9), fontSize: 13, fontWeight: FontWeight.w500, height: 1.45)),
        ),
      ]),
    );
  }
}