// lib/features/auth/auth_screen.dart
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../core/theme.dart';

class AuthScreen extends StatefulWidget {
  const AuthScreen({super.key});

  @override
  State<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends State<AuthScreen> {
  final _formKey = GlobalKey<FormState>();
  bool _isLoginMode = true;
  final _passwordController = TextEditingController();
  final _phoneController = TextEditingController();
  final _nameController = TextEditingController();
  final _pinController = TextEditingController();
  bool _isWorker = false;
  bool _isLoading = false;

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
      SnackBar(content: Text(message), backgroundColor: Colors.redAccent),
    );
  }

  Future<void> _submitAuthForm() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }

    setState(() => _isLoading = true);

    try {
      if (_isLoginMode) {
        await _login();
      } else {
        await _signUp();
      }
    } on FirebaseAuthException catch (e) {
      _showError(e.message ?? 'An authentication error occurred.');
    } catch (e) {
      _showError('An unexpected error occurred: $e');
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _signUp() async {
    // Firebase Auth requires an email format, using a generated email with the phone number
    final email = '${_phoneController.text.trim()}@kaaryaconnect.app';
    final userCredential = await FirebaseAuth.instance.createUserWithEmailAndPassword(
      email: email,
      password: _passwordController.text,
    );
    final uid = userCredential.user!.uid;

    if (_isWorker) {
      await FirebaseFirestore.instance.collection('workers').doc(uid).set({
        'id': uid,
        'name': _nameController.text.trim(),
        'phone': _phoneController.text.trim(),
        'pin': _pinController.text.trim(),
        'altPhone': '',
        'availability': 'Y',
        'totalBookings': 0,
        'completedBookings': 0,
        'fourPlusRatings': 0,
        'avgRating': 0.0,
        'trustScore': 5.0,
        'workCategories': [],
        'idDetails': {'type': 'Aadhar', 'number': ''},
        'experience': 0,
        'profileDescription': '',
        'perHourCharge': 50,
        'perDayCharge': 400,
        'createdAt': Timestamp.now(),
      });
    } else {
      await FirebaseFirestore.instance.collection('users').doc(uid).set({
        'id': uid,
        'name': _nameController.text.trim(),
        'phone': _phoneController.text.trim(),
        'pin': _pinController.text.trim(),
        'altPhone': '',
        'email': '',
        'locality': '',
        'trustScore': 5.0,
        'userType': 'Standard',
        'createdAt': Timestamp.now(),
      });
    }
  }

  Future<void> _login() async {
    final email = '${_phoneController.text.trim()}@kaaryaconnect.app';
    await FirebaseAuth.instance.signInWithEmailAndPassword(
      email: email,
      password: _passwordController.text,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Kaarya Connect')),
      body: Center(
        child: DoodleBackground(
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

                  // Full Name Field (Signup only)
                  if (!_isLoginMode)
                    TextFormField(
                      controller: _nameController,
                      decoration: InputDecoration(
                        labelText: 'Full Name',
                        prefixIcon: const Icon(Icons.person_outline),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                      ),
                      validator: (value) => value!.trim().isEmpty ? 'Please enter your name' : null,
                    ),
                  if (!_isLoginMode) const SizedBox(height: 16),

                  // Phone Number Field
                  TextFormField(
                    controller: _phoneController,
                    keyboardType: TextInputType.phone,
                    decoration: InputDecoration(
                      labelText: '10-Digit Phone Number',
                      prefixIcon: const Icon(Icons.phone_outlined),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                    ),
                    validator: (value) {
                      if (value == null || value.trim().isEmpty) return 'Please enter a phone number';
                      if (value.length != 10) return 'Enter a valid 10-digit phone number';
                      return null;
                    },
                  ),
                  const SizedBox(height: 16),

                  // Pincode Field (Signup only)
                  if (!_isLoginMode)
                    TextFormField(
                      controller: _pinController,
                      keyboardType: TextInputType.number,
                      decoration: InputDecoration(
                        labelText: '6-Digit Pincode',
                        prefixIcon: const Icon(Icons.location_on_outlined),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                      ),
                      validator: (value) {
                        if (value == null || value.trim().isEmpty) return 'Please enter a pincode';
                        if (value.length != 6) return 'Enter a valid 6-digit pincode';
                        return null;
                      },
                    ),
                  const SizedBox(height: 16),

                  // Password Field
                  TextFormField(
                    controller: _passwordController,
                    obscureText: true,
                    decoration: InputDecoration(
                      labelText: 'Password',
                      prefixIcon: const Icon(Icons.lock_outline),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                    ),
                    validator: (value) {
                      if (value == null || value.isEmpty) return 'Please enter a password';
                      if (value.length < 6) return 'Password must be at least 6 characters';
                      return null;
                    },
                  ),

                  // Confirm Password Field (Signup only)
                  if (!_isLoginMode) const SizedBox(height: 16),
                  if (!_isLoginMode)
                    TextFormField(
                      obscureText: true,
                      decoration: InputDecoration(
                        labelText: 'Confirm Password',
                        prefixIcon: const Icon(Icons.lock_outline),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                      ),
                      validator: (value) {
                        if (value != _passwordController.text) return 'Passwords do not match';
                        return null;
                      },
                    ),

                  // User/Worker Switch (Signup only)
                  if (!_isLoginMode) const SizedBox(height: 20),
                  if (!_isLoginMode)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                      decoration: BoxDecoration(
                        color: Colors.indigo.withOpacity(0.05),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Text('I am a User'),
                          Switch(
                            value: _isWorker,
                            onChanged: (val) => setState(() => _isWorker = val),
                          ),
                          const Text('I am a Worker'),
                        ],
                      ),
                    ),

                  const SizedBox(height: 30),

                  // Submit Button
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: _isLoading ? null : _submitAuthForm,
                      style: ElevatedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 16),
                      ),
                      child: _isLoading
                          ? const SizedBox(
                              height: 20, width: 20,
                              child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                            )
                          : Text(_isLoginMode ? 'Login' : 'Sign Up', style: const TextStyle(fontSize: 16)),
                    ),
                  ),

                  // Toggle Login/Signup Button
                  TextButton(
                    onPressed: () => setState(() => _isLoginMode = !_isLoginMode),
                    child: Text(_isLoginMode
                        ? 'Don\'t have an account? Sign Up'
                        : 'Already have an account? Login'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
