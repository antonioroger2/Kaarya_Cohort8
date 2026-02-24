


import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart'; 
import 'package:http/http.dart' as http;
import 'package:firebase_auth/firebase_auth.dart';
import 'package:intl/intl.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart'; 

class WorkerOnboardingScreen extends StatefulWidget {
  final String phoneNumber;
  final String uid;
  final Map<String, dynamic>? baseSignupData;

  const WorkerOnboardingScreen({
    super.key,
    required this.phoneNumber,
    required this.uid,
    this.baseSignupData,
  });

  @override
  State<WorkerOnboardingScreen> createState() => _WorkerOnboardingScreenState();
}



class AppColors {
  static const Color primaryTeal = Color(0xFF008080); 
  static const Color secondaryTeal = Color(0xFF4DB6AC); 
  static const Color primaryBackground = Color(0xFFF8F9FA);
  static const Color secondaryBackground = Colors.white;
  static const Color errorRed = Color(0xFFD32F2F);
  static const Color successGreen = Color(0xFF388E3C);
}

class _WorkerOnboardingScreenState extends State<WorkerOnboardingScreen> {

  static const String baseUrl = "https://hawk4aynahtirk.pythonanywhere.com";
  static String get secretKey => dotenv.env['API_SECRET_KEY'] ?? '';

  
  static const int minDescriptionWords = 60;

  
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _pinController = TextEditingController();
  final _localityController = TextEditingController();
  final _rateController = TextEditingController();
  final _descController = TextEditingController();
  final _passwordController = TextEditingController();

  
  int _currentStep = 0;
  bool _isLoading = false;

  
  
  final List<Map<String, dynamic>> _detectedSkills = [];
  
  final Map<String, Set<String>> _selectedToolsMap = {};

  @override
  void initState() {
    super.initState();
    
    if (widget.baseSignupData != null) {
      _nameController.text = widget.baseSignupData!['name'] ?? '';
      _pinController.text = widget.baseSignupData!['pin'] ?? '';
      _localityController.text = widget.baseSignupData!['locality'] ?? '';
      _rateController.text = widget.baseSignupData!['hourlyRate']?.toString() ?? '300';
      _passwordController.text = widget.baseSignupData!['password'] ?? '';
    }
     
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

  

  void _updateWordCount() {
    
    if (mounted) setState(() {});
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
      return 'Minimum $minDescriptionWords words required.';
    }
    return null;
  }

  String _formatCurrency(num val) {
    final formatter = NumberFormat.currency(locale: 'en_IN', symbol: '₹', decimalDigits: 0);
    return formatter.format(val);
  }

