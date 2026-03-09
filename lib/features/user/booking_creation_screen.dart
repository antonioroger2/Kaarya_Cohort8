import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart'; 
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:intl/intl.dart';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;

import '../../core/api_client.dart'; 
import '../../features/auth/auth_screen.dart';

class BookingCreationScreen extends StatefulWidget {
  final String userId;
  final Map<String, dynamic> preSelectedWorker; 

  static Map<String, dynamic>? pendingBookingData;

  const BookingCreationScreen({
    super.key, 
    required this.userId, 
    required this.preSelectedWorker, 
  });

  @override
  State<BookingCreationScreen> createState() => _BookingCreationScreenState();
}

class _BookingCreationScreenState extends State<BookingCreationScreen> {

  late final String workerId;
  late final String workerName;
  late final String workerPhone;
  late final Map<String, dynamic> workerCwData;
  late final int workingStartHour = 0; 
  late final int workingEndHour = 24;  
  late final double hourlyRate;

  
  DateTime _selectedDate = DateTime.now(); 
  int? _selectedStartHour; 
  int _hours = 2;
  bool _isLoading = false;
  bool _isFetchingSlots = false;
  Set<int> _availableDbSlots = {}; 
  String? _notesErrorText;
  
  
  final _notesController = TextEditingController();
  final _addressController = TextEditingController(); 
  final _landmarkController = TextEditingController(); 
  
  
  String? _selectedServiceCategory;
  List<String> _availableCategories = [];
  
  Map<String, dynamic>? _userData;

  
  Position? _currentPosition;
  String? _nominatimAddress;   
  bool _isGettingLocation = false;
  int _dynamicTA = 38; // Will be calculated based on distance

  // Dynamic Threshold Logic based on the nature of the job
  double _workerDistanceKm = 0.0;
  bool _showDistanceWarning = false;
  double _jobDistanceThreshold = 10.0; // Default

  // Dynamic Threshold Logic based on the nature of the job
  double _getThresholdForJob(String? category) {
    if (category == null) return 10.0;
    final cat = category.toLowerCase();
    
    // Highly localized jobs (High flight risk if far)
    if (cat.contains('clean') || cat.contains('cook') || cat.contains('maid') || cat.contains('sweep')) {
      return 10.0; 
    }
    // Standard trades (Moderate distance acceptable)
    if (cat.contains('plumb') || cat.contains('electric') || cat.contains('carpenter') || cat.contains('mason')) {
      return 20.0;
    }
    // Specialists / Consultants (Can travel far or "fly in")
    if (cat.contains('special') || cat.contains('consult') || cat.contains('tech')) {
      return 500.0; 
    }
    
    return 15.0; // Fallback default
  }
  static const int MIN_NOTES_LENGTH = 10;
  static const int MAX_NOTES_LENGTH = 150;

  @override
  void initState() {
    super.initState();
    
    
    workerId = widget.preSelectedWorker['uid'] ?? widget.preSelectedWorker['workerId'] ?? '';
    workerName = widget.preSelectedWorker['name'] ?? 'Worker';
    workerPhone = widget.preSelectedWorker['phone'] ?? '';
    workerCwData = widget.preSelectedWorker['cw_data'] as Map<String, dynamic>? ?? {};
    hourlyRate = (widget.preSelectedWorker['perHourCharge'] as num?)?.toDouble() ?? 500.0;

    final now = DateTime.now();
    _selectedDate = DateTime(now.year, now.month, now.day);
    
    
    if (workerCwData.isNotEmpty) {
      _availableCategories = workerCwData.keys.toList();
      _selectedServiceCategory = _availableCategories.first;
    } else {
      _availableCategories = ['General'];
      _selectedServiceCategory = 'General';
    }

    _fetchUserData();
    
    _fetchAvailability(); 
    _checkPendingData();
    
    
    _getCurrentLocation();
    
    _notesController.addListener(_updateNotesValidation);
  }
  
  void _updateNotesValidation() {
    final length = _notesController.text.length;
    setState(() {
      if (length < MIN_NOTES_LENGTH && length > 0) {
        _notesErrorText = 'Min $MIN_NOTES_LENGTH chars required. Current: $length';
      } else if (length > MAX_NOTES_LENGTH) {
        _notesErrorText = 'Max $MAX_NOTES_LENGTH chars exceeded.';
      } else {
        _notesErrorText = null;
      }
    });
  }


