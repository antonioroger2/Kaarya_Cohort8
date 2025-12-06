import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:intl/intl.dart';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;
import '../../core/api_client.dart'; 
import '../../features/auth/auth_screen.dart';

// Assuming this path exists if you commented it out: import '../../core/theme.dart';

class BookingCreationScreen extends StatefulWidget {
  // REFACTORED: Simplified constructor to accept the full worker map
  final String userId;
  final Map<String, dynamic> preSelectedWorker; 

  // Static variable for pending data remains, but fields are generic
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
  // --- Worker Info Extracted from preSelectedWorker ---
  late final String workerId;
  late final String workerName;
  late final String workerPhone;
  late final Map<String, dynamic> workerCwData;
  late final int workingStartHour = 0; 
  late final int workingEndHour = 24;  
  late final double hourlyRate;

  // --- State Variables ---
  DateTime _selectedDate = DateTime.now(); 
  int? _selectedStartHour; 
  int _hours = 2;
  bool _isLoading = false;
  bool _isFetchingSlots = false;
  Set<int> _availableDbSlots = {}; 

  // Controllers
  final _notesController = TextEditingController();
  final _addressController = TextEditingController(); 
  final _landmarkController = TextEditingController(); 
  
  // Multi-Skill Fields
  String? _selectedServiceCategory;
  String? _selectedServiceTask;
  List<String> _availableCategories = [];
  List<String> _availableTasks = [];

  Map<String, dynamic>? _userData;

  // --- GPS & TA Variables ---
  Position? _currentPosition;
  String? _nominatimAddress;
  bool _isGettingLocation = false;
  final int _baseTA = 38; 

  @override
  void initState() {
    super.initState();
    
    // --- 0. EXTRACT WORKER DATA ---
    workerId = widget.preSelectedWorker['uid'] ?? widget.preSelectedWorker['workerId'] ?? '';
    workerName = widget.preSelectedWorker['name'] ?? 'Worker';
    workerPhone = widget.preSelectedWorker['phone'] ?? '';
    // Safely cast cw_data which holds the nested skill map (Category -> TaskSlug -> TaskDetails)
    workerCwData = widget.preSelectedWorker['cw_data'] as Map<String, dynamic>? ?? {};
    hourlyRate = (widget.preSelectedWorker['perHourCharge'] as num?)?.toDouble() ?? 500.0;


    final now = DateTime.now();
    _selectedDate = DateTime(now.year, now.month, now.day);
    
    // --- 1. INITIALIZE CATEGORIES ---
    if (workerCwData.isNotEmpty) {
      _availableCategories = workerCwData.keys.toList();
      _selectedServiceCategory = _availableCategories.first;
      _updateAvailableTasks(_selectedServiceCategory!);
    } else {
      // Fallback for workers without detailed cw_data
      _availableCategories = ['General'];
      _availableTasks = ['General Task'];
      _selectedServiceCategory = 'General';
      _selectedServiceTask = 'General Task';
    }

    _fetchUserData();
    _fetchAvailability();
    _checkPendingData();
  }
  
  void _updateAvailableTasks(String category) {
    if (workerCwData.containsKey(category)) {
      setState(() {
        final tasksMap = workerCwData[category] as Map<String, dynamic>;
        // Extract the actual task name from the nested map values
        _availableTasks = tasksMap.values.map((e) => e['name'].toString()).toList();
        _selectedServiceTask = _availableTasks.isNotEmpty ? _availableTasks.first : null;
      });
    }
  }


  @override
  void dispose() {
    _notesController.dispose();
    _addressController.dispose();
    _landmarkController.dispose();
    super.dispose();
  }

  // --- 1. Fetch User Data ---
  Future<void> _fetchUserData() async {
    if (widget.userId.isEmpty) return;
    try {
      final doc = await FirebaseFirestore.instance.collection('users').doc(widget.userId).get();
      if (doc.exists) {
        setState(() {
          _userData = doc.data();
          if (_addressController.text.isEmpty) {
            _addressController.text = _userData?['locality'] ?? ''; 
          }
        });
      }
    } catch (e) {
      debugPrint("Error fetching user: $e");
    }
  }

