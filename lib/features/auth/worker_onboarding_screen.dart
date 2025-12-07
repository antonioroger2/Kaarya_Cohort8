// lib/features/auth/worker_onboarding_screen.dart

import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:firebase_auth/firebase_auth.dart';

class WorkerOnboardingScreen extends StatefulWidget {
  final String phoneNumber;
  final String uid;
  final Map<String, dynamic>? baseSignupData;

  const WorkerOnboardingScreen({
    Key? key, 
    required this.phoneNumber, 
    required this.uid,
    this.baseSignupData,
  }) : super(key: key);

  @override
  State<WorkerOnboardingScreen> createState() => _WorkerOnboardingScreenState();
}

class _WorkerOnboardingScreenState extends State<WorkerOnboardingScreen> {

  static const String baseUrl = "https://hawk4aynahtirk.pythonanywhere.com"; 
  static const String secretKey = "HiFhGDorJRULc1Z"; 

  // --- Controllers ---
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _pinController = TextEditingController();
  final _localityController = TextEditingController();
  final _rateController = TextEditingController();
  final _descController = TextEditingController();
  final _passwordController = TextEditingController();

  int _currentStep = 0;
  bool _isLoading = false;

  // --- Multi-Skill Data Structure ---
  // List of {category, task, cw_id, suggestedTools, aiSuggestedToolsFromProfile}
  List<Map<String, dynamic>> _detectedSkills = []; 
  // Map<cw_id, Set<tool_name>>: Stores user's selected canonical tools per skill.
  final Map<String, Set<String>> _selectedToolsMap = {};

  @override
  void initState() {
    super.initState();
    // Pre-populate controllers from baseSignupData
    if (widget.baseSignupData != null) {
      _nameController.text = widget.baseSignupData!['name'] ?? '';
      _pinController.text = widget.baseSignupData!['pin'] ?? '';
      _localityController.text = widget.baseSignupData!['locality'] ?? '';
      _rateController.text = widget.baseSignupData!['hourlyRate']?.toString() ?? '300';
      _passwordController.text = widget.baseSignupData!['password'] ?? '';
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _pinController.dispose();
    _localityController.dispose();
    _rateController.dispose();
    _descController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  void _showError(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: Colors.red),
    );
  }

