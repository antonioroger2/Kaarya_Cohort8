
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:intl/intl.dart';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;
import '../../core/api_client.dart'; 

class GeneralBookingScreen extends StatefulWidget {
  final String userId;

  const GeneralBookingScreen({
    super.key, 
    required this.userId, 
  });

  @override
  State<GeneralBookingScreen> createState() => _GeneralBookingScreenState();
}

class _GeneralBookingScreenState extends State<GeneralBookingScreen> {
  
  final double _defaultHourlyRate = 400.0; 
  final int workingStartHour = 0; 
  final int workingEndHour = 24;  
  final int _minNotesLength = 20; 
    DateTime _selectedDate = DateTime.now(); 
  int? _selectedStartHour; 
  int _hours = 2;
  bool _isLoading = false;
  
    final _notesController = TextEditingController();
  final _addressController = TextEditingController(); 
  final _landmarkController = TextEditingController(); 
  final _rateController = TextEditingController();

  Map<String, dynamic>? _userData;
    final Set<int> _availableGeneralSlots = List.generate(24, (index) => index).toSet(); 
  
    Position? _currentPosition;
  String? _nominatimAddress;
  bool _isGettingLocation = false;
  final int _baseTA = 38; 

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
    _rateController.dispose();
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

    List<int> _getAvailableStartSlots() {
    List<int> slots = [];
    final now = DateTime.now();
    final minBookingtime = now.add(const Duration(hours: 1));
    
    for (int hour = workingStartHour; hour < workingEndHour; hour++) {
      if (hour + _hours > workingEndHour) continue;
      
      bool isSlotBlockAvailable = true;
      for (int i = 0; i < _hours; i++) {
        if (!_availableGeneralSlots.contains(hour + i)) { isSlotBlockAvailable = false; break; }
      }
      if (!isSlotBlockAvailable) continue;
      
      final slotDateTime = DateTime(_selectedDate.year, _selectedDate.month, _selectedDate.day, hour);
      if (DateUtils.isSameDay(_selectedDate, now)) {
        if (slotDateTime.isBefore(minBookingtime)) continue;
      }
      slots.add(hour);
    }
    return slots;
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
      
      Position position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high
      );

      setState(() {
        _currentPosition = position;
      });

            try {
         final url = Uri.parse('https://nominatim.openstreetmap.org/reverse?format=json&lat=${position.latitude}&lon=${position.longitude}&addressdetails=1');        
          final response = await http.get(url, headers: {'User-Agent': 'FlutterWorkerApp/1.0 (contact@example.com)'});
         if (response.statusCode == 200) {
            final decoded = json.decode(response.body);
            setState(() { _nominatimAddress = decoded['display_name']; });
         }
      } catch (e) {
         debugPrint("Reverse Geocoding Failed: $e");
      }
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Location fetched successfully!"), backgroundColor: Colors.green)
        );
      }
    } catch (e) {
      if (mounted) {
        _showError("$e");
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

    Future<void> _confirmBooking() async {
        if (_selectedStartHour == null) {
       _showError('Please select a Time slot.');
      return;
    }
        if (_notesController.text.trim().length < _minNotesLength) {
       _showError('Please describe your job in more detail (min $_minNotesLength characters) for accurate matching.');
      return;
    }
    if (_addressController.text.trim().isEmpty && _currentPosition == null) {
       _showError('Please enter an address or use GPS.');
      return;
    }

    final currentUser = FirebaseAuth.instance.currentUser;
    if (currentUser == null) {
      _showError('Please login to submit a job request.');
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
      final currentHourlyRate = double.tryParse(_rateController.text) ?? _defaultHourlyRate;
      final calculatedWage = (currentHourlyRate * _hours).toInt();
      final jobDescription = _notesController.text.trim();

            final bookingPayload = {
        'userId': currentUser.uid,
        'userPhone': userPhone,
        'userName': userName, 
        
                'candidateWorkers': [], 

        'userInfo': {'name': userName, 'phone': userPhone, 'email': _userData?['email'] ?? ''},

        'date': DateFormat('yyyy-MM-dd').format(_selectedDate), 
        'startHour': _selectedStartHour!,
        'endHour': _selectedStartHour! + _hours,
        'wage': calculatedWage,
        'ta': _baseTA, 
        
                        'serviceType': jobDescription, 
        'serviceCategory': "General", 
        
        'location': {
          'locality': _userData?['locality'] ?? 'Unknown',
          'pin': _userData?['pin'] ?? '',
          'address': _addressController.text.trim(),
          'db_address': _nominatimAddress ?? _addressController.text.trim(),
          'landmark': _landmarkController.text.trim(),
          'lat': _currentPosition?.latitude, 
          'lng': _currentPosition?.longitude,
          'source': _currentPosition != null ? 'gps' : 'manual',
        },
        'notes': jobDescription,
      };

            final response = await ApiClient.post('/create-booking', bookingPayload);
      
      if (response['ok'] == true) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Request Sent to Top ${response['matched']} Matches!'), backgroundColor: Colors.green));
        Navigator.of(context).pop();
      } else {
        throw Exception(response['error'] ?? 'Failed');
      }
    } catch (e) {
      if (mounted) {
        _showError('Error: $e');
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _showError(String message) {
     if (!mounted) return;
     ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(message), backgroundColor: Colors.red)
     );
  }

  Widget _buildSectionTitle(String title) {
    return Padding(
              padding: const EdgeInsets.only(bottom: 8, top: 4),
              child: Text(title, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.teal)),
            );
  }


  @override
  Widget build(BuildContext context) {
    final availableSlots = _getAvailableStartSlots();

    return Scaffold(
      appBar: AppBar(title: const Text('New General Job Request')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
                        _buildSectionTitle('Detailed Job Description'),
            
                        TextField(
              controller: _notesController,
              decoration: InputDecoration(
                hintText: 'Describe your issue (e.g., "My kitchen tap is leaking and needs a new washer.").',
                labelText: 'Job Description (Min $_minNotesLength chars)',
                prefixIcon: const Icon(Icons.description),
                border: const OutlineInputBorder()
              ),
              maxLines: 4,
            ),
            const SizedBox(height: 20),

                        _buildSectionTitle('Estimated Hourly Rate (for wage calculation)'),
            TextFormField(
              controller: _rateController, 
              keyboardType: TextInputType.number, 
              decoration: const InputDecoration(labelText: "Hourly Rate (₹)", border: OutlineInputBorder()),
              validator: (v) => (double.tryParse(v ?? '0') ?? 0) < 50 ? "Min ₹50" : null,
            ),
            const SizedBox(height: 20),
            
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

                        const SizedBox(height: 10),
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
            
                        const SizedBox(height: 40),
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
                  : const Text('Send Job Request to Top Matches', style: TextStyle(fontSize: 18)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}