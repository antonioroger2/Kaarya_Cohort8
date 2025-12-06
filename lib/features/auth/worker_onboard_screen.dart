// lib/features/auth/worker_onboarding_screen.dart

import 'dart:convert'; // REQUIRED for JSON encoding/decoding
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http; // Required for API calls

class WorkerOnboardingScreen extends StatefulWidget {
  final String phoneNumber;
  final String uid;
  final Map<String, dynamic>? baseSignupData;

  const WorkerOnboardingScreen({Key? key, required this.phoneNumber, required this.uid,this.baseSignupData,}) : super(key: key);

  @override
  State<WorkerOnboardingScreen> createState() => _WorkerOnboardingScreenState();
}

class _WorkerOnboardingScreenState extends State<WorkerOnboardingScreen> {

  // IMPORTANT: Ensure this base URL matches your running Python server instance
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
  List<Map<String, dynamic>> _detectedSkills = []; 
  // Map<cw_id, Set<tool_name>>: Stores user's selected tools per skill.
  final Map<String, Set<String>> _selectedToolsMap = {};

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

  // --- API: Predict Skills (Step 2 to Step 3) ---
  Future<void> _analyzeProfile() async {
    if (!_formKey.currentState!.validate()) return; // Re-validate step 1 data here just in case

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
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final List<dynamic> rawList = data['predictions'];
        
        setState(() {
          _detectedSkills = List<Map<String, dynamic>>.from(rawList);
          
          // Initialize the selected tools map: pre-select all suggested tools
          _selectedToolsMap.clear();
          for (var skill in _detectedSkills) {
            String id = skill['cw_id'];
            // Handles both 'suggestedTools' from global CW and 'aiSuggestedToolsFromProfile' (if sent by backend)
            List<dynamic> tools = skill['suggestedTools'] ?? []; 
            _selectedToolsMap[id] = tools.map((e) => e.toString()).toSet();
          }
          
          if (_detectedSkills.isNotEmpty) {
             _currentStep = 2; // Go to Verification if skills are found
          } else {
             throw Exception("AI found no distinct skills. Try describing your job more clearly.");
          }
        });
      } else {
        throw Exception("AI Analysis Failed: ${response.reasonPhrase}");
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Analysis Error: $e"), backgroundColor: Colors.red));
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  // --- API: Complete Signup (Step 3 Finish) ---
  Future<void> _completeSignup() async {
    if (_detectedSkills.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Please analyze your profile first."), backgroundColor: Colors.red));
      return;
    }
    
    // Check if any tools are selected
    bool hasTools = _selectedToolsMap.values.any((set) => set.isNotEmpty);
    if (!hasTools) {
       ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Please select at least one tool you own for one skill."), backgroundColor: Colors.orange));
       return;
    }

    setState(() => _isLoading = true);

    // Prepare the structured data for the backend
    List<Map<String, dynamic>> finalSkillsPayload = [];
    
    for (var skill in _detectedSkills) {
      String id = skill['cw_id'];
      finalSkillsPayload.add({
        "category": skill['category'],
        "task": skill['task'],
        "myTools": _selectedToolsMap[id]?.toList() ?? [], // Send only verified tools
      });
    }

    try {
      final response = await http.post(
        Uri.parse('$baseUrl/complete-signup'),
        headers: {"Content-Type": "application/json", "x-secret-key": secretKey},
        body: jsonEncode({
          "phone": widget.phoneNumber,
          "name": _nameController.text,
          "password": _passwordController.text, // Warning: Should use Firebase Auth securely
          "pin": _pinController.text,
          "locality": _localityController.text,
          "hourlyRate": int.tryParse(_rateController.text) ?? 300,
          "isWorker": true,
          "profileDescription": _descController.text, // Include description for profile
          "verifiedSkills": finalSkillsPayload // Structured list sent to backend
        }),
      );

      if (response.statusCode == 200) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Signup complete! Redirecting..."), backgroundColor: Colors.green));
        // Success - navigate to the worker dashboard/home
        Navigator.of(context).pushReplacementNamed('/worker-home');
      } else {
        final errorBody = jsonDecode(response.body);
        throw Exception(errorBody['error'] ?? 'Signup failed');
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Signup Error: $e"), backgroundColor: Colors.red));
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  // --- UI Components: Step Builders ---

  Widget _buildStep1BasicInfo() {
    return Form(
      key: _formKey,
      child: ListView( // Use ListView for scrolling if keyboard pops up
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
              decoration: const InputDecoration(labelText: "Pincode", border: OutlineInputBorder()),
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
    return ListView(
      children: [
        const Text("2. Describe Your Skills", style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
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
        const SizedBox(height: 20),
        TextButton(
          onPressed: () => setState(() => _currentStep = 0),
          child: const Text("Go Back"),
        )
      ],
    );
  }

  Widget _buildStep3Verification() {
    return Column(
      children: [
        const Text("3. Verify Skills & Tools", style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
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
              final tools = List<String>.from(skill['suggestedTools']);
              
              return Card(
                margin: const EdgeInsets.only(bottom: 15),
                elevation: 3,
                child: ExpansionTile(
                  initiallyExpanded: true,
                  leading: CircleAvatar(child: Icon(_getIconForCategory(skill['category']))),
                  title: Text(skill['task'], style: const TextStyle(fontWeight: FontWeight.bold)),
                  subtitle: Text(skill['category']),
                  children: [
                    Padding(
                      padding: const EdgeInsets.all(8.0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text("Select Tools you own:", style: TextStyle(fontWeight: FontWeight.bold)),
                          Wrap(
                            spacing: 8,
                            children: tools.map((tool) {
                              final isSelected = _selectedToolsMap[cwId]!.contains(tool);
                              return FilterChip(
                                label: Text(tool),
                                selected: isSelected,
                                selectedColor: Colors.green.shade100,
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
        TextButton(
          onPressed: () => setState(() => _currentStep = 1),
          child: const Text("Go Back to Description"),
        )
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
    return Icons.work;
  }

  // --- Main Build Method ---
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Worker Signup")),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: IndexedStack( // Use IndexedStack to preserve state between steps
          index: _currentStep,
          children: [
            _buildStep1BasicInfo(),
            _buildStep2Interview(),
            if (_currentStep == 2) _buildStep3Verification(),
          ],
        )
      ),
    );
  }
}