  // --- API: Predict Skills (Step 2 to Step 3) ---
  Future<void> _analyzeProfile() async {
    if (_descController.text.trim().length < 5) {
       ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Please describe your work in more detail."), backgroundColor: Colors.orange));
       return;
    }
    
    setState(() => _isLoading = true);

    try {
      final response = await http.post(
        Uri.parse('$baseUrl/cw/predict-multi'), 
        headers: {"Content-Type": "application/json", "x-secret-key": secretKey},
        body: jsonEncode({"text": _descController.text}),
      ).timeout(const Duration(seconds: 30));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final List<dynamic> rawList = data['predictions'] ?? [];
        
        setState(() {
          _detectedSkills = List<Map<String, dynamic>>.from(rawList);
          
          _selectedToolsMap.clear();
          for (var skill in _detectedSkills) {
            String cwId = skill['cw_id'];
            // Use suggestedTools from the global CW registry (more standardized)
            List<dynamic> tools = skill['suggestedTools'] ?? []; 
            _selectedToolsMap[cwId] = tools.map((e) => e.toString()).toSet();
          }
          
          if (_detectedSkills.isNotEmpty) {
             _currentStep = 2; // Go to Verification if skills are found
          } else {
             throw Exception("AI found no distinct skills. Try describing your job more clearly.");
          }
        });
      } else {
        final errorBody = jsonDecode(response.body);
        throw Exception(errorBody['error'] ?? response.reasonPhrase);
      }
    } catch (e) {
      _showError("Analysis Error: $e");
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  // --- API: Complete Signup (Step 3 Finish) ---
  Future<void> _completeSignup() async {
    if (_detectedSkills.isEmpty) {
      _showError("Please analyze your profile first.");
      return;
    }
    
    bool hasTools = _selectedToolsMap.values.any((set) => set.isNotEmpty);
    if (!hasTools) {
       _showError("Please select at least one tool you own for one skill.");
       return;
    }
    
    if (!_formKey.currentState!.validate()) {
       _showError("Please check all fields in Step 1.");
       return;
    }


    setState(() => _isLoading = true);

    // Prepare the structured data for the backend
    List<Map<String, dynamic>> finalSkillsPayload = [];
    
    for (var skill in _detectedSkills) {
      String cwId = skill['cw_id'];
      finalSkillsPayload.add({
        "category": skill['category'],
        "task": skill['task'],
        // Send the list of selected, canonical tools back
        "myTools": _selectedToolsMap[cwId]?.toList() ?? [], 
      });
    }

    try {
      final response = await http.post(
        Uri.parse('$baseUrl/complete-signup'),
        headers: {"Content-Type": "application/json", "x-secret-key": secretKey},
        body: jsonEncode({
          "phone": widget.phoneNumber,
          "name": _nameController.text.trim(),
          "password": _passwordController.text, 
          "pin": _pinController.text.trim(),
          "locality": _localityController.text.trim(),
          "hourlyRate": int.tryParse(_rateController.text) ?? 300,
          "isWorker": true,
          "profileDescription": _descController.text.trim(), 
          // New structured field
          "verifiedSkills": finalSkillsPayload 
        }),
      ).timeout(const Duration(seconds: 30));

      if (response.statusCode == 200) {
        if (!mounted) return;
        // The backend creates the user, we must sign them in now.
        await FirebaseAuth.instance.signInWithEmailAndPassword(
          email: '${widget.phoneNumber}@kaaryaconnect.app',
          password: _passwordController.text,
        );
        
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Signup complete!"), backgroundColor: Colors.green));
        // Navigate to the main dashboard (AuthWrapper handles the final redirect)
        Navigator.of(context).popUntil((route) => route.isFirst);
        Navigator.of(context).pushReplacementNamed('/');
      } else {
        final errorBody = jsonDecode(response.body);
        throw Exception(errorBody['error'] ?? 'Signup failed');
      }
    } catch (e) {
      _showError("Signup Error: $e");
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  // --- UI Components: Step Builders ---

  Widget _buildStep1BasicInfo() {
    // Basic profile inputs
    return Form(
      key: _formKey,
      child: ListView( 
        padding: const EdgeInsets.only(top: 10),
        children: [
          const Text("1. Basic Profile Details", style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
          const SizedBox(height: 15),
          TextFormField(
            controller: _nameController, 
            decoration: const InputDecoration(labelText: "Full Name", border: OutlineInputBorder()),
            validator: (v) => v!.isEmpty ? "Required" : null,
          ),
          const SizedBox(height: 10),
          TextFormField(
            controller: _passwordController, 
            obscureText: true, 
            decoration: const InputDecoration(labelText: "Password (min 6 chars)", border: OutlineInputBorder()),
            validator: (v) => v!.length < 6 ? "Minimum 6 characters" : null,
          ),
          const SizedBox(height: 10),
          Row(children: [
            Expanded(child: TextFormField(
              controller: _pinController, 
              keyboardType: TextInputType.number, 
              maxLength: 6,
              decoration: const InputDecoration(labelText: "Pincode", counterText: "", border: OutlineInputBorder()),
              validator: (v) => v!.length != 6 ? "6 digits required" : null,
            )),
            const SizedBox(width: 10),
            Expanded(child: TextFormField(
              controller: _localityController, 
              decoration: const InputDecoration(labelText: "Locality", border: OutlineInputBorder()),
              validator: (v) => v!.isEmpty ? "Required" : null,
            )),
          ]),
          const SizedBox(height: 10),
          TextFormField(
            controller: _rateController, 
            keyboardType: TextInputType.number, 
            decoration: const InputDecoration(labelText: "Hourly Rate (₹)", border: OutlineInputBorder()),
            validator: (v) => (int.tryParse(v ?? '0') ?? 0) < 50 ? "Min ₹50" : null,
          ),
          const SizedBox(height: 20),
          ElevatedButton(
            onPressed: () {
              if (_formKey.currentState!.validate()) {
                setState(() => _currentStep = 1);
              }
            }, 
            child: const Text("Next: Describe Your Skills")
          )
        ],
      ),
    );
  }

  Widget _buildStep2Interview() {
    // AI analysis prompt
    return ListView(
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text("2. Describe Your Skills", style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
            TextButton(
              onPressed: () => setState(() => _currentStep = 0),
              child: const Text("Edit Step 1"),
            )
          ],
        ),
        const Padding(
          padding: EdgeInsets.symmetric(vertical: 10),
          child: Text("Tell us exactly what services you offer. The more detailed you are, the better our AI can categorize you. (e.g., 'I am a plumber who fixes taps and flushes, and an electrician who installs fans and repairs faulty wiring.')"),
        ),
        TextFormField(
          controller: _descController,
          maxLines: 4,
          decoration: const InputDecoration(
            border: OutlineInputBorder(), 
            hintText: "Describe your work here...",
          ),
        ),
        const SizedBox(height: 20),
        ElevatedButton.icon(
          icon: _isLoading 
            ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
            : const Icon(Icons.auto_awesome),
          label: Text(_isLoading ? "Analyzing..." : "Analyze Profile"),
          onPressed: _isLoading ? null : _analyzeProfile,
        ),
      ],
    );
  }

  Widget _buildStep3Verification() {
    // Skill and tool selection
    return Column(
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text("3. Verify Skills & Tools", style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
            TextButton(
              onPressed: () => setState(() => _currentStep = 1),
              child: const Text("Edit Step 2"),
            )
          ],
        ),
        const Padding(
          padding: EdgeInsets.symmetric(vertical: 10),
          child: Text("Confirm the detected tasks and select ONLY the tools you physically own for each job. This ensures you get accurate bookings."),
        ),
        Expanded(
          child: ListView.builder(
            itemCount: _detectedSkills.length,
            itemBuilder: (context, index) {
              final skill = _detectedSkills[index];
              final cwId = skill['cw_id'];
              final tools = List<String>.from(skill['suggestedTools'] ?? []); 
              
              return Card(
                margin: const EdgeInsets.only(bottom: 15),
                elevation: 3,
                child: ExpansionTile(
                  initiallyExpanded: index == 0, 
                  leading: CircleAvatar(child: Icon(_getIconForCategory(skill['category']))),
                  title: Text(skill['task'], style: const TextStyle(fontWeight: FontWeight.bold)),
                  subtitle: Text(skill['category']),
                  children: [
                    Padding(
                      padding: const EdgeInsets.all(16.0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text("Select Tools you own:", style: TextStyle(fontWeight: FontWeight.bold)),
                          const SizedBox(height: 8),
                          Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: tools.map((tool) {
                              if (!_selectedToolsMap.containsKey(cwId)) {
                                _selectedToolsMap[cwId] = {};
                              }
                              final isSelected = _selectedToolsMap[cwId]!.contains(tool);
                              return FilterChip(
                                label: Text(tool),
                                selected: isSelected,
                                selectedColor: Colors.green.shade100,
                                labelStyle: TextStyle(color: isSelected ? Colors.green.shade900 : Colors.black87),
                                onSelected: (val) {
                                  setState(() {
                                    if (val) {
                                      _selectedToolsMap[cwId]!.add(tool);
                                    } else {
                                      _selectedToolsMap[cwId]!.remove(tool);
                                    }
                                  });
                                },
                              );
                            }).toList(),
                          )
                        ],
                      ),
                    )
                  ],
                ),
              );
            },
          ),
        ),
        const SizedBox(height: 10),
        ElevatedButton(
          onPressed: _isLoading ? null : _completeSignup,
          style: ElevatedButton.styleFrom(minimumSize: const Size(double.infinity, 50)),
          child: Text(_isLoading ? "Saving..." : "Confirm & Finish Signup"),
        ),
      ],
    );
  }

  // --- Helper: Icon Selection ---
  IconData _getIconForCategory(String category) {
    final lowerCaseCategory = category.toLowerCase();
    if (lowerCaseCategory.contains("plumb")) return Icons.water_drop;
    if (lowerCaseCategory.contains("electr")) return Icons.electrical_services;
    if (lowerCaseCategory.contains("clean")) return Icons.cleaning_services;
    if (lowerCaseCategory.contains("carpenter")) return Icons.carpenter;
    if (lowerCaseCategory.contains("paint")) return Icons.format_paint;
    if (lowerCaseCategory.contains("cook")) return Icons.restaurant;
    return Icons.work;
  }

  // --- Main Build Method ---
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Worker Signup")),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: IndexedStack( 
          index: _currentStep,
          children: [
            _buildStep1BasicInfo(),
            _buildStep2Interview(),
            // Only build step 3 when data is ready
            if (_currentStep == 2) _buildStep3Verification(),
          ].whereType<Widget>().toList(), 
        )
      ),
    );
  }
}