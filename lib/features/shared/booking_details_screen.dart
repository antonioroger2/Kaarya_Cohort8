// lib/features/shared/booking_details_screen.dart
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import '../../core/theme.dart';
import '../../core/api_client.dart'; 
import './rating_dialog.dart'; 

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
  final _otpController = TextEditingController();
  bool _isLoading = false;
  bool _paymentReceived = false; 

  @override
  void dispose() {
    _otpController.dispose();
    super.dispose();
  }

  void _showLoading(bool loading) {
    setState(() => _isLoading = loading);
  }

  void _showError(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: Colors.red),
    );
  }

  Future<void> _generateStartOtp() async {
    _showLoading(true);
    try {
      final response = await ApiClient.post('/generate-start-otp', {
        'bookingId': widget.bookingId,
        'userId': widget.userId, 
      });

      if (response['ok'] == true) {
        _showOtpVerificationDialog('start', response['correlationId']);
      }
    } catch (e) {
      _showError(e.toString());
    } finally {
      _showLoading(false);
    }
  }

  Future<void> _verifyStartOtp(String correlationId) async {
    _showLoading(true);
    Navigator.of(context).pop(); 
    try {
      final response = await ApiClient.post('/verify-start-otp', {
        'bookingId': widget.bookingId,
        'correlationId': correlationId,
        'code': _otpController.text,
        'verifiedBy': 'user', 
      });

      if (response['valid'] == true) {
        _otpController.clear();
      }
    } catch (e) {
      _showError(e.toString());
    } finally {
      _showLoading(false);
    }
  }

  Future<void> _generateEndOtp() async {
    _showLoading(true);
    try {
      final response = await ApiClient.post('/generate-end-otp', {
        'bookingId': widget.bookingId,
        'requestedBy': 'user', 
      });

      if (response['ok'] == true) {

        _showOtpVerificationDialog('end', response['correlationId']);

      }
    } catch (e) {
      _showError(e.toString());
    } finally {
      _showLoading(false);
    }
  }

  Future<void> _verifyEndOtp(String correlationId) async {
    _showLoading(true);
    Navigator.of(context).pop(); 
    try {
      final response = await ApiClient.post('/verify-end-otp', {
        'bookingId': widget.bookingId,
        'correlationId': correlationId,
        'code': _otpController.text,
        'verifiedBy': 'user', 
        'paymentReceived': _paymentReceived, 
      });

      if (response['valid'] == true) {
        _otpController.clear();
        setState(() => _paymentReceived = false);
      }
    } catch (e) {
      _showError(e.toString());
    } finally {
      _showLoading(false);
    }
  }

  Future<void> _rateJob(Map<String, dynamic> bookingData) async {
    final workerName = bookingData['workerInfo']?['name'] ?? 'Worker';
    final workerId = bookingData['workerId'];

    final rating = await showDialog<double>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => RatingDialog(workerName: workerName),
    );

    if (rating == null || workerId == null) return;

    _showLoading(true);
    try {

      await ApiClient.post('/submit-rating', {
        'userId': widget.userId,
        'bookingId': widget.bookingId,
        'workerId': workerId,
        'rating': rating,
        'review': 'Rated $rating stars'
      });

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Rating submitted successfully!'),
        backgroundColor: Colors.green,
      ));

    } catch (e) {
      _showError(e.toString());
    } finally {
      if (mounted) _showLoading(false);
    }
  }

  void _showOtpVerificationDialog(String type, String correlationId) {
    _otpController.clear();
    bool isEndOtp = type == 'end';

    if (isEndOtp) setState(() => _paymentReceived = false);

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder( 
        builder: (context, setDialogState) {
          return AlertDialog(
            title: Text(isEndOtp ? 'Verify Job End' : 'Verify Job Start'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [

                const Text('Please ask your worker for the 6-digit code and enter it below.'),
                TextField(
                  controller: _otpController,
                  keyboardType: TextInputType.number,
                  maxLength: 6,
                ),

                if (isEndOtp) 
                  CheckboxListTile(
                    title: const Text("I have paid the worker"),
                    value: _paymentReceived,
                    onChanged: (val) {
                      setDialogState(() => _paymentReceived = val ?? false);
                      setState(() => _paymentReceived = val ?? false); 
                    },
                  ),
              ],
            ),
            actions: [
              TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Cancel')),
              ElevatedButton(
                onPressed: () {
                  if (isEndOtp) {
                    _verifyEndOtp(correlationId);
                  } else {
                    _verifyStartOtp(correlationId);
                  }
                },
                child: const Text('Verify'),
              ),
            ],
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {

    return Scaffold(
      appBar: AppBar(
        title: const Text('Booking Details'),
      ),
      body: DoodleBackground(
        child: StreamBuilder<DocumentSnapshot>(
          stream: FirebaseFirestore.instance.collection('bookings').doc(widget.bookingId).snapshots(),
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Center(child: CircularProgressIndicator());
            }
            if (!snapshot.hasData || !snapshot.data!.exists) {
              return const Center(child: Text('Booking not found'));
            }

            final bookingData = snapshot.data!.data() as Map<String, dynamic>;
            return _buildContent(context, bookingData);
          },
        ),
      ),
    );
  }

  Widget _buildContent(BuildContext context, Map<String, dynamic> bookingData) {

    final date = (bookingData['bookingDate'] as Timestamp).toDate();
    final status = bookingData['status'] ?? 'Unknown';
    final wage = (bookingData['wage'] ?? 0).toInt();
    final workerName = bookingData['workerInfo']?['name'] ?? bookingData['workerName'] ?? 'Worker';
    final userName = bookingData['userInfo']?['name'] ?? bookingData['userName'] ?? 'User';
    final timeSlot = (bookingData['endHour'] ?? 0) - (bookingData['startHour'] ?? 0);
    final rating = (bookingData['rating'] ?? 0).toDouble();

    Color statusColor;
    switch (status) {
      case 'e3': statusColor = Colors.green; break;
      case 'Cancelled':
      case 'Rejected': statusColor = Colors.red; break;
      case 'a1': statusColor = Colors.blue; break;
      case 'w2': statusColor = Colors.cyan; break;
      case 'w1':
      case 'e1':
      case 'e2': statusColor = Colors.deepPurple; break;
      case 'b1':
      case 'b2':
      default: statusColor = Colors.orange;
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [

          Card(child: Padding(padding: const EdgeInsets.all(16), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('Booking Status', style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 8),
              Container(padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6), decoration: BoxDecoration(color: statusColor.withOpacity(0.1), borderRadius: BorderRadius.circular(20),),
                child: Text(status, style: TextStyle(color: statusColor, fontWeight: FontWeight.bold,),),
              ),
            ],),),
          ),
          const SizedBox(height: 16),

          Card(child: Padding(padding: const EdgeInsets.all(16), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('Service Details', style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 12),
                Row(children: [const Icon(Icons.calendar_today, color: Colors.teal), const SizedBox(width: 8), Text(DateFormat('EEEE, MMMM d, yyyy').format(date)),]),
                const SizedBox(height: 8),
                Row(children: [const Icon(Icons.schedule, color: Colors.teal), const SizedBox(width: 8), Text(DateFormat.jm().format(date)),]),
                const SizedBox(height: 8),
                Row(children: [const Icon(Icons.timer, color: Colors.teal), const SizedBox(width: 8), Text('$timeSlot hours'),]),
                const SizedBox(height: 8),
                Row(children: [const Icon(Icons.currency_rupee, color: Colors.green), const SizedBox(width: 8), Text('₹$wage', style: const TextStyle(color: Colors.green, fontWeight: FontWeight.bold)),]),
              ],),),
          ),
          const SizedBox(height: 16),

          Card(child: Padding(padding: const EdgeInsets.all(16), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(widget.isWorker ? 'Client Information' : 'Worker Information', style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 12),
                Row(children: [
                    CircleAvatar(backgroundColor: Colors.teal.withOpacity(0.1), child: Icon(widget.isWorker ? Icons.person : Icons.engineering, color: Colors.teal),),
                    const SizedBox(width: 12),
                    Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text(widget.isWorker ? userName : workerName, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),),
                        Text(widget.isWorker ? 'Client' : 'Service Provider', style: TextStyle(color: Colors.grey[600]),),
                      ],),
                  ],),
              ],),),
          ),

          const SizedBox(height: 24),
          _buildActionButtons(context, bookingData, status, rating),
          const SizedBox(height: 24),
        ],
      ),
    );
  }

  Widget _buildActionButtons(BuildContext context, Map<String, dynamic> bookingData, String status, double rating) {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    List<Widget> buttons = [];

    if (widget.isWorker) {
      switch (status) {
        case 'a1': 
          buttons.add(const Text('Waiting for user to start job...', textAlign: TextAlign.center, style: TextStyle(color: Colors.blue, fontWeight: FontWeight.bold)));
          break;
        case 'w1': 
          buttons.add(const Text('Please share the Start OTP (from your SMS) with the user.', textAlign: TextAlign.center, style: TextStyle(color: Colors.purple, fontWeight: FontWeight.bold)));
          break;
        case 'w2': 
          buttons.add(const Text('Job in progress...', textAlign: TextAlign.center, style: TextStyle(color: Colors.cyan, fontWeight: FontWeight.bold)));
          break;
        case 'e1': 
        case 'e2': 
          buttons.add(const Text('Please share the End OTP (from your SMS) with the user to confirm payment.', textAlign: TextAlign.center, style: TextStyle(color: Colors.purple, fontWeight: FontWeight.bold)));
          break;
        case 'e3':
          buttons.add(const Text('Job completed.', textAlign: TextAlign.center, style: TextStyle(color: Colors.green, fontWeight: FontWeight.bold)));
          break;
      }
    }

    else {
      switch (status) {
        case 'a1': 
          buttons.add(ElevatedButton.icon(
            onPressed: _generateStartOtp,
            icon: const Icon(Icons.play_arrow),
            label: const Text('Start Job (Get Worker OTP)'),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.green),
          ));
          break;
        case 'w1': 
          buttons.add(ElevatedButton.icon(
            onPressed: () => _showOtpVerificationDialog('start', bookingData['startOTPCorrelationId']),
            icon: const Icon(Icons.password),
            label: const Text('Verify Worker\'s Start OTP'),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.purple),
          ));
          break;
        case 'w2': 
          buttons.add(ElevatedButton.icon(
            onPressed: _generateEndOtp,
            icon: const Icon(Icons.stop),
            label: const Text('End Job (Get Worker OTP)'),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
          ));
          break;
        case 'e1': 
        case 'e2': 
          buttons.add(ElevatedButton.icon(
            onPressed: () => _showOtpVerificationDialog('end', bookingData['endOTPCorrelationId']),
            icon: const Icon(Icons.password),
            label: const Text('Verify Worker\'s End OTP'),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.purple),
          ));
          break;
        case 'e3': 
          if (rating == 0) { 
            buttons.add(ElevatedButton.icon(
              onPressed: () => _rateJob(bookingData),
              icon: const Icon(Icons.star),
              label: const Text('Rate This Service'),
              style: ElevatedButton.styleFrom(backgroundColor: Colors.amber),
            ));
          } else {
             buttons.add(const Text('Job completed and rated.', textAlign: TextAlign.center, style: TextStyle(color: Colors.green, fontWeight: FontWeight.bold)));
          }
          break;
      }
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: buttons,
    );
  }
}