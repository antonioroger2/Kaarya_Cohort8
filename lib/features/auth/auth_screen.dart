import 'dart:convert';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;
import 'package:karyaseva/core/api_client.dart';
import '../../core/design_tokens.dart';
import '../../core/footer.dart';
import 'worker_onboarding_screen.dart';

InputDecoration _proInputDecoration(String label, IconData icon) {
  return InputDecoration(
    labelText: label,
    prefixIcon: Icon(icon, color: Colors.grey.shade600),
    contentPadding: const EdgeInsets.symmetric(vertical: 16, horizontal: 12),
    border: OutlineInputBorder(
      borderRadius: BorderRadius.circular(12),
      borderSide: BorderSide(color: Colors.grey.shade300, width: 1.5),
    ),
    enabledBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(12),
      borderSide: BorderSide(color: Colors.grey.shade300, width: 1.5),
    ),
    focusedBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(12),
      borderSide: const BorderSide(color: AppDesignTokens.primary, width: 2),
    ),
    filled: true,
    fillColor: Colors.white,
  );
}

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

  final _passwordController = TextEditingController();
  final _phoneController = TextEditingController();
  final _nameController = TextEditingController();
  final _pinController = TextEditingController();

  List<String> _localities = [];
  String? _selectedLocality;

  @override
  void dispose() {
    _passwordController.dispose();
    _phoneController.dispose();
    _nameController.dispose();
    _pinController.dispose();
    super.dispose();
  }

  void _showError(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: Colors.redAccent, duration: const Duration(seconds: 4)),
    );
  }

  void _showSystemOffline() {
    if (!mounted) return;
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: const Text("System Offline", style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold)),
        content: const Text("Contact Developer. The system is currently offline or APIs are unavailable."),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(), child: const Text("OK")),
        ],
      ),
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
      final position = await Geolocator.getCurrentPosition(desiredAccuracy: LocationAccuracy.high);
      final reverseUrl = 'https://nominatim.openstreetmap.org/reverse?format=jsonv2&lat=${position.latitude}&lon=${position.longitude}&addressdetails=1';
      final reverseRes = await http.get(Uri.parse(reverseUrl), headers: {'User-Agent': 'KaaryaConnectApp'});
      if (reverseRes.statusCode != 200) throw Exception('Network Error');
      final reverseData = jsonDecode(reverseRes.body);
      final pincode = reverseData['address']?['postcode'];
      if (pincode == null) { setState(() => _pincodeError = 'GPS could not find a pincode'); return; }
      _pinController.text = pincode.toString();
      await _fetchLocalities(pincode.toString());
    } catch (e) {
      _showError('Error fetching location: $e');
    } finally {
      if (mounted) setState(() => _isLocationLoading = false);
    }
  }

  Future<void> _fetchLocalities(String pincode) async {
    setState(() { _localities = []; _selectedLocality = null; _pincodeError = null; });
    try {
      final res = await http.get(Uri.parse('https://api.postalpincode.in/pincode/$pincode'));
      final data = jsonDecode(res.body);
      if (data is List && data.isNotEmpty) {
        if (data[0]['Status'] == 'Error') { setState(() => _pincodeError = 'Invalid Pincode.'); return; }
        final offices = data[0]['PostOffice'] as List?;
        setState(() {
          _localities = offices?.map((e) => e['Name'].toString()).toList() ?? [];
          if (_localities.isNotEmpty) _selectedLocality = _localities.first;
        });
      }
    } catch (e) {
      setState(() => _pincodeError = 'Network error checking pincode');
    }
  }

  Future<void> _submitAuthForm() async {
    if (!_formKey.currentState!.validate()) return;

    if (_isLoginMode) {
      await _login();
    } else {
      if (_pincodeError != null || _localities.isEmpty) {
        _showError("Please enter a valid pincode.");
        return;
      }
      final phone = _phoneController.text.trim();
      if (_isWorker) {
        final signupData = {
          'password': _passwordController.text.trim(),
          'name': _nameController.text.trim(),
          'pin': _pinController.text.trim(),
          'locality': _selectedLocality ?? '',
          'hourlyRate': '300',
        };
        Navigator.of(context).push(MaterialPageRoute(
          builder: (context) => WorkerOnboardingScreen(phoneNumber: phone, uid: phone, baseSignupData: signupData),
        ));
      } else {
        await _completeUserSignup(phone);
      }
    }
  }

  Future<void> _completeUserSignup(String phone) async {
    setState(() => _isLoading = true);
    try {
      final payload = {
        'phone': phone,
        'password': _passwordController.text.trim(),
        'name': _nameController.text.trim(),
        'pin': _pinController.text.trim(),
        'locality': _selectedLocality ?? '',
        'isWorker': false,
      };
      final response = await ApiClient.post('/complete-signup', payload);
      if (response['ok'] == true) {
        await _login();
      } else {
        throw Exception(response['error'] ?? 'Failed to create profile');
      }
    } catch (e) {
      _showSystemOffline();
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _login() async {
    setState(() => _isLoading = true);
    try {
      final email = '${_phoneController.text.trim()}@kaaryaconnect.app';
      await FirebaseAuth.instance.signInWithEmailAndPassword(
        email: email,
        password: _passwordController.text,
      );
      if (mounted && Navigator.canPop(context)) Navigator.pop(context);
    } on FirebaseAuthException catch (e) {
      _showError(e.message ?? 'Login failed');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    String mainButtonText = _isLoginMode ? 'Login' : (_isWorker ? 'Continue to Onboarding' : 'Sign Up');

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: Text(
          _isLoginMode ? 'Login' : 'Sign Up',
          style: const TextStyle(
            fontWeight: FontWeight.w900,
            color: Colors.teal,
            fontSize: 18,
          ),
        ),
        backgroundColor: Colors.white,
        iconTheme: IconThemeData(color: Colors.black),
        elevation: 0,
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 400),
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
            child: Form(
              key: _formKey,
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const CircleAvatar(
                    radius: 40,
                    backgroundColor: AppDesignTokens.primary,
                    child: Icon(Icons.work, size: 40, color: Colors.white),
                  ),
                  const SizedBox(height: 20),
                  Text(
                    _isLoginMode ? 'Welcome Back!' : 'Join Our Network',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                      fontWeight: FontWeight.w800,
                      color: AppDesignTokens.primary,
                      fontSize: 28,
                    ),
                  ),
                  const SizedBox(height: 30),

                  if (!_isLoginMode) ...[
                    TextFormField(
                      controller: _nameController,
                      decoration: _proInputDecoration('Full Name', Icons.person_outline),
                      validator: (v) => v!.trim().isEmpty ? 'Please enter name' : null,
                    ),
                    const SizedBox(height: 16),
                  ],

                  TextFormField(
                    controller: _phoneController,
                    keyboardType: TextInputType.phone,
                    maxLength: 10,
                    decoration: _proInputDecoration('10-Digit Phone Number', Icons.phone_outlined).copyWith(counterText: ""),
                    validator: (v) => (v == null || !RegExp(r'^[0-9]{10}$').hasMatch(v)) ? 'Must be 10 digits' : null,
                  ),
                  const SizedBox(height: 16),

                  if (!_isLoginMode) ...[
                    Row(
                      children: [
                        Expanded(
                          child: TextFormField(
                            controller: _pinController,
                            keyboardType: TextInputType.number,
                            maxLength: 6,
                            decoration: _proInputDecoration('6-Digit Pincode', Icons.location_on_outlined).copyWith(
                              counterText: "",
                              errorText: _pincodeError,
                              suffixIcon: _isLocationLoading ? const Padding(padding: EdgeInsets.all(12.0), child: SizedBox(height: 10, width: 10, child: CircularProgressIndicator(strokeWidth: 2, color: AppDesignTokens.primary))) : null,
                            ),
                            onChanged: (val) {
                              if (val.length == 6) _fetchLocalities(val);
                            },
                          ),
                        ),
                        const SizedBox(width: 10),
                        Container(
                          decoration: BoxDecoration(color: AppDesignTokens.lightGrey, borderRadius: BorderRadius.circular(12)),
                          child: IconButton(
                            icon: const Icon(Icons.gps_fixed, color: AppDesignTokens.primary),
                            onPressed: _isLocationLoading ? null : _detectLocationAndFetchPincode,
                          ),
                        ),
                      ],
                    ),
                    if (_localities.isNotEmpty) ...[
                      const SizedBox(height: 16),
                      DropdownButtonFormField<String>(
                        value: _selectedLocality,
                        decoration: _proInputDecoration('Select Locality', Icons.map_outlined),
                        items: _localities.map((loc) => DropdownMenuItem(value: loc, child: Text(loc))).toList(),
                        onChanged: (val) => setState(() => _selectedLocality = val),
                        validator: (val) => val == null ? 'Required' : null,
                      ),
                    ],
                    const SizedBox(height: 16),
                  ],

                  TextFormField(
                    controller: _passwordController,
                    obscureText: true,
                    decoration: _proInputDecoration('Password', Icons.lock_outline),
                    validator: (v) => (v == null || v.length < 6) ? 'Min 6 characters' : null,
                  ),
                  
                  if (!_isLoginMode) ...[
                    const SizedBox(height: 16),
                    TextFormField(
                      obscureText: true,
                      decoration: _proInputDecoration('Confirm Password', Icons.lock_outline),
                      validator: (v) => (v != _passwordController.text) ? 'Passwords do not match' : null,
                    ),
                    const SizedBox(height: 20),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
                      decoration: BoxDecoration(color: AppDesignTokens.lightGrey, borderRadius: BorderRadius.circular(12)),
                      child: Row(
                        children: [
                          _buildToggleButton("I'm a User", !_isWorker, AppDesignTokens.aiBlue),
                          _buildToggleButton("I'm a Worker", _isWorker, AppDesignTokens.primary),
                        ],
                      ),
                    ),
                  ],

                  const SizedBox(height: 30),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: _isLoading ? null : _submitAuthForm,
                      style: ElevatedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        backgroundColor: _isLoginMode ? AppDesignTokens.aiBlue : AppDesignTokens.primary,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        elevation: 4,
                      ),
                      child: _isLoading
                          ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                          : Text(mainButtonText, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                    ),
                  ),

                  TextButton(
                    onPressed: () => setState(() {
                      _isLoginMode = !_isLoginMode;
                      _formKey.currentState?.reset();
                      _pinController.clear();
                      _localities = [];
                      _selectedLocality = null;
                      _pincodeError = null;
                    }),
                    child: Text(
                      _isLoginMode ? "Don't have an account? Sign Up" : "Already have an account? Login",
                      style: TextStyle(color: AppDesignTokens.aiBlue.withOpacity(0.8), fontWeight: FontWeight.w600),
                    ),
                  ),
                  const SizedBox(height: 32),
                  // Footer
                  const AppFooter(),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildToggleButton(String label, bool isActive, Color activeColor) {
    return Expanded(
      child: GestureDetector(
        onTap: () => setState(() => _isWorker = (label == "I'm a Worker")),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 12),
          decoration: BoxDecoration(
            color: isActive ? Colors.white : Colors.transparent,
            borderRadius: BorderRadius.circular(8),
            boxShadow: isActive ? [BoxShadow(color: Colors.black.withOpacity(0.08), blurRadius: 4)] : [],
          ),
          child: Center(
            child: Text(label, style: TextStyle(fontWeight: FontWeight.bold, color: isActive ? activeColor : AppDesignTokens.text1.withOpacity(0.6))),
          ),
        ),
      ),
    );
  }
}