  // --- 2. Check Pending Data ---
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
          _selectedServiceTask = data['serviceTask'];
          _addressController.text = data['address'] ?? '';
          _landmarkController.text = data['landmark'] ?? '';
          
          // Re-populate tasks based on restored category
          if (_selectedServiceCategory != null) {
            _updateAvailableTasks(_selectedServiceCategory!);
          }
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

  // --- 3. Fetch Worker Availability ---
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
      }
    } catch (e) {
      debugPrint("Error fetching availability: $e");
    } finally {
      if (mounted) setState(() => _isFetchingSlots = false);
    }
  }

  // --- 4. Filter Slots Logic ---
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

  // --- 5. GPS & Reverse Geocoding Logic ---
  Future<void> _getNominatimAddress(double lat, double lon) async {
    try {
      final url = Uri.parse(
        'https://nominatim.openstreetmap.org/reverse?format=json&lat=$lat&lon=$lon&zoom=18&addressdetails=1'
      );
      final response = await http.get(url, headers: {
        'User-Agent': 'FlutterWorkerApp/1.0 (contact@example.com)' 
      });

      if (response.statusCode == 200) {
        final decoded = json.decode(response.body);
        setState(() {
          _nominatimAddress = decoded['display_name'];
        });
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
        throw Exception('Location services are disabled. Please enable GPS.');
      }

      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) {
          throw Exception('Location permissions are denied');
        }
      }
      
      if (permission == LocationPermission.deniedForever) {
        throw Exception('Location permissions are permanently denied.');
      }

      Position position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high
      );

      setState(() {
        _currentPosition = position;
      });

      await _getNominatimAddress(position.latitude, position.longitude);
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Location fetched successfully!"), backgroundColor: Colors.green)
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("$e"), backgroundColor: Colors.red)
        );
      }
    } finally {
      if (mounted) setState(() => _isGettingLocation = false);
    }
  }

  String _formatTime(int hour) {
    if (hour == 24 || hour == 0) return "12 AM";
    final now = DateTime.now();
    final dt = DateTime(now.year, now.month, now.day, hour % 24);
    return DateFormat.j().format(dt); 
  }

  // --- 6. Submit Booking ---
  Future<void> _confirmBooking() async {
    // Validation
    if (_selectedServiceCategory == null || _selectedServiceTask == null || _selectedStartHour == null) {
       ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Please select Category, Task, and Time.'), backgroundColor: Colors.orange));
      return;
    }
    if (_addressController.text.trim().isEmpty && _currentPosition == null) {
       ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Please enter an address or use GPS.'), backgroundColor: Colors.red));
      return;
    }

    // Auth Check
    final currentUser = FirebaseAuth.instance.currentUser;
    if (currentUser == null) {
      BookingCreationScreen.pendingBookingData = {
        'workerId': workerId, 
        'workerName': workerName, 
        'workerPhone': workerPhone,
        'serviceCategory': _selectedServiceCategory,
        'serviceTask': _selectedServiceTask,
        'date': _selectedDate, 
        'hour': _selectedStartHour,
        'hours': _hours, 
        'notes': _notesController.text, 
        'address': _addressController.text, 
        'landmark': _landmarkController.text
      };
      await Navigator.of(context).push(MaterialPageRoute(builder: (_) => const AuthScreen()));
      if (FirebaseAuth.instance.currentUser != null && mounted) Navigator.of(context).pop(); 
      return;
    }

    setState(() => _isLoading = true);
    try {
      // Fetch user data if missed
      if (_userData == null && widget.userId.isNotEmpty) {
          final userDoc = await FirebaseFirestore.instance.collection('users').doc(widget.userId).get();
          if (userDoc.exists) _userData = userDoc.data();
      }
      
      final userName = _userData?['name'] ?? 'Anonymous User';
      final userPhone = _userData?['phone'] ?? '';
      
      final calculatedWage = (hourlyRate * _hours).toInt();

      // --- ADDRESS PADDING LOGIC ---
      String finalAddress = _addressController.text.trim();
      if (_currentPosition != null) {
        finalAddress += "\n[GPS Coordinates: ${_currentPosition!.latitude}, ${_currentPosition!.longitude}]";
        if (_nominatimAddress != null && _nominatimAddress!.isNotEmpty) {
          finalAddress += "\n[GPS Detected Address: $_nominatimAddress]";
        }
      }

      // --- PAYLOAD CONSTRUCTION ---
      final bookingPayload = {
        'userId': currentUser.uid,
        'userPhone': userPhone,
        'userName': userName, 
        'workerId': workerId, 
        
        'userInfo': {'name': userName, 'phone': userPhone, 'email': _userData?['email'] ?? ''},
        'workerInfo': {'name': workerName, 'phone': workerPhone},

        'candidateWorkers': [workerId], 
        'date': DateFormat('yyyy-MM-dd').format(_selectedDate), 
        'startHour': _selectedStartHour!,
        'endHour': _selectedStartHour! + _hours,
        'wage': calculatedWage,
        'ta': _baseTA, 
        
        // NEW FIELDS
        'serviceCategory': _selectedServiceCategory,
        'serviceTask': _selectedServiceTask,
        'serviceType': _selectedServiceTask, // Used for backend indexing
        
        'location': {
          'locality': _userData?['locality'] ?? 'Unknown',
          'pin': _userData?['pin'] ?? '',
          'address': finalAddress,
          'landmark': _landmarkController.text.trim(),
          'latitude': _currentPosition?.latitude, 
          'longitude': _currentPosition?.longitude,
          'source': _currentPosition != null ? 'gps' : 'manual',
        },
        'notes': _notesController.text.trim(),
      };

      final response = await ApiClient.post('/create-booking', bookingPayload);
      
      if (response['ok'] == true) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Request Sent!'), backgroundColor: Colors.green));
        Navigator.of(context).pop();
      } else {
        throw Exception(response['error'] ?? 'Failed');
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red));
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final availableSlots = _getAvailableStartSlots();

    return Scaffold(
      appBar: AppBar(title: Text('Book $workerName')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // --- Service Category & Task (Updated Dropdowns) ---
            _buildSectionTitle('Service Details'),
            
            // Category Dropdown
            DropdownButtonFormField<String>(
              value: _selectedServiceCategory,
              items: _availableCategories.map((s) => DropdownMenuItem(value: s, child: Text(s))).toList(),
              onChanged: (v) {
                setState(() => _selectedServiceCategory = v);
                if (v != null) _updateAvailableTasks(v);
              },
              decoration: const InputDecoration(labelText: "Service Category", border: OutlineInputBorder()),
            ),
            const SizedBox(height: 16),
            
            // Task Dropdown
            DropdownButtonFormField<String>(
              value: _selectedServiceTask,
              items: _availableTasks.map((s) => DropdownMenuItem(value: s, child: Text(s))).toList(),
              onChanged: (v) => setState(() => _selectedServiceTask = v),
              decoration: const InputDecoration(labelText: "Specific Task", border: OutlineInputBorder()),
            ),
            const SizedBox(height: 16),
            
            // --- Location Section ---
            _buildSectionTitle('Location & Contact'),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _addressController,
                    decoration: const InputDecoration(
                      labelText: "Address / Locality",
                      hintText: "Flat 401, Sunshine Apts...",
                      prefixIcon: Icon(Icons.location_city),
                      border: OutlineInputBorder(),
                    ),
                    maxLines: 2,
                  ),
                ),
                const SizedBox(width: 10),
                Column(
                  children: [
                    IconButton.filledTonal(
                      onPressed: _isGettingLocation ? null : _getCurrentLocation,
                      icon: _isGettingLocation 
                        ? const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2))
                        : const Icon(Icons.my_location, color: Colors.blue),
                      tooltip: "Use Current GPS",
                    ),
                    const Text("Get GPS", style: TextStyle(fontSize: 10)),
                  ],
                ),
              ],
            ),
            
            if (_currentPosition != null)
              Padding(
                padding: const EdgeInsets.only(top: 5.0, bottom: 5.0),
                child: Row(
                  children: [
                    const Icon(Icons.check_circle, color: Colors.green, size: 16),
                    const SizedBox(width: 5),
                    Text(
                      "GPS Attached: ${_currentPosition!.latitude.toStringAsFixed(5)}, ${_currentPosition!.longitude.toStringAsFixed(5)}",
                      style: const TextStyle(color: Colors.green, fontWeight: FontWeight.bold, fontSize: 12),
                    ),
                  ],
                ),
              ),

            const SizedBox(height: 10),
            TextField(
              controller: _landmarkController,
              decoration: const InputDecoration(
                labelText: "Landmark",
                hintText: "Near SBI Bank...",
                prefixIcon: Icon(Icons.flag),
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 20),

            // --- Date Picker ---
            _buildSectionTitle('Date & Time'),
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
                  prefixIcon: Icon(Icons.calendar_today),
                  border: OutlineInputBorder(),
                ),
                child: Text(
                  DateFormat('EEEE, MMMM dd').format(_selectedDate),
                  style: const TextStyle(fontSize: 16),
                ),
              ),
            ),
            const SizedBox(height: 15),

            // --- Duration ---
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text("Duration (Hours):", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                Row(
                  children: [
                    IconButton(
                      onPressed: _hours > 1 ? () => setState(() { _hours--; _selectedStartHour = null; }) : null, 
                      icon: const Icon(Icons.remove_circle_outline)
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      decoration: BoxDecoration(color: Colors.grey[200], borderRadius: BorderRadius.circular(8)),
                      child: Text('$_hours', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
                    ),
                    IconButton(
                      onPressed: () => setState(() { _hours++; _selectedStartHour = null; }), 
                      icon: const Icon(Icons.add_circle_outline)
                    ),
                  ],
                )
              ],
            ),

            // --- Slots ---
            const SizedBox(height: 10),
            if (_isFetchingSlots) 
              const Center(child: LinearProgressIndicator())
            else if (availableSlots.isEmpty)
               Container(
                 padding: const EdgeInsets.all(10),
                 decoration: BoxDecoration(color: Colors.red[50], borderRadius: BorderRadius.circular(8)),
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
                    selectedColor: Colors.blue,
                    labelStyle: TextStyle(color: isSelected ? Colors.white : Colors.black),
                    onSelected: (s) => setState(() => _selectedStartHour = s ? hour : null),
                  );
                }).toList(),
              ),

            // --- Notes ---
            const SizedBox(height: 20),
            _buildSectionTitle('Additional Notes'),
            TextField(
              controller: _notesController,
              decoration: const InputDecoration(
                hintText: 'Describe the issue or special requests...',
                border: OutlineInputBorder()
              ),
              maxLines: 3,
            ),
            
            // --- Footer (Wage & TA) ---
            const SizedBox(height: 20),
            const Divider(thickness: 1),
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8.0),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                   Text("Travel Allowance (Base):", style: TextStyle(color: Colors.grey[700])),
                   Text("₹$_baseTA", style: const TextStyle(fontWeight: FontWeight.bold)),
                ],
              ),
            ),
            
            const SizedBox(height: 10),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _isLoading ? null : _confirmBooking,
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  backgroundColor: Colors.teal,
                  foregroundColor: Colors.white,
                ),
                child: _isLoading 
                  ? const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(color: Colors.white))
                  : const Text('Confirm Booking', style: TextStyle(fontSize: 18)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSectionTitle(String title) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8, top: 4),
      child: Text(title, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.teal)),
    );
  }
}