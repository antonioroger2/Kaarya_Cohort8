import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import '../../features/shared/booking_details_screen.dart';
import '../../features/shared/report_dialog.dart';
import '../../core/api_client.dart';

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

    final oldWorker = oldWidget.bookingData['workerId'];
    final newWorker = widget.bookingData['workerId'];
    final oldUser = oldWidget.bookingData['userId'];
    final newUser = widget.bookingData['userId'];

    if (oldWorker != newWorker || oldUser != newUser) {
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
      _profileFuture = FirebaseFirestore.instance
          .collection(collection)
          .doc(_counterpartId)
          .get();
    } else {
      _profileFuture = null;
    }
  }

  String _getStatusText(String code) {
    switch (code.toLowerCase()) {
      case 'b1': return 'Request Sent';
      case 'b2': return 'Pending Approval';
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

  Future<void> _cancelBooking() async {
    if (_currentBookingId == null) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Cancel Booking'),
        content: const Text('Are you sure you want to cancel?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('No')),
          TextButton(onPressed: () => Navigator.pop(context, true), child: const Text('Yes')),
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

      if (response['ok'] == true) {
        if (!mounted) return;
        setState(() { _displayStatus = 'cancelled'; });
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Booking cancelled.'), backgroundColor: Colors.green));
      } 
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red));
    } finally {
      if (mounted) setState(() => _isCancelling = false);
    }
  }

  Future<void> _reportIssue(String reportType) async {
    final reportReason = await showDialog<String>(context: context, builder: (context) => ReportDialog(reportType: reportType));
    if (reportReason == null || reportReason.isEmpty || _currentBookingId == null) return;

    try {
      final currentUserId = FirebaseAuth.instance.currentUser!.uid;
      final reportedUserId = widget.bookingData['workerId'] == currentUserId
          ? widget.bookingData['userId']
          : widget.bookingData['workerId'];

      await FirebaseFirestore.instance.collection('reports').add({
        'bookingId': _currentBookingId,
        'reporterId': currentUserId,
        'reportedUserId': reportedUserId,
        'reportType': reportType,
        'reason': reportReason,
        'status': 'Pending',
        'createdAt': Timestamp.now(),
        'bookingData': widget.bookingData,
      });

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Report submitted.'), backgroundColor: Colors.orange));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Failed: $e'), backgroundColor: Colors.red));
    }
  }

    String _capitalize(String s) {
    if (s.isEmpty) return s;
    return s[0].toUpperCase() + s.substring(1);
  }

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
    } catch (e) {
      date = DateTime.now();
    }

    final statusText = _getStatusText(_displayStatus);
    final wage = (widget.bookingData['wage'] ?? 0).toInt();
    
        final rawService = widget.bookingData['serviceType'] ?? 'Service';
    final serviceType = _capitalize(rawService.toString());

    final currentUserId = FirebaseAuth.instance.currentUser?.uid;
    final workerId = widget.bookingData['workerId'];
    final currentUserIsWorker = (currentUserId == workerId);

    Color statusColor;
    IconData statusIcon;
    switch (_displayStatus.toLowerCase()) {
      case 'e3': statusColor = Colors.green; statusIcon = Icons.check_circle; break;
      case 'cancelled': case 'rejected': statusColor = Colors.red; statusIcon = Icons.cancel; break;
      case 'a1': statusColor = Colors.blue; statusIcon = Icons.calendar_today; break;
      case 'w2': statusColor = Colors.cyan; statusIcon = Icons.construction; break;
      case 'w1': statusColor = Colors.deepPurple; statusIcon = Icons.location_on; break;
      case 'e1': case 'e2': statusColor = Colors.orange; statusIcon = Icons.payment; break;
      default: statusColor = Colors.orange; statusIcon = Icons.pending;
    }

    return InkWell(
      onTap: () {
        if (_currentBookingId != null) {
          Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) => BookingDetailsScreen(
                bookingId: _currentBookingId!,
                userId: currentUserId!,
                isWorker: currentUserIsWorker,
              ),
            ),
          );
        }
      },
      child: Card(
        margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        elevation: 2,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        child: Column(
          children: [
                        Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                borderRadius: const BorderRadius.only(topLeft: Radius.circular(12), topRight: Radius.circular(12)),
                gradient: LinearGradient(
                  colors: [statusColor.withOpacity(0.1), statusColor.withOpacity(0.05)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
              ),
              child: Row(
                children: [
                  Icon(statusIcon, color: statusColor, size: 20),
                  const SizedBox(width: 8),
                  Text(statusText, style: TextStyle(color: statusColor, fontWeight: FontWeight.bold)),
                  const Spacer(),
                  Text(DateFormat('EEE, MMM d').format(date), style: const TextStyle(fontWeight: FontWeight.w500)),
                ],
              ),
            ),
            
                        Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                                    _profileFuture == null 
                  ? _buildProfileRow(
                                                                                        mainText: serviceType,
                      subText: 'Pending Assignment', 
                      rating: 0.0,
                      showRating: false,
                      isPendingState: true,                     )
                  : FutureBuilder<DocumentSnapshot>(
                      future: _profileFuture,
                      builder: (context, snapshot) {
                        String displayName;
                        String subTitle;
                        
                        if (currentUserIsWorker) {
                          displayName = widget.bookingData['userName'] ?? 'Client';
                          subTitle = 'Client';
                        } else {
                          displayName = widget.bookingData['workerName'] ?? 'Pending Assignment';
                          subTitle = 'Service Provider';
                        }
                        
                        double rating = 0.0;

                        if (snapshot.connectionState == ConnectionState.waiting) {
                           return _buildLoadingSkeleton();
                        }

                        if (snapshot.hasData && snapshot.data!.exists) {
                          final data = snapshot.data!.data() as Map<String, dynamic>;
                          displayName = data['name'] ?? displayName;
                          rating = (data['avgRating'] ?? 0.0).toDouble();
                        }

                        return _buildProfileRow(
                                                                                                        mainText: displayName,
                          subText: subTitle,
                          rating: rating,
                          showRating: !currentUserIsWorker,
                          isPendingState: false,
                        );
                      },
                    ),
                  
                  const Divider(height: 32),
                  
                                    Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(children: [
                            Icon(Icons.schedule, size: 16, color: Colors.grey[600]), 
                            const SizedBox(width: 6), 
                            Text('Start: ${DateFormat.jm().format(date.add(Duration(hours: (widget.bookingData['startHour'] ?? 0))))}',
                            style: const TextStyle(fontWeight: FontWeight.w500))
                          ]),
                          const SizedBox(height: 8),
                          Row(children: [
                            Icon(Icons.timer_outlined, size: 16, color: Colors.grey[600]), 
                            const SizedBox(width: 6), 
                            Text('${(widget.bookingData['endHour'] ?? 0) - (widget.bookingData['startHour'] ?? 0)} hrs duration')
                          ]),
                        ],
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                        decoration: BoxDecoration(
                          color: Colors.green.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(8)
                        ),
                        child: Text('₹$wage', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18, color: Colors.green)),
                      ),
                    ],
                  ),
                  
                                    if (!currentUserIsWorker && (_displayStatus == 'b2' || _displayStatus == 'b1' || _displayStatus == 'a1') && !_isCancelling)
                    Padding(
                      padding: const EdgeInsets.only(top: 20),
                      child: Row(
                        children: [
                          Expanded(
                            child: OutlinedButton(
                              onPressed: _cancelBooking,
                              style: OutlinedButton.styleFrom(
                                foregroundColor: Colors.red, 
                                side: const BorderSide(color: Colors.red),
                                padding: const EdgeInsets.symmetric(vertical: 12)
                              ),
                              child: const Text('Cancel Booking'),
                            ),
                          ),
                        ],
                      ),
                    ),

                  if (_isCancelling) 
                    const Padding(padding: EdgeInsets.only(top: 20), child: Center(child: CircularProgressIndicator())),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

    Widget _buildProfileRow({
    required String mainText, 
    required String subText, 
    required double rating, 
    required bool showRating,
    required bool isPendingState
  }) {
    return Row(
      children: [
                                CircleAvatar(
          backgroundColor: isPendingState ? Colors.grey.withOpacity(0.2) : Colors.teal.withOpacity(0.1),
          radius: 22,
          child: isPendingState 
            ? Icon(Icons.search, color: Colors.grey[600], size: 20)             : Text(
                mainText.isNotEmpty ? mainText[0].toUpperCase() : '?', 
                style: const TextStyle(color: Colors.teal, fontWeight: FontWeight.bold, fontSize: 18)
              ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
                            
                                          
                                                        
              if (isPendingState) ...[
                Text(
                  mainText,                   style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Colors.black87),
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 2),
                Text(
                  subText,                   style: TextStyle(color: Colors.orange[800], fontSize: 12, fontStyle: FontStyle.italic, fontWeight: FontWeight.w500)
                ),
              ] else ...[
                                                                 Text(
                  subText, 
                  style: TextStyle(color: Colors.grey[600], fontSize: 12)
                ),
                Text(
                  mainText, 
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                  overflow: TextOverflow.ellipsis,
                ),
                if (showRating && rating > 0)
                  Row(
                    children: [
                      const Icon(Icons.star, size: 14, color: Colors.amber),
                      const SizedBox(width: 4),
                      Text(rating.toStringAsFixed(1), style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                    ],
                  ),
              ]
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildLoadingSkeleton() {
    return Row(children: [
       const CircleAvatar(backgroundColor: Colors.grey, radius: 18),
       const SizedBox(width: 12),
       Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
         Container(width: 80, height: 10, color: Colors.grey[200]),
         const SizedBox(height: 4),
         Container(width: 120, height: 14, color: Colors.grey[300]),
       ])
    ]);
  }
}