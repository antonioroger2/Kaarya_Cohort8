// lib/features/shared/otp_viewer_screen.dart
import 'package:flutter/material.dart';
import 'dart:async';
import '../../core/theme.dart';
import '../../core/api_client.dart';

class OtpViewerScreen extends StatefulWidget {
  final String bookingId;
  final String otpType; // 'start' or 'end'
  final String correlationId;
  final String? otpCode;

  const OtpViewerScreen({
    super.key,
    required this.bookingId,
    required this.otpType,
    required this.correlationId,
    this.otpCode,
  });

  @override
  State<OtpViewerScreen> createState() => _OtpViewerScreenState();
}

class _OtpViewerScreenState extends State<OtpViewerScreen> {
  bool _isLoading = true;
  String? _error;
  Timer? _timer;
  int _remainingSeconds = 600; // 10 minutes
  bool _isExpired = false;
  String? _otpCode;

  @override
  void initState() {
    super.initState();
    _otpCode = widget.otpCode;
    _fetchOtpCode();
    _startTimer();
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  void _startTimer() {
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      setState(() {
        _remainingSeconds--;
        if (_remainingSeconds <= 0) {
          _isExpired = true;
          _timer?.cancel();
        }
      });
    });
  }

  Future<void> _fetchOtpCode() async {
    setState(() {
      _isLoading = false;
      _error = null;
    });

    // Show confirmation when an OTP is already available (first open)
    if (_otpCode != null) {
      _showOtpCreatedAlert(otpCode: _otpCode);
    }
  }

  void _showOtpCreatedAlert({String? otpCode}) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('OTP Created'),
        content: Text(
          otpCode != null
              ? 'OTP: $otpCode\n\nShare this ${widget.otpType == 'start' ? 'start' : 'end'} code with the worker or read it aloud to verify.'
              : 'A ${widget.otpType == 'start' ? 'Start' : 'End'} OTP has been generated and sent to the worker via app notification. Ask the worker to read the 6-digit code aloud for verification.'
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  String _formatTime(int seconds) {
    final minutes = seconds ~/ 60;
    final remainingSeconds = seconds % 60;
    return '${minutes.toString().padLeft(2, '0')}:${remainingSeconds.toString().padLeft(2, '0')}';
  }

  Future<void> _reRequestOtp() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Re-request OTP'),
        content: const Text('Send a fresh OTP via in-app notification? The previous code will be invalidated.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Send OTP'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    // Reset timer
    _timer?.cancel();
    setState(() {
      _remainingSeconds = 600;
      _isExpired = false;
      _isLoading = true;
    });
    _startTimer();

    // Regenerate OTP
    try {
      final response = widget.otpType == 'start'
          ? await ApiClient.generateStartOtp(widget.bookingId)
          : await ApiClient.generateEndOtp(widget.bookingId);

      if (response['ok'] == true) {
        setState(() {
          _error = null;
          _otpCode = response['otp'] as String?;
          _isLoading = false;
        });
        _showOtpCreatedAlert(otpCode: _otpCode);
      }
    } catch (e) {
      setState(() {
        _error = e.toString();
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(
          '${widget.otpType == 'start' ? 'Start' : 'End'} Job OTP',
          style: const TextStyle(
            fontWeight: FontWeight.w900,
            color: Colors.teal,
            fontSize: 18,
          ),
        ),
        backgroundColor: widget.otpType == 'start' ? Colors.blue : Colors.green,
        foregroundColor: Colors.white,
      ),
      body: DoodleBackground(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(24.0),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                // Header
                Icon(
                  widget.otpType == 'start' ? Icons.play_arrow : Icons.stop,
                  size: 80,
                  color: widget.otpType == 'start' ? Colors.blue : Colors.green,
                ),
                const SizedBox(height: 16),
                Text(
                  widget.otpType == 'start' ? 'Job Start Verification' : 'Job End Verification',
                  style: const TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 8),
                Text(
                  'OTP sent to worker. Wait for them to provide the code.',
                  style: TextStyle(
                    fontSize: 16,
                    color: Colors.grey[600],
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 32),

                // Timer
                Container(
                  padding: const EdgeInsets.all(24),
                  decoration: BoxDecoration(
                    color: _isExpired ? Colors.red.withOpacity(0.1) : Colors.white,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color: _isExpired ? Colors.red : (_remainingSeconds < 60 ? Colors.orange : Colors.grey.shade300),
                      width: 2,
                    ),
                  ),
                  child: Column(
                    children: [
                      Text(
                        _isExpired ? 'OTP EXPIRED' : 'Time Remaining',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: _isExpired ? Colors.red : (_remainingSeconds < 60 ? Colors.orange : Colors.black),
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        _formatTime(_remainingSeconds),
                        style: TextStyle(
                          fontSize: 32,
                          fontWeight: FontWeight.bold,
                          color: _isExpired ? Colors.red : (_remainingSeconds < 60 ? Colors.orange : Colors.black),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 32),

                // OTP display if available
                if (!_isLoading && _otpCode != null)
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.black.withOpacity(0.05),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.black12),
                    ),
                    child: Column(
                      children: [
                        Text(
                          'Your ${widget.otpType == 'start' ? 'Start' : 'End'} OTP',
                          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                        ),
                        const SizedBox(height: 8),
                        SelectableText(
                          _otpCode!,
                          style: const TextStyle(fontSize: 32, letterSpacing: 4, fontWeight: FontWeight.w700),
                        ),
                        const SizedBox(height: 6),
                        const Text('Share this code only with the worker on-site.')
                      ],
                    ),
                  ),

                if (!_isLoading && _otpCode == null)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 16),
                    child: Text(
                      'Waiting for OTP. It will appear here and in the worker inbox.',
                      style: TextStyle(color: Colors.grey[700]),
                      textAlign: TextAlign.center,
                    ),
                  ),

                // Status
                if (_isLoading)
                  const CircularProgressIndicator()
                else if (_error != null)
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.red.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.red),
                    ),
                    child: Text(
                      'Error: $_error',
                      style: const TextStyle(color: Colors.red),
                      textAlign: TextAlign.center,
                    ),
                  )
                else
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.green.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.green),
                    ),
                    child: const Column(
                      children: [
                        Icon(Icons.check_circle, color: Colors.green, size: 32),
                        SizedBox(height: 8),
                        Text(
                          'OTP Generated Successfully',
                          style: TextStyle(
                            color: Colors.green,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        SizedBox(height: 4),
                        Text(
                          'OTP sent to worker via app (demo)',
                          style: TextStyle(
                            color: Colors.green,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ),

                const SizedBox(height: 32),

                // Instructions
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.blue.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Column(
                    children: [
                      Text(
                        'Instructions:',
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        widget.otpType == 'start'
                            ? '1. Worker will receive OTP via app notification\n2. Ask worker to read the 6-digit code aloud\n3. Enter the code in the verification screen\n4. Job will start once verified'
                            : '1. Worker will receive OTP via app notification\n2. Ask worker to read the 6-digit code aloud\n3. Enter the code in the verification screen\n4. Job will end once verified',
                        style: const TextStyle(fontSize: 14),
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 32),

                // Re-request button (allowed any time; old code invalidated server-side)
                ElevatedButton.icon(
                  onPressed: _reRequestOtp,
                  icon: const Icon(Icons.refresh),
                  label: const Text('Re-request OTP'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: widget.otpType == 'start' ? Colors.blue : Colors.green,
                    padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
                  ),
                ),

                // Back button
                const SizedBox(height: 16),
                OutlinedButton(
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
                  ),
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('Back to Booking'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}