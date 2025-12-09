import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart'; 
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

  Future<void> _attemptStartJob(Map<String, dynamic> bookingData) async {
    final date = (bookingData['bookingDate'] as Timestamp).toDate();
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
        final response = await ApiClient.post('/generate-start-otp', { 'bookingId': widget.bookingId, 'userId': widget.userId }); 
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
      final response = await ApiClient.post('/verify-start-otp', { 'bookingId': widget.bookingId, 'correlationId': correlationId, 'code': _otpController.text, 'verifiedBy': 'user' }); 
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
      final response = await ApiClient.post('/generate-end-otp', { 'bookingId': widget.bookingId, 'requestedBy': 'user' }); 
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
      final response = await ApiClient.post('/verify-end-otp', { 'bookingId': widget.bookingId, 'correlationId': correlationId, 'code': _otpController.text, 'verifiedBy': 'user', 'paymentReceived': _paymentReceived }); 
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
    final rating = await showDialog<double>(context: context, barrierDismissible: false, builder: (dialogContext) => RatingDialog(workerName: workerName)); 
    if (rating == null || workerId == null) return; 
    
    _showLoading(true); 
    try { 
      await ApiClient.post('/submit-rating', { 'userId': widget.userId, 'bookingId': widget.bookingId, 'workerId': workerId, 'rating': rating, 'review': 'Rated $rating stars' }); 
      if (!mounted) return; 
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Rating submitted successfully!'), backgroundColor: Colors.green)); 
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
                TextField(controller: _otpController, keyboardType: TextInputType.number, maxLength: 6,),
                if (isEndOtp) CheckboxListTile(title: const Text("I have paid the worker"), value: _paymentReceived, onChanged: (val) { setDialogState(() => _paymentReceived = val ?? false); setState(() => _paymentReceived = val ?? false); },),
              ],
            ),
            actions: [
              TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Cancel')),
              ElevatedButton(onPressed: () { if (isEndOtp) { _verifyEndOtp(correlationId); } else { _verifyStartOtp(correlationId); } }, child: const Text('Verify')),
            ],
          );
        },
      ),
    );
  }

