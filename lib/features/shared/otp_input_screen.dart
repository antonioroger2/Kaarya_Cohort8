// lib/features/shared/otp_input_screen.dart
import 'package:flutter/material.dart';
import 'dart:async';
import '../../core/theme.dart';
import '../../core/api_client.dart';

class OtpInputScreen extends StatefulWidget {
  final String bookingId;
  final String otpType; // 'start' or 'end'
  final String correlationId;

  const OtpInputScreen({
    super.key,
    required this.bookingId,
    required this.otpType,
    required this.correlationId,
  });

  @override
  State<OtpInputScreen> createState() => _OtpInputScreenState();
}

class _OtpInputScreenState extends State<OtpInputScreen> {
  final TextEditingController _otpController = TextEditingController();
  bool _isLoading = false;
  String? _error;
  Timer? _timer;
  int _remainingSeconds = 600; // 10 minutes
  bool _isExpired = false;

  @override
  void initState() {
    super.initState();
    _startTimer();
  }

  @override
  void dispose() {
    _otpController.dispose();
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

  String _formatTime(int seconds) {
    final minutes = seconds ~/ 60;
    final remainingSeconds = seconds % 60;
    return '${minutes.toString().padLeft(2, '0')}:${remainingSeconds.toString().padLeft(2, '0')}';
  }

  Future<void> _verifyOtp() async {
    final code = _otpController.text.trim();
    if (code.length != 6) {
      setState(() => _error = 'Please enter a 6-digit code');
      return;
    }

    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final response = widget.otpType == 'start'
          ? await ApiClient.verifyStartOtp(widget.bookingId, widget.correlationId, code)
          : await ApiClient.verifyEndOtp(widget.bookingId, widget.correlationId, code);

      if (response['ok'] == true || response['valid'] == true) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Job ${widget.otpType} verified successfully!'),
            backgroundColor: Colors.green,
          ),
        );
        Navigator.of(context).pop(true); // Return success
      } else {
        setState(() => _error = response['error'] ?? 'Invalid OTP code');
      }
    } catch (e) {
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Enter ${widget.otpType == 'start' ? 'Start' : 'End'} OTP'),
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
                  widget.otpType == 'start' ? 'Start Job Verification' : 'End Job Verification',
                  style: const TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 8),
                Text(
                  'Enter the 6-digit code provided by the worker',
                  style: TextStyle(
                    fontSize: 16,
                    color: Colors.grey[600],
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 32),

                // Timer
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: _isExpired ? Colors.red.withOpacity(0.1) : Colors.white,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: _isExpired ? Colors.red : (_remainingSeconds < 60 ? Colors.orange : Colors.grey.shade300),
                      width: 2,
                    ),
                  ),
                  child: Column(
                    children: [
                      Text(
                        _isExpired ? 'CODE EXPIRED' : 'Code expires in',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: _isExpired ? Colors.red : (_remainingSeconds < 60 ? Colors.orange : Colors.black),
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        _formatTime(_remainingSeconds),
                        style: TextStyle(
                          fontSize: 24,
                          fontWeight: FontWeight.bold,
                          color: _isExpired ? Colors.red : (_remainingSeconds < 60 ? Colors.orange : Colors.black),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 32),

                // OTP Input
                Container(
                  constraints: const BoxConstraints(maxWidth: 300),
                  child: TextField(
                    controller: _otpController,
                    keyboardType: TextInputType.number,
                    maxLength: 6,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 8,
                    ),
                    decoration: InputDecoration(
                      hintText: '000000',
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide(
                          color: widget.otpType == 'start' ? Colors.blue : Colors.green,
                          width: 2,
                        ),
                      ),
                      counterText: '',
                    ),
                    onChanged: (value) {
                      setState(() => _error = null);
                      if (value.length == 6) {
                        // Auto-verify when 6 digits entered
                        _verifyOtp();
                      }
                    },
                  ),
                ),

                // Error message
                if (_error != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 16),
                    child: Text(
                      _error!,
                      style: const TextStyle(
                        color: Colors.red,
                        fontSize: 16,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ),

                const SizedBox(height: 32),

                // Verify button
                if (!_isExpired)
                  ElevatedButton(
                    onPressed: _isLoading ? null : _verifyOtp,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: widget.otpType == 'start' ? Colors.blue : Colors.green,
                      padding: const EdgeInsets.symmetric(horizontal: 48, vertical: 16),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: _isLoading
                        ? const SizedBox(
                            width: 24,
                            height: 24,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                            ),
                          )
                        : Text(
                            'Verify ${widget.otpType == 'start' ? 'Start' : 'End'}',
                            style: const TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                  ),

                const SizedBox(height: 16),

                // Back button
                OutlinedButton(
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 48, vertical: 16),
                  ),
                  onPressed: () => Navigator.of(context).pop(false),
                  child: const Text('Cancel'),
                ),

                // Expired message
                if (_isExpired)
                  Padding(
                    padding: const EdgeInsets.only(top: 16),
                    child: Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: Colors.red.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: Colors.red),
                      ),
                      child: const Column(
                        children: [
                          Icon(Icons.timer_off, color: Colors.red, size: 32),
                          SizedBox(height: 8),
                          Text(
                            'OTP Code Expired',
                            style: TextStyle(
                              color: Colors.red,
                              fontWeight: FontWeight.bold,
                              fontSize: 16,
                            ),
                          ),
                          SizedBox(height: 4),
                          Text(
                            'Please ask the user to regenerate the code',
                            style: TextStyle(
                              color: Colors.red,
                              fontSize: 14,
                            ),
                            textAlign: TextAlign.center,
                          ),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}