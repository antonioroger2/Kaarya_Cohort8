// lib/features/auth/auth_screen.dart
import 'dart:convert';
import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;

const String API_BASE_URL = "https://hawk4aynahtirk.pythonanywhere.com"; 
const String API_SECRET = "HiFhGDorJRULc1Z"; 

class AuthScreen extends StatefulWidget {
  const AuthScreen({super.key});

  @override
  State<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends State<AuthScreen> {
  final _formKey = GlobalKey<FormState>();
  
  bool _isLoginMode = true;
  bool _isWorker = false;
  bool _isLoading = false;
  bool _isLocationLoading = false; 
  String? _pincodeError; 
  String? _serverCorrelationId;

  final _passwordController = TextEditingController();
  final _phoneController = TextEditingController();
  final _nameController = TextEditingController();
  final _pinController = TextEditingController();
  final _otpController = TextEditingController();

  List<String> _localities = [];
  String? _selectedLocality;

  @override
  void dispose() {
    _passwordController.dispose();
    _phoneController.dispose();
    _nameController.dispose();
    _pinController.dispose();
    _otpController.dispose();
    super.dispose();
  }

  void _showError(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: Colors.redAccent, duration: const Duration(seconds: 4)),
    );
  }

  void _showSuccess(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: Colors.green),
    );
  }

  Future<void> _detectLocationAndFetchPincode() async {
    setState(() { _isLocationLoading = true; _pincodeError = null; });
    try {
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) { _showError('Please enable location services'); return; }
      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) { _showError('Location permission denied'); return; }
      }
      if (permission == LocationPermission.deniedForever) {
        _showError('Location permission permanently denied. Open settings?');
        return;
      }
      final position = await Geolocator.getCurrentPosition(desiredAccuracy: LocationAccuracy.high);
      final reverseUrl = 'https://nominatim.openstreetmap.org/reverse?format=jsonv2&lat=${position.latitude}&lon=${position.longitude}&addressdetails=1';
      final reverseRes = await http.get(Uri.parse(reverseUrl), headers: {'User-Agent': 'KaaryaConnectApp (dev@kaarya.app)'});
      if (reverseRes.statusCode != 200) throw Exception('Network Error');
      final reverseData = jsonDecode(reverseRes.body);
      final pincode = reverseData['address']?['postcode'];
      if (pincode == null) { setState(() => _pincodeError = 'GPS could not find a pincode'); return; }
      _pinController.text = pincode.toString();
      await _fetchLocalities(pincode.toString());
    } catch (e) { _showError('Error fetching location: $e');
    } finally { if (mounted) setState(() => _isLocationLoading = false); }
  }

  Future<void> _fetchLocalities(String pincode) async {
    setState(() { _localities = []; _selectedLocality = null; _pincodeError = null; });
    try {
      final res = await http.get(Uri.parse('https://api.postalpincode.in/pincode/$pincode'));
      final data = jsonDecode(res.body);
      if (data is List && data.isNotEmpty) {
        final status = data[0]['Status'];
        if (status == 'Error') { setState(() => _pincodeError = 'Invalid Pincode.'); return; }
        final offices = data[0]['PostOffice'] as List?;
        if (offices == null || offices.isEmpty) { setState(() => _pincodeError = 'No localities found.'); return; }
        setState(() {
          _localities = offices.map((e) => e['Name'].toString()).toList();
          if (_localities.isNotEmpty) _selectedLocality = _localities.first;
        });
      }
    } catch (e) { setState(() => _pincodeError = 'Network error checking pincode'); }
  }

  Future<void> _submitAuthForm() async {
    if (!_formKey.currentState!.validate()) return;

    if (_isLoginMode) {
      await _login();
    } else {
      if (_pincodeError != null) return; 
      if (_localities.isEmpty) { setState(() => _pincodeError = 'Enter a valid pincode first'); return; }
      if (_selectedLocality == null) { _showError('Please select a locality.'); return; }

      await _requestOtpForNewUser();
    }
  }

  Future<void> _requestOtpForNewUser() async {
    setState(() => _isLoading = true);
    final phone = _phoneController.text.trim();
    try {
      final response = await http.post(
        Uri.parse('$API_BASE_URL/generate-otp'),
        headers: { "Content-Type": "application/json", "x-secret-key": API_SECRET },
        body: jsonEncode({"phone": phone}), 
      ).timeout(const Duration(seconds: 15));

      final body = jsonDecode(response.body);
      if (response.statusCode == 200) {
        _serverCorrelationId = body['correlation_id'];
        if (mounted) _showOtpDialog(phone);
      } else {
        throw Exception("Server Error: ${body['error']}");
      }
    } catch (e) { _showError("Error: $e"); } finally { if (mounted) setState(() => _isLoading = false); }
  }

  void _showOtpDialog(String phone) {
    _otpController.clear();
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: const Text("Verify Phone"),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
              Text("Enter the 6-digit code sent to +91 $phone"),
              const SizedBox(height: 16),
              TextField(controller: _otpController, keyboardType: TextInputType.number, maxLength: 6, decoration: const InputDecoration(labelText: "OTP Code", counterText: "")),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text("Cancel")),
          ElevatedButton(onPressed: () { Navigator.pop(ctx); _verifyOtpAndCreateAccount(phone, _otpController.text.trim()); }, child: const Text("Verify & Sign Up"))
        ],
      ),
    );
  }

  Future<void> _verifyOtpAndCreateAccount(String phone, String code) async {
    if (code.length != 6) { _showError("OTP must be 6 digits"); return; }
    setState(() => _isLoading = true);
    try {
      final response = await http.post(
        Uri.parse('$API_BASE_URL/verify-otp-log'), 
        headers: { "Content-Type": "application/json", "x-secret-key": API_SECRET },
        body: jsonEncode({ "phone": phone, "code": code, "correlation_id": _serverCorrelationId }), 
      ).timeout(const Duration(seconds: 15));

      final body = jsonDecode(response.body);
      if (response.statusCode == 200 && body['valid'] == true) {
        await _serverCreateProfile(phone);
      } else { throw Exception(body['error'] ?? 'Invalid OTP'); }
    } catch (e) { _showError("$e"); } finally { if (mounted) setState(() => _isLoading = false); }
  }

  Future<void> _serverCreateProfile(String phone) async {
    try {
      final payload = {
        'phone': phone,
        'password': _passwordController.text.trim(),
        'name': _nameController.text.trim(),
        'pin': _pinController.text.trim(),
        'locality': _selectedLocality ?? '',
        'isWorker': _isWorker,
      };
      final response = await http.post(
        Uri.parse('$API_BASE_URL/complete-signup'),
        headers: { "Content-Type": "application/json", "x-secret-key": API_SECRET },
        body: jsonEncode(payload),
      ).timeout(const Duration(seconds: 20));

      final body = jsonDecode(response.body);
      if (response.statusCode == 200 && body['ok'] == true) {
        await _login(); // Auto login after signup
        // The _login function will handle navigation pop
      } else { throw Exception(body['error'] ?? 'Failed to create profile'); }
    } catch (e) { _showError("$e"); }
  }

  Future<void> _login() async {
    try {
      final email = '${_phoneController.text.trim()}@kaaryaconnect.app';
      await FirebaseAuth.instance.signInWithEmailAndPassword(
        email: email,
        password: _passwordController.text,
      );
      
      // --- KEY CHANGE: POP IF PUSHED ---
      // If this screen was pushed (e.g., from Booking Screen), pop it.
      if (mounted && Navigator.canPop(context)) {
        Navigator.pop(context);
      }
    } on FirebaseAuthException catch (e) {
      _showError(e.message ?? 'Login failed');
    } catch (e) {
      _showError("Error: $e");
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Kaarya Connect')),
      body: Center(
        child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Form(
              key: _formKey,
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const SizedBox(height: 20),
                  Text(
                    _isLoginMode ? 'Welcome Back!' : 'Join Our Network',
                    style: Theme.of(context).textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 30),

                  if (!_isLoginMode)
                    TextFormField(
                      controller: _nameController,
                      decoration: InputDecoration(labelText: 'Full Name', prefixIcon: const Icon(Icons.person_outline), border: OutlineInputBorder(borderRadius: BorderRadius.circular(8))),
                      validator: (v) => v!.trim().isEmpty ? 'Please enter name' : null,
                    ),
                  if (!_isLoginMode) const SizedBox(height: 16),

                  TextFormField(
                    controller: _phoneController,
                    keyboardType: TextInputType.phone,
                    maxLength: 10,
                    decoration: InputDecoration(labelText: '10-Digit Phone Number', counterText: "", prefixIcon: const Icon(Icons.phone_outlined), border: OutlineInputBorder(borderRadius: BorderRadius.circular(8))),
                    validator: (v) => (v == null || !RegExp(r'^[0-9]{10}$').hasMatch(v)) ? 'Must be 10 digits' : null,
                  ),
                  const SizedBox(height: 16),

                  if (!_isLoginMode)
                    Row(
                      children: [
                        Expanded(
                          child: TextFormField(
                            controller: _pinController,
                            keyboardType: TextInputType.number,
                            maxLength: 6,
                            decoration: InputDecoration(
                              labelText: '6-Digit Pincode', counterText: "", prefixIcon: const Icon(Icons.location_on_outlined), errorText: _pincodeError, 
                              suffixIcon: _isLocationLoading ? const Padding(padding: EdgeInsets.all(12.0), child: SizedBox(height: 10, width: 10, child: CircularProgressIndicator(strokeWidth: 2))) : null,
                              border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                            ),
                            validator: (v) => (v == null || v.length != 6) ? 'Must be 6 digits' : null,
                            onChanged: (val) {
                              if (_pincodeError != null) setState(() => _pincodeError = null);
                              if (val.length == 6) { _fetchLocalities(val); } else { setState(() { _localities = []; _selectedLocality = null; }); }
                            },
                          ),
                        ),
                        IconButton(icon: const Icon(Icons.gps_fixed), onPressed: _isLocationLoading ? null : _detectLocationAndFetchPincode),
                      ],
                    ),

                  if (!_isLoginMode)
                    Padding(
                      padding: const EdgeInsets.only(top: 16),
                      child: DropdownButtonFormField<String>(
                        value: _selectedLocality,
                        decoration: InputDecoration(labelText: 'Select Locality', border: OutlineInputBorder(borderRadius: BorderRadius.circular(8))),
                        items: _localities.map((loc) => DropdownMenuItem(value: loc, child: Text(loc))).toList(),
                        onChanged: (val) => setState(() => _selectedLocality = val),
                        validator: (val) => val == null ? 'Required' : null,
                      ),
                    ),
                  const SizedBox(height: 16),

                  TextFormField(
                    controller: _passwordController,
                    obscureText: true,
                    decoration: InputDecoration(labelText: 'Password', prefixIcon: const Icon(Icons.lock_outline), border: OutlineInputBorder(borderRadius: BorderRadius.circular(8))),
                    validator: (v) => (v == null || v.length < 6) ? 'Min 6 characters' : null,
                  ),

                  if (!_isLoginMode) const SizedBox(height: 16),
                  if (!_isLoginMode)
                    TextFormField(
                      obscureText: true,
                      decoration: InputDecoration(labelText: 'Confirm Password', prefixIcon: const Icon(Icons.lock_outline), border: OutlineInputBorder(borderRadius: BorderRadius.circular(8))),
                      validator: (v) => (v != _passwordController.text) ? 'Passwords do not match' : null,
                    ),

                  if (!_isLoginMode) const SizedBox(height: 20),
                  if (!_isLoginMode)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                      decoration: BoxDecoration(color: Theme.of(context).colorScheme.primary.withOpacity(0.05), borderRadius: BorderRadius.circular(8)),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Text('I am a User'),
                          Switch(value: _isWorker, onChanged: (val) => setState(() => _isWorker = val)),
                          const Text('I am a Worker'),
                        ],
                      ),
                    ),
                  const SizedBox(height: 30),

                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: _isLoading ? null : _submitAuthForm,
                      style: ElevatedButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 16)),
                      child: _isLoading
                          ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                          : Text(_isLoginMode ? 'Login' : 'Sign Up', style: const TextStyle(fontSize: 16)),
                    ),
                  ),

                  TextButton(
                    onPressed: () => setState(() => _isLoginMode = !_isLoginMode),
                    child: Text(_isLoginMode ? 'Don\'t have an account? Sign Up' : 'Already have an account? Login'),
                  ),
                ],
              ),
            ),
          ),
      ),
    );
  }
}