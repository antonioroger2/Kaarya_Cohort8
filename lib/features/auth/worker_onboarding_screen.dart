// lib/features/auth/worker_onboarding_screen.dart

import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart'; // Needed for input formatters
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
  
  // --- Validation Constants ---
  static const int minDescriptionWords = 60; 

  // --- Controllers & Keys ---
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
     // Listener for word count in step 2
    _descController.addListener(_updateWordCount);
  }

  @override
  void dispose() {
    _nameController.dispose();
    _pinController.dispose();
    _localityController.dispose();
    _rateController.dispose();
    _descController.removeListener(_updateWordCount);
    _descController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  // --- Helper Methods ---

  void _updateWordCount() {
    final text = _descController.text;
    // Simple word count: split by spaces, filter empty strings
    final words = text.trim().split(RegExp(r'\s+')).where((s) => s.isNotEmpty);
    // Force rebuild to update word counter text
    setState(() {
      // Intentionally empty setState to trigger rebuild for counter visibility
    });
  }

  int get _currentWordCount {
    final text = _descController.text;
    return text.trim().split(RegExp(r'\s+')).where((s) => s.isNotEmpty).length;
  }

  String? _validateDescription(String? value) {
    if (value == null || value.isEmpty) {
      return 'Professional summary is required.';
    }
    if (_currentWordCount < minDescriptionWords) {
      return 'Minimum $minDescriptionWords words required. (Current: $_currentWordCount)';
    }
    return null;
  }

  void _showError(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: Colors.red),
    );
  }

  // --- API: Predict Skills (Step 1 to Step 2) ---
  Future<void> _analyzeProfile() async {
    if (!_formKey.currentState!.validate() || _validateDescription(_descController.text) != null) {
       _showError("Please correct the highlighted fields and meet the 60-word minimum.");
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
        
        // --- Data Mapping and Initialization ---
        _detectedSkills.clear();
        _selectedToolsMap.clear();

        for (var rawSkill in rawList) {
          final skill = Map<String, dynamic>.from(rawSkill);
          String cwId = skill['cw_id'];
          // Ensure suggestedTools is treated as List<String>
          List<String> tools = List<String>.from(skill['suggestedTools'] ?? []); 
          
          _detectedSkills.add(skill);
          // Initialize selected tools with suggested tools for convenience
          _selectedToolsMap[cwId] = tools.toSet();
        }
        
        if (_detectedSkills.isNotEmpty) {
           setState(() {
             _currentStep = 2; // Go to Verification if skills are found
           });
        } else {
           throw Exception("AI found no distinct skills. Try describing your job more clearly.");
        }
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

  // --- API: Complete Signup (Step 2 Finish) ---
  Future<void> _completeSignup() async {
    if (_detectedSkills.isEmpty) {
      _showError("Profile analysis failed. Please go back and re-analyze your description.");
      return;
    }
    
    // Check if at least one tool is selected for the ENTIRE profile
    bool hasTools = _selectedToolsMap.values.any((set) => set.isNotEmpty);
    if (!hasTools) {
       _showError("You must select at least one tool you own across all your skills.");
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
          "verifiedSkills": finalSkillsPayload 
        }),
      ).timeout(const Duration(seconds: 30));

      if (response.statusCode == 200) {
        if (!mounted) return;
        
        // 1. Sign in the newly created user
        await FirebaseAuth.instance.signInWithEmailAndPassword(
          email: '${widget.phoneNumber}@kaaryaconnect.app',
          password: _passwordController.text,
        );
        
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Signup complete! Welcome!"), backgroundColor: Colors.green));
        
        // 2. Navigate away
        Navigator.of(context).popUntil((route) => route.isFirst);
        // Assuming your main app handles redirection based on Auth state.
        // If not, use pushReplacementNamed:
        // Navigator.of(context).pushReplacementNamed('/home'); 
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
    // Incorporates Step 1 (Basic Info) and Step 2 (Description/Analysis Trigger)
    
    int wordCount = _currentWordCount;
    final wordCountColor = wordCount >= minDescriptionWords ? Colors.green.shade700 : Colors.red.shade700;

    return Form(
      key: _formKey,
      child: ListView( 
        padding: const EdgeInsets.only(top: 10),
        children: [
          const Text("1. Basic Profile & Rate", style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
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
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
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
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            decoration: const InputDecoration(labelText: "Hourly Rate (₹)", border: OutlineInputBorder()),
            validator: (v) => (int.tryParse(v ?? '0') ?? 0) < 50 ? "Min ₹50" : null,
          ),
          const SizedBox(height: 30),

          // --- Description Section (Professional Requirement) ---
          const Text("2. Professional Summary *", style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 10),
            child: Text("Describe your services in detail (experience, specialty, quality commitment) for accurate job matching. Example: 'I am a highly skilled plumber with 10 years experience focusing on tap repair and water heater installation. My commitment is to ensure quick, clean, and reliable service every time.'"),
          ),
          TextFormField(
            controller: _descController,
            maxLines: 5,
            decoration: InputDecoration(
              border: const OutlineInputBorder(), 
              hintText: "Enter your professional summary...",
              errorMaxLines: 2,
            ),
            // Use local validation method
            validator: _validateDescription, 
          ),
          const SizedBox(height: 8),
          // Word Count Indicator
          Align(
            alignment: Alignment.centerRight,
            child: Text(
              'Words: $wordCount / $minDescriptionWords minimum',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: wordCountColor,
              ),
            ),
          ),
          const SizedBox(height: 20),
          ElevatedButton.icon(
            onPressed: _isLoading ? null : _analyzeProfile,
            icon: _isLoading 
              ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
              : const Icon(Icons.auto_awesome),
            label: Text(_isLoading ? "Analyzing Profile..." : "Analyze & Verify Skills"),
            style: ElevatedButton.styleFrom(minimumSize: const Size(double.infinity, 50)),
          ),
        ],
      ),
    );
  }

  Widget _buildStep2Verification() {
    // Skill and tool selection (renamed to Step 2)
    return Column(
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text("2. Verify Detected Skills & Tools", style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
            TextButton(
              onPressed: () => setState(() => _currentStep = 0),
              child: const Text("Edit Description"),
            )
          ],
        ),
        const Padding(
          padding: EdgeInsets.symmetric(vertical: 10),
          child: Text("✅ AI detected the following service categories. Confirm they are correct and select ONLY the tools you physically own for each job."),
        ),
        Expanded(
          // Ensure ListView is correctly constrained by Expanded
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
                  leading: CircleAvatar(backgroundColor: Colors.blue.shade50, child: Icon(_getIconForCategory(skill['category']), color: Colors.blue)),
                  title: Text(skill['task'], style: const TextStyle(fontWeight: FontWeight.bold)),
                  subtitle: Text(skill['category']),
                  children: [
                    Padding(
                      padding: const EdgeInsets.all(16.0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text("Select Tools YOU OWN:", style: TextStyle(fontWeight: FontWeight.bold)),
                          const SizedBox(height: 8),
                          Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: tools.map((tool) {
                              // Ensure the key exists before checking/updating
                              if (!_selectedToolsMap.containsKey(cwId)) {
                                _selectedToolsMap[cwId] = <String>{};
                              }
                              final isSelected = _selectedToolsMap[cwId]!.contains(tool);
                              return FilterChip(
                                label: Text(tool),
                                selected: isSelected,
                                selectedColor: Colors.lightGreen.shade200,
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
          style: ElevatedButton.styleFrom(minimumSize: const Size(double.infinity, 50), backgroundColor: Colors.green),
          child: Text(_isLoading ? "Completing Setup..." : "Confirm & Finish Signup"),
        ),
        const SizedBox(height: 10),
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
      appBar: AppBar(title: const Text("Worker Profile Setup")),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        // Use a Column/IndexedStack structure that allows Expanded to work correctly
        child: Column(
          children: [
            if (_currentStep == 0) Expanded(child: _buildStep1BasicInfo()),
            if (_currentStep == 2) Expanded(child: _buildStep2Verification()),
            
            // Handle the case when Step 2 analysis fails (no skills detected)
            if (_currentStep == 1) ...[
              const Text("Analysis failed, returning to step 1...", style: TextStyle(color: Colors.red)),
              ElevatedButton(
                onPressed: () => setState(() => _currentStep = 0),
                child: const Text("Go Back"),
              )
            ]
          ],
        )
      ),
    );
  }
}