  @override
  void dispose() {
    _notesController.removeListener(_updateNotesValidation);
    _notesController.dispose();
    _addressController.dispose();
    _landmarkController.dispose();
    super.dispose();
  }

  
  Future<void> _fetchUserData() async {
    if (widget.userId.isEmpty) return;
    try {
      final doc = await FirebaseFirestore.instance.collection('users').doc(widget.userId).get();
      if (doc.exists) {
        setState(() {
          _userData = doc.data();
          if (_addressController.text.isEmpty) {
            _addressController.text = _userData?['locality'] ?? _userData?['address'] ?? ''; 
          }
        });
      }
    } catch (e) {
      debugPrint("Error fetching user: $e");
    }
  }

  
  void _checkPendingData() {
    if (BookingCreationScreen.pendingBookingData != null) {
      final data = BookingCreationScreen.pendingBookingData!;
      if (data['workerId'] == workerId) { 
        setState(() {
          _selectedDate = data['date'];
          _selectedStartHour = data['hour'];
          _hours = data['hours'];
          _notesController.text = data['notes'];
          _selectedServiceCategory = data['serviceCategory'];
          
          _addressController.text = data['address'] ?? '';
          _landmarkController.text = data['landmark'] ?? '';
        });
        
        BookingCreationScreen.pendingBookingData = null;

        if (FirebaseAuth.instance.currentUser != null && widget.userId.isNotEmpty) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
             ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Resuming your booking...'), backgroundColor: Colors.blue)
            );
            _confirmBooking(); 
          });
        }
      }
    }
  }

  
  Future<void> _fetchAvailability() async {
    setState(() { _isFetchingSlots = true; _availableDbSlots.clear(); _selectedStartHour = null; });
    try {
      final dateStr = DateFormat('yyyy-MM-dd').format(_selectedDate);
                  
      
      final response = await ApiClient.post('/get-worker-availability', {
        'workerId': workerId, 
        'date': dateStr,
      });
      
      if (response['ok'] == true) {
        final List<dynamic> hours = response['availableHours'];
        if (mounted) setState(() => _availableDbSlots = hours.cast<int>().toSet());
      } else {
         
         debugPrint("Failed to fetch slots: ${response['error']}");
         
         final List<dynamic> hours = [8, 9, 10, 11, 13, 14, 15, 16, 17, 18, 19];
         if (mounted) setState(() => _availableDbSlots = hours.cast<int>().toSet());
      }
      
    } catch (e) {
      debugPrint("Error fetching availability: $e");
    } finally {
      if (mounted) setState(() => _isFetchingSlots = false);
    }
  }

  
  List<int> _getAvailableStartSlots() {
    List<int> slots = [];
    final now = DateTime.now();
    final minBookingTime = now.add(const Duration(hours: 1));
    
    for (int hour = workingStartHour; hour < workingEndHour; hour++) {
      if (hour + _hours > workingEndHour) continue;
      
      bool isSlotBlockAvailable = true;
      for (int i = 0; i < _hours; i++) {
        
        if (!_availableDbSlots.contains(hour + i)) { isSlotBlockAvailable = false; break; }
      }
      if (!isSlotBlockAvailable) continue;
      
      final slotDateTime = DateTime(_selectedDate.year, _selectedDate.month, _selectedDate.day, hour);
      if (DateUtils.isSameDay(_selectedDate, now)) {
        
        if (slotDateTime.isBefore(minBookingTime)) continue;
      }
      slots.add(hour);
    }
    return slots;
  }

  
  Future<void> _getNominatimAddress(double lat, double lon) async {
    try {
      final url = Uri.parse(
        'https://nominatim.openstreetmap.org/reverse?format=json&lat=$lat&lon=$lon&addressdetails=1'
      );
      final response = await http.get(url, headers: {
        'User-Agent': 'FlutterWorkerApp/1.0 (contact@example.com)' 
      });

      if (response.statusCode == 200) {
        final decoded = json.decode(response.body);
        if (mounted) {
          setState(() {
            _nominatimAddress = decoded['display_name'];
          });
        }
      }
    } catch (e) {
      debugPrint("Reverse Geocoding Failed: $e");
    }
  }

  Future<void> _getCurrentLocation() async {
    setState(() => _isGettingLocation = true);
    try {
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Location services are disabled.'), backgroundColor: Colors.orange));
        return;
      }

      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied || permission == LocationPermission.deniedForever) {
          if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Location permissions denied.'), backgroundColor: Colors.orange));
          return;
        }
      }
      
      Position position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.low       );

      setState(() {
        _currentPosition = position;
      });

      await _getNominatimAddress(position.latitude, position.longitude);
      _calculateDistanceAndTA(position.latitude, position.longitude); // Calculate distance and TA
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Location fetched in background."), backgroundColor: Colors.blue)
        );
      }
    } catch (e) {
      debugPrint("Location Error: $e");
    } finally {
      if (mounted) setState(() => _isGettingLocation = false);
    }
  }

  // Fetch Lat/Long from Pincode using data.gov.in API
  Future<void> _fetchLatLongFromPincode(String pincode) async {
    if (pincode.length != 6) return;
    setState(() => _isGettingLocation = true);
    
    try {
      // Using your provided API details
      final url = Uri.parse('https://api.data.gov.in/resource/6176ee09-3d56-4a3b-8115-21841576b2f6?api-key=579b464db66ec23bdd000001cdd3946e44ce4aad7209ff7b23ac571b&format=json&filters[pincode]=$pincode');
      final response = await http.get(url);

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data['records'] != null && data['records'].isNotEmpty) {
          // Assume API returns lat/lon in the records (adjust keys based on actual API response)
          final record = data['records'][0]; 
          final lat = double.tryParse(record['latitude'].toString()) ?? 0.0;
          final lng = double.tryParse(record['longitude'].toString()) ?? 0.0;

          if (lat != 0.0 && lng != 0.0) {
            _calculateDistanceAndTA(lat, lng);
          }
        }
      }
    } catch (e) {
      debugPrint("Pincode API Error: $e");
    } finally {
      setState(() => _isGettingLocation = false);
    }
  }

  // Calculate Distance and trigger liability warning
  void _calculateDistanceAndTA(double userLat, double userLng) {
    final workerLat = widget.preSelectedWorker['lat'] as double?;
    final workerLng = widget.preSelectedWorker['lng'] as double?;

    if (workerLat != null && workerLng != null) {
      double distanceInMeters = Geolocator.distanceBetween(
        userLat, userLng, 
        workerLat, workerLng
      );
      
      setState(() {
        _workerDistanceKm = distanceInMeters / 1000;
        _jobDistanceThreshold = _getThresholdForJob(_selectedServiceCategory);
        
        // Calculate TA: ₹12 per km
        int calculatedTA = (_workerDistanceKm * 12.0).round();
        _dynamicTA = calculatedTA < 30 ? 30 : calculatedTA; // Minimum ₹30 TA
        
        // Trigger Warning if distance exceeds the dynamic threshold for this specific job
        _showDistanceWarning = _workerDistanceKm > _jobDistanceThreshold;
      });
    }
  }

  String _formatTime(int hour) {
    if (hour == 24 || hour == 0) return "12 AM";
    final now = DateTime.now();
    final dt = DateTime(now.year, now.month, now.day, hour % 24);
    return DateFormat.j().format(dt); 
  }

  String _formatCurrency(num val) {
    if (val <= 0) return '—';
    final formatter = NumberFormat.currency(locale: 'en_IN', symbol: '₹', decimalDigits: 0);
    return formatter.format(val);
  }
  
    
  
  Future<void> _confirmBooking() async {
    
    if (_selectedServiceCategory == null) {
       ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Please select a Service Category.'), backgroundColor: Colors.orange));
      return;
    }
    if (_selectedStartHour == null) {
       ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Please select a starting time slot.'), backgroundColor: Colors.orange));
      return;
    }

    final notesText = _notesController.text.trim();
    final notesLength = notesText.length;
    if (notesLength < MIN_NOTES_LENGTH || notesLength > MAX_NOTES_LENGTH) {
       ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Notes must be between $MIN_NOTES_LENGTH and $MAX_NOTES_LENGTH characters (currently $notesLength).'),
          backgroundColor: Colors.red
        )
      );
      return;
    }
    
    if (_addressController.text.trim().isEmpty) {
       ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Please enter your Address/Locality.'), backgroundColor: Colors.red));
      return;
    }

    
    final currentUser = FirebaseAuth.instance.currentUser;
    if (currentUser == null) {
      BookingCreationScreen.pendingBookingData = {
        'workerId': workerId, 
        'workerName': workerName, 
        'workerPhone': workerPhone,
        'hourlyRate': hourlyRate,
        'cw_data': workerCwData,
        'serviceCategory': _selectedServiceCategory,
        
        'serviceTask': _selectedServiceCategory, 
        'date': _selectedDate, 
        'hour': _selectedStartHour,
        'hours': _hours, 
        'notes': notesText, 
        'address': _addressController.text.trim(), 
        'landmark': _landmarkController.text.trim()
      };
      await Navigator.of(context).push(MaterialPageRoute(builder: (_) => const AuthScreen()));
      if (FirebaseAuth.instance.currentUser != null && mounted) Navigator.of(context).pop(); 
      return;
    }

    setState(() => _isLoading = true);
    try {
      if (_userData == null && widget.userId.isNotEmpty) {
          final userDoc = await FirebaseFirestore.instance.collection('users').doc(widget.userId).get();
          if (userDoc.exists) _userData = userDoc.data();
      }
      
      final userName = _userData?['name'] ?? 'Anonymous User';
      final userPhone = _userData?['phone'] ?? '';
      final calculatedWage = (hourlyRate * _hours).toInt();

      
      final bookingPayload = {
        'userId': currentUser.uid,
        'userPhone': userPhone,
        'userName': userName, 
        'candidateWorkers': [workerId], 

        'userInfo': {'name': userName, 'phone': userPhone, 'email': _userData?['email'] ?? ''},
        'workerInfo': {'name': workerName, 'phone': workerPhone},

        'date': DateFormat('yyyy-MM-dd').format(_selectedDate), 
        'startHour': _selectedStartHour!,
        'endHour': _selectedStartHour! + _hours,
        'wage': calculatedWage,
        'ta': _dynamicTA, 
        
        'serviceCategory': _selectedServiceCategory,
        
        'serviceType': _selectedServiceCategory, 
        
        'location': {
          'locality': _userData?['locality'] ?? 'Unknown',
          'pin': _userData?['pin'] ?? '',
          'address': _addressController.text.trim(), 
          'landmark': _landmarkController.text.trim(),
          'lat': _currentPosition?.latitude, 
          'lng': _currentPosition?.longitude,
          'source': _currentPosition != null ? 'gps' : 'manual',
          'db_address': _nominatimAddress ?? _addressController.text.trim(), 
        },
        'notes': notesText,
      };

      
      final response = await ApiClient.post('/create-booking', bookingPayload);
      
      if (response['ok'] == true) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Request Sent to $workerName!'), backgroundColor: Colors.green));
        Navigator.of(context).pop();
      } else {
        throw Exception(response['error'] ?? 'Failed to create booking.');
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red));
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  
  Widget _buildSectionCard({required String title, required Widget content}) {
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
          Text(
            title,
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.black87),
          ),
          const Divider(height: 20, thickness: 0.5),
          content,
        ],
      ),
    );
  }

  Widget _buildBottomBookingBar(int calculatedWage, int totalCost) {
    return Container(
      padding: const EdgeInsets.all(16.0),
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.1),
            blurRadius: 10,
            offset: const Offset(0, -5),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
               Text("Service Wage ($_hours hrs):", style: TextStyle(color: Colors.grey[700])),
               Text(_formatCurrency(calculatedWage), style: const TextStyle(fontWeight: FontWeight.bold)),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
               Text("Travel Allowance (Base):", style: TextStyle(color: Colors.grey[700])),
               Text(_formatCurrency(_dynamicTA), style: const TextStyle(fontWeight: FontWeight.bold)),
            ],
          ),
          const Divider(height: 24, thickness: 1.5, color: Colors.black38),

          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: _isLoading ? null : _confirmBooking,
              style: ElevatedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 16),
                backgroundColor: Colors.teal.shade600,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                elevation: 5,
              ),
              child: _isLoading 
                ? const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(color: Colors.white))
                : Text('Total: ${_formatCurrency(totalCost)} - Send Request', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            ),
          ),
        ],
      ),
    );
  }


  @override
  Widget build(BuildContext context) {
    final availableSlots = _getAvailableStartSlots();
    
    final calculatedWage = (hourlyRate * _hours).toInt();
    final totalCost = calculatedWage + _dynamicTA;

    return Scaffold(
      backgroundColor: Colors.grey.shade100,
      appBar: AppBar(
        title: Text('Book ${workerName.split(' ').first}', style: const TextStyle(fontWeight: FontWeight.w600)),
        centerTitle: true,
        elevation: 0,
        backgroundColor: Colors.white,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            
            _buildSectionCard(
              title: 'Service Category',
              content: Column(
                children: [
                  DropdownButtonFormField<String>(
                    value: _selectedServiceCategory,
                    items: _availableCategories.map((s) => DropdownMenuItem(value: s, child: Text(s))).toList(),
                    onChanged: (v) => setState(() => _selectedServiceCategory = v),
                    decoration: const InputDecoration(labelText: "Service Category", prefixIcon: Icon(Icons.category_outlined, color: Colors.teal), border: OutlineInputBorder(borderRadius: BorderRadius.all(Radius.circular(10)))),
                  ),
                ],
              ),
            ),
            
            
            _buildSectionCard(
              title: 'Service Location',
              content: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  TextField(
                    controller: _addressController,
                    decoration: const InputDecoration(
                      labelText: "Address / Locality",
                      hintText: "Flat 401, Sunshine Apts...",
                      prefixIcon: Icon(Icons.location_city, color: Colors.blue),
                      border: OutlineInputBorder(borderRadius: BorderRadius.all(Radius.circular(10))),
                    ),
                    maxLines: 2,
                  ),
                  
                  if (_currentPosition != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 8.0, bottom: 5.0),
                      child: Row(
                        children: [
                          const Icon(Icons.location_on, color: Colors.blue, size: 16),
                          const SizedBox(width: 5),
                          Text(
                            "GPS Ready: ${_currentPosition!.latitude.toStringAsFixed(3)}, ${_currentPosition!.longitude.toStringAsFixed(3)}",
                            style: TextStyle(color: Colors.blue.shade700, fontWeight: FontWeight.bold, fontSize: 12),
                          ),
                          if (_isGettingLocation)
                            const SizedBox(width: 10, height: 10, child: CircularProgressIndicator(strokeWidth: 1))
                        ],
                      ),
                    )
                  else if (_isGettingLocation)
                     const Padding(
                       padding: EdgeInsets.only(top: 8.0, bottom: 5.0),
                       child: Row(
                         children: [
                           SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)),
                           SizedBox(width: 5),
                           Text("Fetching GPS location ...", style: TextStyle(fontSize: 12, color: Colors.grey)),
                         ],
                       ),
                     ),

                  const SizedBox(height: 10),
                  TextField(
                    controller: _landmarkController,
                    decoration: const InputDecoration(
                      labelText: "Landmark",
                      hintText: "Near SBI Bank...",
                      prefixIcon: Icon(Icons.flag, color: Colors.grey),
                      border: OutlineInputBorder(borderRadius: BorderRadius.all(Radius.circular(10))),
                    ),
                  ),

                  // Pincode Field to trigger the API fallback
                  const SizedBox(height: 10),
                  TextField(
                    decoration: const InputDecoration(
                      labelText: "Pincode (Auto-fetches location)",
                      prefixIcon: Icon(Icons.pin_drop, color: Colors.blue),
                      border: OutlineInputBorder(),
                    ),
                    keyboardType: TextInputType.number,
                    maxLength: 6,
                    onChanged: (val) {
                      if (val.length == 6) {
                        _fetchLatLongFromPincode(val); // Trigger API
                      }
                    },
                  ),

                  // ==========================================
                  // DYNAMIC LIABILITY WARNING BANNER
                  // ==========================================
                  if (_showDistanceWarning)
                    Container(
                      margin: const EdgeInsets.only(top: 16),
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.red.shade50,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: Colors.red.shade300, width: 1.5),
                      ),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Icon(Icons.warning_amber_rounded, color: Colors.red, size: 28),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  "High Distance Liability Warning",
                                  style: TextStyle(fontWeight: FontWeight.bold, color: Colors.red.shade900),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  "This worker is ${_workerDistanceKm.toStringAsFixed(1)} km away. For a '${_selectedServiceCategory}' job, booking outside $_jobDistanceThreshold km highly increases the risk of delays or cancellation. Kaarya Connect holds no liability for extreme travel times.",
                                  style: TextStyle(color: Colors.red.shade800, fontSize: 12),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            ),

            
            _buildSectionCard(
              title: 'Schedule',
              content: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  
                  InkWell(
                    onTap: () async {
                      final picked = await showDatePicker(
                        context: context,
                        initialDate: _selectedDate,
                        firstDate: DateTime.now(),
                        lastDate: DateTime.now().add(const Duration(days: 30)),
                      );
                      if (picked != null) {
                        setState(() => _selectedDate = picked);
                        _fetchAvailability();
                      }
                    },
                    child: InputDecorator(
                      decoration: const InputDecoration(
                        labelText: 'Select Date',
                        prefixIcon: Icon(Icons.calendar_today, color: Colors.teal),
                        border: OutlineInputBorder(borderRadius: BorderRadius.all(Radius.circular(10))),
                      ),
                      child: Text(
                        DateFormat('EEEE, MMMM dd').format(_selectedDate),
                        style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w500),
                      ),
                    ),
                  ),
                  const SizedBox(height: 20),

                  
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text("Duration (Hours):", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                      Row(
                        children: [
                          IconButton(
                            onPressed: _hours > 1 ? () => setState(() { _hours--; _selectedStartHour = null; }) : null, 
                            icon: const Icon(Icons.remove_circle_outline, color: Colors.red)
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                            decoration: BoxDecoration(color: Colors.teal.shade50, borderRadius: BorderRadius.circular(8)),
                            child: Text('$_hours', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18, color: Colors.teal.shade800)),
                          ),
                          IconButton(
                            onPressed: () => setState(() { _hours++; _selectedStartHour = null; }), 
                            icon: const Icon(Icons.add_circle_outline, color: Colors.teal)
                          ),
                        ],
                      )
                    ],
                  ),
                  
                  
                  const Padding(
                    padding: EdgeInsets.only(top: 20, bottom: 8),
                    child: Text('Available Time Slots:', style: TextStyle(fontWeight: FontWeight.w600)),
                  ),

                  if (_isFetchingSlots) 
                    const Center(child: LinearProgressIndicator())
                  else if (availableSlots.isEmpty)
                     Container(
                       padding: const EdgeInsets.all(10),
                       decoration: BoxDecoration(color: Colors.red[50], borderRadius: BorderRadius.circular(8), border: Border.all(color: Colors.red.shade200)),
                       child: const Row(
                         children: [
                           Icon(Icons.error_outline, color: Colors.red),
                           SizedBox(width: 10),
                           Expanded(child: Text("No slots available for this date/duration.", style: TextStyle(color: Colors.red))),
                         ],
                       ),
                     )
                  else
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: availableSlots.map((hour) {
                        final isSelected = _selectedStartHour == hour;
                        return ChoiceChip(
                          label: Text(_formatTime(hour)),
                          selected: isSelected,
                          selectedColor: Colors.teal.shade400,
                          labelStyle: TextStyle(color: isSelected ? Colors.white : Colors.black87, fontWeight: FontWeight.w500),
                          backgroundColor: Colors.grey.shade200,
                          onSelected: (s) => setState(() => _selectedStartHour = s ? hour : null),
                        );
                      }).toList(),
                    ),
                ],
              ),
            ),
            
            
            _buildSectionCard(
              title: 'Additional Notes',
              content: TextField(
                controller: _notesController,
                maxLength: MAX_NOTES_LENGTH,                 
                onChanged: (_) => _updateNotesValidation(),                 
                decoration: InputDecoration(
                  hintText: 'Describe the issue or special requests (min $MIN_NOTES_LENGTH chars)...',
                  errorText: _notesErrorText,                   
                  border: const OutlineInputBorder(borderRadius: BorderRadius.all(Radius.circular(10))),
                  prefixIcon: const Icon(Icons.edit_note, color: Colors.grey),
                ),
                maxLines: 3,
                keyboardType: TextInputType.multiline,
                inputFormatters: [
                  LengthLimitingTextInputFormatter(MAX_NOTES_LENGTH),
                ],
              ),
            ),
            
            const SizedBox(height: 10),
          ],
        ),
      ),
      
      bottomNavigationBar: _buildBottomBookingBar(calculatedWage, totalCost),
    );
  }
}