Future<void> _launchMaps(String address, double? lat, double? lng) async {
    final Uri uri;
    
    if (lat != null && lng != null) {

      uri = Uri.parse("https://www.google.com/maps/dir/?api=1&destination=$lat,$lng");
    } 
    else {
      return; 
    }

    try {
      if (!await launchUrl(uri, mode: LaunchMode.externalApplication)) {
        await launchUrl(uri, mode: LaunchMode.platformDefault);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not open Maps')),
        );
      }
    }
  }


  String _getStatusText(String code) {
    final c = code.toLowerCase();
    switch (c) {
      case 'b1': return 'Request Sent';
      case 'b2': return 'Booking Pending';
      case 'a1': return 'Scheduled';
      case 'w1': return 'Worker Arrived';
      case 'w2': return 'In Progress';
      case 'e1': case 'e2': return 'Payment Due';
      case 'e3': return 'Completed';
      case 'cancelled': return 'Cancelled';
      case 'rejected': return 'Declined';
      default: return code;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Booking Details')),
      body: DoodleBackground(
        child: StreamBuilder<DocumentSnapshot>(
          stream: FirebaseFirestore.instance.collection('bookings').doc(widget.bookingId).snapshots(),
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) return const Center(child: CircularProgressIndicator());
            if (!snapshot.hasData || !snapshot.data!.exists) return const Center(child: Text('Booking not found'));

            final bookingData = snapshot.data!.data() as Map<String, dynamic>;
            
            final status = (bookingData['status'] ?? '').toString();
            final isCancelled = status.toLowerCase() == 'cancelled';
            final isRejected = status.toLowerCase() == 'rejected';

            if (isCancelled || isRejected) {
               return Center(
                 child: Padding(
                   padding: const EdgeInsets.all(32.0),
                   child: Column(
                     mainAxisAlignment: MainAxisAlignment.center,
                     children: [
                       Icon(isRejected ? Icons.cancel_presentation : Icons.block, size: 80, color: Colors.grey[400]),
                       const SizedBox(height: 24),
                       Text(
                         isRejected ? "Booking Declined" : "Booking Cancelled", 
                         style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: Colors.grey[700])
                       ),
                       const SizedBox(height: 12),
                       const Text(
                         "This booking is no longer active.",
                         textAlign: TextAlign.center,
                         style: TextStyle(color: Colors.grey, fontSize: 16),
                       ),
                       const SizedBox(height: 32),
                       OutlinedButton.icon(
                         onPressed: () => Navigator.pop(context),
                         icon: const Icon(Icons.arrow_back),
                         label: const Text("Go Back"),
                       )
                     ],
                   ),
                 )
               );
            }

            final counterpartId = widget.isWorker ? bookingData['userId'] : bookingData['workerId'];
            final counterpartCollection = widget.isWorker ? 'users' : 'workers';

            return FutureBuilder<DocumentSnapshot>(
              future: (counterpartId != null) ? FirebaseFirestore.instance.collection(counterpartCollection).doc(counterpartId).get() : null,
              builder: (context, profileSnapshot) {
                Map<String, dynamic>? profileData;
                if (profileSnapshot.hasData && profileSnapshot.data!.exists) {
                  profileData = profileSnapshot.data!.data() as Map<String, dynamic>;
                }
                return _buildContent(context, bookingData, profileData);
              },
            );
          },
        ),
      ),
    );
  }

  Widget _buildContent(BuildContext context, Map<String, dynamic> bookingData, Map<String, dynamic>? profileData) {
    final dateStr = bookingData['date'] as String?;
    final startHour = bookingData['startHour'] ?? 0;
    final endHour = bookingData['endHour'] ?? 0;
    final statusCode = bookingData['status'] ?? 'Unknown';
    final statusText = _getStatusText(statusCode);
    final wage = (bookingData['wage'] ?? 0).toInt();

    final scheduledDate = dateStr != null 
        ? DateFormat('yyyy-MM-dd').parse(dateStr) 
        : (bookingData['bookingDate'] as Timestamp? ?? Timestamp.now()).toDate(); 
        
    final date = scheduledDate; 

    final startDateTime = DateTime(date.year, date.month, date.day, startHour);
    final endDateTime = DateTime(date.year, date.month, date.day, endHour);
    final timeRangeText = "${DateFormat.jm().format(startDateTime)} - ${DateFormat.jm().format(endDateTime)}";

    final now = DateTime.now();

    final statusLower = statusCode.toString().toLowerCase();
    final bool isJobActive = statusLower != 'cancelled' && statusLower != 'rejected' && statusLower != 'e3';
    
    final bool isWithinPrivacyWindow = now.isAfter(startDateTime.subtract(const Duration(hours: 1))) && now.isBefore(endDateTime.add(const Duration(hours: 1)));
    final bool showContactDetails = isJobActive && isWithinPrivacyWindow;
    final String name = profileData?['name'] ?? (widget.isWorker ? bookingData['userName'] : bookingData['workerName']) ?? 'N/A';
    final String phone = profileData?['phone'] ?? (widget.isWorker ? bookingData['userPhone'] : bookingData['workerPhone']) ?? 'N/A';
    final double rating = (profileData?['avgRating'] ?? 0.0).toDouble();

    final locMap = bookingData['location'] ?? {};
    final address = locMap['address'] ?? locMap['locality'] ?? 'Unknown';
    final landmark = locMap['landmark'] ?? '';
    final lat = locMap['lat'];
    final lng = locMap['lng'];
    final displayAddress = landmark.isNotEmpty ? "$address\n(Landmark: $landmark)" : address;

    Color statusColor;

    switch (statusLower) {
      case 'e3': statusColor = Colors.green; break;
      case 'cancelled': case 'rejected': statusColor = Colors.red; break;
      case 'a1': statusColor = Colors.blue; break;
      case 'w2': statusColor = Colors.cyan; break;
      case 'w1': statusColor = Colors.deepPurple; break;
      default: statusColor = Colors.orange;
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start, 
                children: [
                  Text('Booking Status', style: Theme.of(context).textTheme.titleMedium),
                  const SizedBox(height: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6), 
                    decoration: BoxDecoration(color: statusColor.withOpacity(0.1), borderRadius: BorderRadius.circular(20),),
                    child: Text(statusText, style: TextStyle(color: statusColor, fontWeight: FontWeight.bold)),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),

 
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16), 
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start, 
                children: [
                  Text('Service Details', style: Theme.of(context).textTheme.titleMedium),
                  const SizedBox(height: 12),
                  Row(children: [const Icon(Icons.calendar_today, color: Colors.teal), const SizedBox(width: 8), Text(DateFormat('EEEE, MMMM d, yyyy').format(date))]),
                  const SizedBox(height: 8),
                  Row(children: [const Icon(Icons.schedule, color: Colors.teal), const SizedBox(width: 8), Text(timeRangeText)]),
                  const SizedBox(height: 8),
                  Row(children: [const Icon(Icons.currency_rupee, color: Colors.green), const SizedBox(width: 8), Text('₹$wage', style: const TextStyle(color: Colors.green, fontWeight: FontWeight.bold))]),
                  const SizedBox(height: 12),
                  if (widget.isWorker) ...[
                    const Divider(),
                    const SizedBox(height: 8),
                    Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        const Icon(Icons.location_on, color: Colors.redAccent),
                        const SizedBox(width: 8),
                        Expanded(child: Text(showContactDetails ? displayAddress : "Address Hidden", style: const TextStyle(fontWeight: FontWeight.w500))),
                    ]),
                    if (showContactDetails)
                  Padding(
                    padding: const EdgeInsets.only(top: 12),
                    child: SizedBox(
                      width: double.infinity,
                      child: ElevatedButton.icon(
                        onPressed: () => _launchMaps(address, lat, lng),
                        icon: const Icon(Icons.map),
                        label: const Text("Navigate via Google Maps"),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.blue, 
                          foregroundColor: Colors.white
                        ),
                      ),
                    ),
                  )
                  ]
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),


          Card(
            child: Padding(
              padding: const EdgeInsets.all(16), 
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start, 
                children: [
                  Text(widget.isWorker ? 'Client Information' : 'Service Provider', style: Theme.of(context).textTheme.titleMedium),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      CircleAvatar(backgroundColor: Colors.teal.withOpacity(0.1), radius: 25, child: Text(name.isNotEmpty ? name[0].toUpperCase() : '?', style: const TextStyle(fontSize: 20, color: Colors.teal, fontWeight: FontWeight.bold))),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            Text(name, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18),),
                            if (!widget.isWorker) Row(children: [const Icon(Icons.star, size: 16, color: Colors.amber), const SizedBox(width: 4), Text(rating.toStringAsFixed(1))]),
                        ],),
                      ),
                    ],
                  ),
                  const Divider(height: 24),
                  _buildContactRow(Icons.phone, 'Phone', showContactDetails ? phone : 'Hidden '),
                ],
              ),
            ),
          ),
          const SizedBox(height: 24),
          
          _buildActionButtons(context, bookingData, statusCode, (bookingData['rating'] ?? 0).toDouble(), startDateTime),
          const SizedBox(height: 24),
        ],
      ),
    );
  }
  
  Widget _buildContactRow(IconData icon, String label, String value) {
    final isHidden = value.startsWith('Hidden');
    return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Icon(icon, color: isHidden ? Colors.grey : Colors.teal, size: 20), 
      const SizedBox(width: 12), 
      Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start, 
          children: [
            Text(label, style: TextStyle(color: Colors.grey[600], fontSize: 12)), 
            Text(value, style: TextStyle(fontSize: 15, fontWeight: isHidden ? FontWeight.normal : FontWeight.w500, color: isHidden ? Colors.grey : Colors.black87))
          ]
        )
      )
    ]);
  }

  Widget _buildActionButtons(BuildContext context, Map<String, dynamic> bookingData, String status, double rating, DateTime scheduledStart) {
    if (_isLoading) return const Center(child: CircularProgressIndicator());
    List<Widget> buttons = [];
    final now = DateTime.now();

    if (widget.isWorker) {
      switch (status) {
        case 'a1': buttons.add(const Text('Waiting for user to start job...', textAlign: TextAlign.center, style: TextStyle(color: Colors.blue, fontWeight: FontWeight.bold))); break;
        case 'w1': buttons.add(const Text('Please share the Start OTP (from your SMS) with the user.', textAlign: TextAlign.center, style: TextStyle(color: Colors.purple, fontWeight: FontWeight.bold))); break;
        case 'w2': buttons.add(const Text('Job in progress...', textAlign: TextAlign.center, style: TextStyle(color: Colors.cyan, fontWeight: FontWeight.bold))); break;
        case 'e1': case 'e2': buttons.add(const Text('Please share the End OTP (from your SMS) with the user to confirm payment.', textAlign: TextAlign.center, style: TextStyle(color: Colors.purple, fontWeight: FontWeight.bold))); break;
        case 'e3': buttons.add(const Text('Job completed.', textAlign: TextAlign.center, style: TextStyle(color: Colors.green, fontWeight: FontWeight.bold))); break;
      }
    } else {
      switch (status) {
        case 'a1': 
          final allowedStart = scheduledStart.subtract(const Duration(hours: 1));
          final allowedEnd = scheduledStart.add(const Duration(hours: 1));
          
          if (now.isBefore(allowedStart)) {
             buttons.add(ElevatedButton.icon(
               onPressed: null, 
               icon: const Icon(Icons.access_time),
               label: Text('Available at ${DateFormat.jm().format(allowedStart)}'),
               style: ElevatedButton.styleFrom(backgroundColor: Colors.grey, disabledBackgroundColor: Colors.grey[300], disabledForegroundColor: Colors.grey[600])
             ));
          } else if (now.isAfter(allowedEnd)) {
             buttons.add(ElevatedButton.icon(
               onPressed: null,
               icon: const Icon(Icons.error_outline),
               label: const Text('Job Expired'),
               style: ElevatedButton.styleFrom(backgroundColor: Colors.red, disabledBackgroundColor: Colors.red[100], disabledForegroundColor: Colors.red[800])
             ));
          } else {
             buttons.add(ElevatedButton.icon(
               onPressed: () => _attemptStartJob(bookingData), 
               icon: const Icon(Icons.play_arrow), 
               label: const Text('Start Job (Get Worker OTP)'), 
               style: ElevatedButton.styleFrom(backgroundColor: Colors.green)
             )); 
          }
          break;
        case 'w1': buttons.add(ElevatedButton.icon(onPressed: () => _showOtpVerificationDialog('start', bookingData['startOTPCorrelationId']), icon: const Icon(Icons.password), label: const Text('Verify Worker\'s Start OTP'), style: ElevatedButton.styleFrom(backgroundColor: Colors.purple))); break;
        case 'w2': buttons.add(ElevatedButton.icon(onPressed: _generateEndOtp, icon: const Icon(Icons.stop), label: const Text('End Job (Get Worker OTP)'), style: ElevatedButton.styleFrom(backgroundColor: Colors.red))); break;
        case 'e1': case 'e2': buttons.add(ElevatedButton.icon(onPressed: () => _showOtpVerificationDialog('end', bookingData['endOTPCorrelationId']), icon: const Icon(Icons.password), label: const Text('Verify Worker\'s End OTP'), style: ElevatedButton.styleFrom(backgroundColor: Colors.purple))); break;
        case 'e3': if (rating == 0) { buttons.add(ElevatedButton.icon(onPressed: () => _rateJob(bookingData), icon: const Icon(Icons.star), label: const Text('Rate This Service'), style: ElevatedButton.styleFrom(backgroundColor: Colors.amber))); } else { buttons.add(const Text('Job completed and rated.', textAlign: TextAlign.center, style: TextStyle(color: Colors.green, fontWeight: FontWeight.bold))); } break;
      }
    }
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: buttons);
  }
}