  void _showError(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: AppColors.errorRed),
    );
  }

  
  Future<void> _analyzeProfile() async {
    
    if (!_formKey.currentState!.validate() || _validateDescription(_descController.text) != null) {
       _showError("Please fill all fields and ensure the description meets the 60-word minimum.");
       return;
    }

    setState(() => _isLoading = true);

    try {
      final response = await http.post(
        Uri.parse('$baseUrl/cw/predict-multi'),
        headers: {"Content-Type": "application/json", "x-secret-key": secretKey},
        body: jsonEncode({"text": _descController.text}),
      ).timeout(const Duration(seconds: 120));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final List<dynamic> rawList = data['predictions'] ?? [];

        
        _detectedSkills.clear();
        _selectedToolsMap.clear();

        for (var rawSkill in rawList) {
          final skill = Map<String, dynamic>.from(rawSkill);
          String cwId = skill['cw_id'];
          List<String> tools = List<String>.from(skill['suggestedTools'] ?? []);

          _detectedSkills.add(skill);
          
          _selectedToolsMap[cwId] = tools.toSet();
        }

        if (_detectedSkills.isNotEmpty) {
           setState(() {
             _currentStep = 1; 
           });
        } else {
           throw Exception("AI found no distinct skills. Try describing your services more clearly.");
        }
      } else {
        final errorBody = jsonDecode(response.body);
        throw Exception(errorBody['error'] ?? response.reasonPhrase);
      }
    } catch (e) {
      _showError("Analysis Error: ${e.toString().split(':').last}");
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  
  Future<void> _completeSignup() async {
    if (_detectedSkills.isEmpty) {
      _showError("Profile analysis failed. Please go back and re-analyze your description.");
      return;
    }

    
    bool hasTools = _selectedToolsMap.values.any((set) => set.isNotEmpty);
    if (!hasTools) {
       _showError("You must select at least one tool you own across all your verified skills.");
       return;
    }

    setState(() => _isLoading = true);

    
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
      ).timeout(const Duration(seconds: 120));

      if (response.statusCode == 200) {
        if (!mounted) return;

        
        await FirebaseAuth.instance.signInWithEmailAndPassword(
          email: '${widget.phoneNumber}@kaaryaconnect.app',
          password: _passwordController.text,
        );

        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Signup complete! Welcome!"), backgroundColor: AppColors.successGreen));

        
        Navigator.of(context).popUntil((route) => route.isFirst);
      } else {
        final errorBody = jsonDecode(response.body);
        throw Exception(errorBody['error'] ?? 'Signup failed');
      }
    } catch (e) {
      _showError("Signup Error: ${e.toString().split(':').last}");
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  

  Widget _buildHeader(String title, String subtitle, {bool isSubStep = false}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 10),
        Text(
          title,
          style: TextStyle(
            fontSize: isSubStep ? 20 : 24,
            fontWeight: FontWeight.bold,
            color: Colors.black87,
          ),
        ),
        const SizedBox(height: 5),
        Text(
          subtitle,
          style: const TextStyle(fontSize: 14, color: Colors.black54),
        ),
        const Divider(height: 30, thickness: 1, color: Colors.grey),
      ],
    );
  }

  
  InputDecoration _inputDecoration(String label, IconData icon) {
    return InputDecoration(
      labelText: label,
      labelStyle: const TextStyle(color: Colors.black54),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: BorderSide(color: Colors.grey.shade300),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: BorderSide(color: Colors.grey.shade300),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: const BorderSide(color: AppColors.primaryTeal, width: 2),
      ),
      prefixIcon: Icon(icon, color: AppColors.primaryTeal.withOpacity(0.7)),
      filled: true,
      fillColor: AppColors.secondaryBackground,
    );
  }

  Widget _buildStep0BasicInfo() {
    int wordCount = _currentWordCount;
    final wordCountColor = wordCount >= minDescriptionWords ? AppColors.successGreen : AppColors.errorRed;

    return Form(
      key: _formKey,
      child: ListView(
        padding: const EdgeInsets.symmetric(horizontal: 0),
        children: [
          _buildHeader(
            "Worker Profile Setup",
            "Fill in your details to create your service profile."
          ),

          
          Row(
            children: [
              Expanded(child: TextFormField(
                controller: _nameController,
                decoration: _inputDecoration("Full Name", Icons.person_outline),
                validator: (v) => v!.isEmpty ? "Required" : null,
              )),
              const SizedBox(width: 10),
              Expanded(child: TextFormField(
                controller: _passwordController,
                obscureText: true,
                decoration: _inputDecoration("Password", Icons.lock_outline),
                validator: (v) => v!.length < 6 ? "Minimum 6 characters" : null,
              )),
            ],
          ),
          const SizedBox(height: 15),

          
          Row(children: [
            Expanded(child: TextFormField(
              controller: _pinController,
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              maxLength: 6,
              decoration: _inputDecoration("Pincode", Icons.location_on_outlined).copyWith(
                counterText: "",
              ),
              validator: (v) => v!.length != 6 ? "6 digits required" : null,
            )),
            const SizedBox(width: 10),
            Expanded(child: TextFormField(
              controller: _localityController,
              decoration: _inputDecoration("Locality / Area", Icons.place_outlined),
              validator: (v) => v!.isEmpty ? "Required" : null,
            )),
          ]),
          const SizedBox(height: 15),

          
          TextFormField(
            controller: _rateController,
            keyboardType: TextInputType.number,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            decoration: _inputDecoration("Base Hourly Rate", Icons.currency_rupee).copyWith(
              prefixText: "",
            ),
            validator: (v) => (int.tryParse(v ?? '0') ?? 0) < 50 ? "Minimum ${_formatCurrency(50)}" : null,
          ),
          const SizedBox(height: 30),

          
          _buildHeader(
            "Professional Summary (AI Analysis)",
            "Write a detailed summary of your services, experience, and tools for AI skill detection.",
            isSubStep: true,
          ),

          TextFormField(
            controller: _descController,
            maxLines: 6,
            decoration: InputDecoration(
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: BorderSide(color: Colors.grey.shade300),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: const BorderSide(color: AppColors.primaryTeal, width: 2),
              ),
              hintText: "Enter your professional summary (e.g., 'I am a master plumber with 10 years experience. I own a pipe cutter, snake drain machine, and a welding torch...').",
              errorMaxLines: 3,
            ),
            validator: _validateDescription,
          ),
          const SizedBox(height: 8),

          
          Align(
            alignment: Alignment.centerRight,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: wordCountColor.withOpacity(0.1),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(
                'Words: $wordCount / $minDescriptionWords required',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: wordCountColor,
                ),
              ),
            ),
          ),
          const SizedBox(height: 20),

          
          ElevatedButton.icon(
            onPressed: _isLoading ? null : _analyzeProfile,
            icon: _isLoading
              ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
              : const Icon(Icons.psychology_outlined),
            label: Text(_isLoading ? "Analyzing Profile..." : "Analyze & Verify Skills"),
            style: ElevatedButton.styleFrom(
              minimumSize: const Size(double.infinity, 50),
              backgroundColor: AppColors.primaryTeal,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))
            ),
          ),
          const SizedBox(height: 20),
        ],
      ),
    );
  }

  Widget _buildStep1Verification() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            _buildHeader(
              "Tool Confirmation",
              "Verify your skills and select the tools you own."
            ),
            TextButton.icon(
              onPressed: () => setState(() => _currentStep = 0),
              icon: Icon(Icons.edit, size: 18, color: AppColors.errorRed),
              label: Text("Edit Summary", style: TextStyle(color: AppColors.errorRed)),
            )
          ],
        ),

        
        Expanded(
          child: ListView.builder(
            itemCount: _detectedSkills.length,
            itemBuilder: (context, index) {
              final skill = _detectedSkills[index];
              final cwId = skill['cw_id'];
              
              final tools = (skill['suggestedTools'] as List<dynamic>?)?.map((t) => t.toString()).toSet().toList() ?? [];

              return Card(
                margin: const EdgeInsets.only(bottom: 15),
                elevation: 4,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                child: ExpansionTile(
                  initiallyExpanded: index == 0,
                  tilePadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                  leading: CircleAvatar(
                    backgroundColor: AppColors.secondaryTeal.withOpacity(0.1),
                    child: Icon(_getIconForCategory(skill['category']), color: AppColors.primaryTeal)
                  ),
                  title: Text(skill['task'], style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Colors.black87)),
                  subtitle: Text(skill['category'], style: const TextStyle(color: Colors.black54)),
                  children: [
                    const Divider(height: 1, thickness: 1, color: Colors.grey),
                    Padding(
                      padding: const EdgeInsets.all(16.0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text("Select Tools YOU OWN (Mandatory for service):", style: TextStyle(fontWeight: FontWeight.bold, color: Colors.black87)),
                          const SizedBox(height: 10),
                          Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: tools.map((tool) {
                              if (!_selectedToolsMap.containsKey(cwId)) {
                                _selectedToolsMap[cwId] = <String>{};
                              }
                              final isSelected = _selectedToolsMap[cwId]!.contains(tool);
                              return FilterChip(
                                label: Text(tool, style: TextStyle(fontSize: 13, fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal)),
                                selected: isSelected,
                                selectedColor: AppColors.secondaryTeal.withOpacity(0.3),
                                disabledColor: Colors.grey.shade100,
                                checkmarkColor: AppColors.primaryTeal,
                                labelStyle: TextStyle(color: isSelected ? AppColors.primaryTeal : Colors.black87),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(8),
                                  side: BorderSide(color: isSelected ? AppColors.secondaryTeal : Colors.grey.shade300)
                                ),
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
                          ),
                          const SizedBox(height: 10),
                          if (_selectedToolsMap[cwId]?.isEmpty ?? true)
                            Padding(
                              padding: const EdgeInsets.only(top: 8.0),
                              child: Text(
                                '⚠️ Selecting at least one tool for this skill is strongly recommended.',
                                style: TextStyle(color: AppColors.errorRed, fontSize: 12),
                              ),
                            ),
                        ],
                      ),
                    )
                  ],
                ),
              );
            },
          ),
        ),
        const SizedBox(height: 15),

        
        ElevatedButton(
          onPressed: _isLoading ? null : _completeSignup,
          style: ElevatedButton.styleFrom(
            minimumSize: const Size(double.infinity, 50),
            backgroundColor: AppColors.successGreen,
            foregroundColor: Colors.white,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))
          ),
          child: Text(_isLoading ? "Completing Setup..." : "Confirm & Finish Signup", style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
        ),
        const SizedBox(height: 10),
      ],
    );
  }

  
  IconData _getIconForCategory(String category) {
    final lowerCaseCategory = category.toLowerCase();
    if (lowerCaseCategory.contains("plumb")) return Icons.plumbing;
    if (lowerCaseCategory.contains("electr")) return Icons.bolt;
    if (lowerCaseCategory.contains("clean")) return Icons.cleaning_services;
    if (lowerCaseCategory.contains("carpenter") || lowerCaseCategory.contains("wood")) return Icons.carpenter;
    if (lowerCaseCategory.contains("paint")) return Icons.format_paint;
    if (lowerCaseCategory.contains("cook") || lowerCaseCategory.contains("chef")) return Icons.restaurant;
    if (lowerCaseCategory.contains("repair") || lowerCaseCategory.contains("handy")) return Icons.handyman;
    if (lowerCaseCategory.contains("driver")) return Icons.local_shipping;
    if (lowerCaseCategory.contains("ac")) return Icons.air;
    return Icons.work;
  }

  
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.primaryBackground,
      appBar: AppBar(
        title: const Text("Worker Onboarding", style: TextStyle(fontWeight: FontWeight.w600, color: Colors.black87)),
        centerTitle: false,
        elevation: 0,
        backgroundColor: AppColors.secondaryBackground,
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  _currentStep == 0 ? "Step 1 of 2: Profile Details" : "Step 2 of 2: Skill Verification",
                  style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: Colors.black54),
                ),
                Text(
                  "${_currentStep + 1}/2",
                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: AppColors.primaryTeal),
                ),
              ],
            ),
            const SizedBox(height: 8),
            LinearProgressIndicator(
              value: _currentStep == 0 ? 0.5 : 1.0,
              backgroundColor: Colors.grey.shade300,
              valueColor: const AlwaysStoppedAnimation<Color>(AppColors.primaryTeal),
              minHeight: 8,
              borderRadius: BorderRadius.circular(4),
            ),
            const SizedBox(height: 16),

            
            Expanded(
              child: IndexedStack(
                index: _currentStep,
                children: [
                  _buildStep0BasicInfo(), 
                  _buildStep1Verification(), 
                ],
              ),
            ),
          ],
        )
      ),
    );
  }
}