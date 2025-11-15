// lib/features/user/booking_creation_screen.dart
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import '../../core/api_client.dart'; // Import the ApiClient

class BookingCreationScreen extends StatefulWidget {
  final String userId;
  final String workerId;
  final String workerName;
  final String workerPhone;
  // --- MODIFIED: Accept list of categories ---
  final List<Map<String, dynamic>> workCategories;

  const BookingCreationScreen({
    super.key, 
    required this.userId, 
    required this.workerId, 
    required this.workerName,
    required this.workerPhone,
    required this.workCategories, // Changed from String serviceType
  });

  @override
  State<BookingCreationScreen> createState() => _BookingCreationScreenState();
}

class _BookingCreationScreenState extends State<BookingCreationScreen> {
  DateTime _selectedDate = DateTime.now().add(const Duration(days: 1));
  TimeOfDay _selectedTime = const TimeOfDay(hour: 9, minute: 0);
  int _hours = 2;
  bool _isLoading = false;
  final _notesController = TextEditingController();
  
  // --- NEW: State for service selection ---
  String? _selectedServiceType;
  List<String> _availableServices = [];

  @override
  void initState() {
    super.initState();
    // Populate the list of available services from the worker's categories
    _availableServices = widget.workCategories
        .map((cat) => cat['mainCategory'] as String)
        .toList();
    
    // Default to the first service if available
    if (_availableServices.isNotEmpty) {
      _selectedServiceType = _availableServices.first;
    }
  }
  // --- END NEW ---

  Future<void> _confirmBooking() async {
    // --- NEW: Validation for service type ---
    if (_selectedServiceType == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Please select a service type'),
        backgroundColor: Colors.redAccent,
      ));
      return;
    }
    // --- END NEW ---

    setState(() => _isLoading = true);

    try {
      final workerSnap = await FirebaseFirestore.instance.collection('workers').doc(widget.workerId).get();
      final userSnap = await FirebaseFirestore.instance.collection('users').doc(widget.userId).get();

      if (!workerSnap.exists || !userSnap.exists) {
        throw Exception("User or worker not found.");
      }

      final workerData = workerSnap.data()!;
      final userData = userSnap.data()!;
      
      final hourlyRate = (workerData['perHourCharge'] ?? 500).toDouble();
      final wage = hourlyRate * _hours;
      
      final bookingDateTime = DateTime(
          _selectedDate.year, 
          _selectedDate.month, 
          _selectedDate.day, 
          _selectedTime.hour, 
          _selectedTime.minute
      );
      
      final startHour = _selectedTime.hour;
      final endHour = startHour + _hours;

      final bookingPayload = {
        'userId': widget.userId,
        'userPhone': userData['phone'] ?? '',
        'candidateWorkers': [widget.workerId], // Send as a list
        'date': DateFormat('yyyy-MM-dd').format(_selectedDate), // Server expects "YYYY-MM-DD"
        'startHour': startHour,
        'endHour': endHour,
        'wage': wage.toInt(),
        'ta': 0, // Travel Allowance, default to 0
        // --- MODIFIED: Use the selected service type ---
        'serviceType': _selectedServiceType,
        'location': {
          'locality': userData['locality'] ?? '',
          'pin': userData['pin'] ?? '',
          'address': userData['locality'] ?? '', // Add more address info if you have it
        },
        'notes': _notesController.text.trim(),
      };

      final response = await ApiClient.post('/create-booking', bookingPayload);

      if (!mounted) return;

      if (response['ok'] == true) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Booking request sent to worker!'),
          backgroundColor: Colors.green,
        ));
        Navigator.of(context).pop();
      } else {
        throw Exception(response['error'] ?? 'Failed to create booking');
      }

    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('Error: $e'),
        backgroundColor: Colors.redAccent,
      ));
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  void dispose() {
    _notesController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('Book ${widget.workerName}')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // --- NEW: Service Selection Dropdown ---
            const Text('Select Service', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
            const SizedBox(height: 12),
            Card(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                child: DropdownButtonFormField<String>(
                  value: _selectedServiceType,
                  items: _availableServices.map((String service) {
                    return DropdownMenuItem<String>(
                      value: service,
                      child: Text(service),
                    );
                  }).toList(),
                  onChanged: (newValue) {
                    setState(() {
                      _selectedServiceType = newValue;
                    });
                  },
                  decoration: const InputDecoration(
                    border: InputBorder.none,
                    prefixIcon: Icon(Icons.build),
                  ),
                ),
              ),
            ),
            // --- END NEW ---

            const SizedBox(height: 20),
            
            const Text('Select Date', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
            const SizedBox(height: 12),
            Card(
              child: ListTile(
                leading: const Icon(Icons.calendar_today),
                title: Text(DateFormat('MMMM dd, yyyy').format(_selectedDate)),
                trailing: const Icon(Icons.arrow_drop_down),
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
              ),
            ),
            
            const SizedBox(height: 20),
            
            const Text('Select Start Time', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
            const SizedBox(height: 12),
            Card(
              child: ListTile(
                leading: const Icon(Icons.schedule),
                title: Text(_selectedTime.format(context)),
                trailing: const Icon(Icons.arrow_drop_down),
                onTap: () async {
                  final picked = await showTimePicker(
                    context: context,
                    initialTime: _selectedTime,
                  );
                  if (picked != null) {
                    setState(() => _selectedTime = picked);
                  }
                },
              ),
            ),
            
            const SizedBox(height: 20),
            
            const Text('Select Duration (Hours)', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
            const SizedBox(height: 12),
            Card(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                child: Row(
                  children: [
                    IconButton(
                      onPressed: _hours > 1 ? () => setState(() => _hours--) : null,
                      icon: const Icon(Icons.remove_circle_outline),
                    ),
                    Expanded(
                      child: Text('$_hours hours', textAlign: TextAlign.center, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                    ),
                    IconButton(
                      onPressed: () => setState(() => _hours++),
                      icon: const Icon(Icons.add_circle_outline),
                    ),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 20),
            const Text('Notes (Optional)', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
            const SizedBox(height: 12),
            TextField(
              controller: _notesController,
              decoration: const InputDecoration(
                hintText: 'e.g. "Main tap is leaking", "Bring ladder"',
                border: OutlineInputBorder(),
              ),
              maxLines: 3,
            ),
            
            const SizedBox(height: 40),
            
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _isLoading ? null : _confirmBooking,
                style: ElevatedButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 16)),
                child: _isLoading
                    ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white,))
                    : const Text('Send Booking Request'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}