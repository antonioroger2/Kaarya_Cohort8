// lib/features/shared/otp_viewer_screen.dart
import 'package:flutter/material.dart';
import 'dart:async';
import '../../core/theme.dart';
import '../../core/api_client.dart';

class OtpViewerScreen extends StatefulWidget {
  final String bookingId;
  final String otpType; // 'start' or 'end'
  final String correlationId;

  const OtpViewerScreen({
    super.key,
    required this.bookingId,
    required this.otpType,
    required this.correlationId,
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

  @override
  void initState() {
    super.initState();
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
    setState(() => _isLoading = true);

    try {
      // For demo purposes, we'll simulate getting the OTP code
      // In real implementation, this would come from the backend response
      // For now, we'll show a placeholder
      await Future.delayed(const Duration(seconds: 2)); // Simulate API call

      // In a real implementation, the OTP would be retrieved from the backend
      // For demo, we'll show that the OTP has been sent
      setState(() {
        _isLoading = false;
      });

      // Show alert that OTP has been created
      _showOtpCreatedAlert();

    } catch (e) {
      setState(() {
        _error = e.toString();
        _isLoading = false;
      });
    }
  }

  void _showOtpCreatedAlert() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('OTP Created'),
        content: Text(
          'A ${widget.otpType == 'start' ? 'Start' : 'End'} OTP has been generated and sent to the worker via app notification (demo). '
          'Ask the worker to check their app and read the 6-digit code aloud for verification.'
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

  Future<void> _regenerateOtp() async {
    if (_remainingSeconds > 0) {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Regenerate OTP'),
          content: const Text('Are you sure you want to regenerate the OTP? The previous OTP will become invalid.'),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('Regenerate'),
            ),
          ],
        ),
      );

      if (confirmed != true) return;
    }

    // Reset timer
    _timer?.cancel();
    setState(() {
      _remainingSeconds = 600;
      _isExpired = false;
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
        });
        _showOtpCreatedAlert();
      }
    } catch (e) {
      setState(() {
        _error = e.toString();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('${widget.otpType == 'start' ? 'Start' : 'End'} Job OTP'),
        backgroundColor: widget.otpType == 'start' ? Colors.blue : Colors.green,
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

                // Regenerate button
                if (_isExpired || _error != null)
                  ElevatedButton.icon(
                    onPressed: _regenerateOtp,
                    icon: const Icon(Icons.refresh),
                    label: const Text('Regenerate OTP'),
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