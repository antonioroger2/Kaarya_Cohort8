// lib/features/shared/profile_screen.dart

import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../core/theme.dart'; // Ensure this path is correct

class ProfileScreen extends StatefulWidget {
  final String userId;
  final bool isWorker;

  const ProfileScreen({super.key, required this.userId, required this.isWorker});

  @override
  _ProfileScreenState createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  final _formKey = GlobalKey<FormState>();
  bool _isEditing = false;
  bool _isLoading = false; // Added loading state for save operation

  // Controllers for general user/worker fields
  final _nameController = TextEditingController();
  final _phoneController = TextEditingController();
  final _altPhoneController = TextEditingController();
  final _pinController = TextEditingController();

  // Controllers for worker specific fields
  final _descriptionController = TextEditingController();
  final _hourlyRateController = TextEditingController();
  final _idNumberController = TextEditingController();

  String _idType = 'Aadhar';
  int _experience = 0;
  
  // NOTE: We no longer use _workCategories for editing.
  // Editing worker skills will require a dedicated "Skill Management" screen
  // that uses the /cw/predict-multi and /complete-signup endpoints. 
  // For the profile screen, we only display the stored CW data.
  
  final ScrollController _scrollController = ScrollController();

  @override
  void dispose() {
    _nameController.dispose();
    _phoneController.dispose();
    _altPhoneController.dispose();
    _pinController.dispose();
    _descriptionController.dispose();
    _hourlyRateController.dispose();
    _idNumberController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  // --- Data Loading ---
  void _loadUserData(Map<String, dynamic> data) {
    // Basic user fields
    _nameController.text = data['name'] ?? '';
    _phoneController.text = data['phone'] ?? '';
    _altPhoneController.text = data['altPhone'] ?? '';
    _pinController.text = data['pin'] ?? '';

    // Worker fields
    if (widget.isWorker) {
      // NOTE: 'profileDescription' is typically set during the initial AI-driven signup
      _descriptionController.text = data['profileDescription'] ?? ''; 
      _hourlyRateController.text = (data['perHourCharge'] ?? 0).toString();
      _idNumberController.text = data['idDetails']?['number'] ?? '';
      _idType = data['idDetails']?['type'] ?? 'Aadhar';
      _experience = data['experience'] ?? 0;
    }
  }

  // --- Save Logic ---
  Future<void> _saveProfile() async {
    if (!_formKey.currentState!.validate()) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Please fill all required fields correctly'), backgroundColor: Colors.orange));
      return;
    }

    final collection = widget.isWorker ? 'workers' : 'users';

    Map<String, dynamic> dataToSave = {
      'name': _nameController.text.trim(),
      'phone': _phoneController.text.trim(),
      'altPhone': _altPhoneController.text.trim(),
      'pin': _pinController.text.trim(),
    };

    if (widget.isWorker) {
      final hourlyRate = int.tryParse(_hourlyRateController.text);

      if (hourlyRate == null || hourlyRate <= 0) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Please enter a valid hourly rate greater than 0'), backgroundColor: Colors.red));
        return;
      }

      dataToSave.addAll({
        'profileDescription': _descriptionController.text.trim(),
        'perHourCharge': hourlyRate,
        'experience': _experience,
        'idDetails': {
          'type': _idType,
          'number': _idNumberController.text.trim()
        },
        // IMPORTANT: We do NOT send CW data or tools here to prevent accidental overwrites
        // of complex nested data structures managed by the AI/Booking system.
      });
    }

    setState(() {
      _isEditing = false;
      _isLoading = true;
    });

    try {
      await FirebaseFirestore.instance.collection(collection).doc(widget.userId).set(dataToSave, SetOptions(merge: true));

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Profile saved successfully!'), backgroundColor: Colors.green));

    } catch (e) {
      if (!mounted) return;
      setState(() => _isEditing = true); 
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Failed to save profile: $e'), backgroundColor: Colors.red));
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }
  
  // --- UI Builder Methods ---

  Widget _buildTextField({
    required TextEditingController controller, 
    required String label, 
    required IconData icon, 
    bool required = true, 
    int? maxLines, 
    int? maxLength, 
    TextInputType? keyboardType
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16.0),
      child: TextFormField(
        controller: controller,
        enabled: _isEditing,
        decoration: InputDecoration(
          labelText: label,
          prefixIcon: Icon(icon),
          border: const OutlineInputBorder(),
          filled: !_isEditing,
          fillColor: Colors.grey[200],
        ),
        maxLines: maxLines ?? 1,
        maxLength: maxLength,
        keyboardType: keyboardType,
        validator: (value) {
          if (required && (value == null || value.isEmpty)) {
            return 'This field is required';
          }
          return null;
        },
      ),
    );
  }

  Widget _buildIdDetailsSection() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('ID Verification', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
            const SizedBox(height: 8),
            DropdownButtonFormField<String>(
              value: _idType,
              items: ['Aadhar', 'PAN', 'Voter ID', 'Drivers License'].map((String value) {
                return DropdownMenuItem<String>(
                  value: value,
                  child: Text(value),
                );
              }).toList(),
              onChanged: _isEditing ? (newValue) {
                setState(() {
                  _idType = newValue!;
                });
              } : null,
              decoration: const InputDecoration(
                labelText: 'ID Type',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 16),
            _buildTextField(controller: _idNumberController, label: 'ID Number', icon: Icons.badge),
            if (_idType == 'Drivers License' && widget.isWorker)
              const Padding(
                padding: EdgeInsets.only(top: 8.0),
                child: Text('Note: Driver\'s License is mandatory for driving-related jobs.', style: TextStyle(color: Colors.redAccent, fontSize: 12)),
              )
          ],
        ),
      ),
    );
  }

  Widget _buildExperienceSection() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Professional Experience', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18, color: Colors.teal)),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [Colors.teal.withOpacity(0.1), Colors.cyan.withOpacity(0.1)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.teal.withOpacity(0.2)),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  if (_isEditing)
                    IconButton(
                      onPressed: () => setState(() {
                        if (_experience > 0) _experience--;
                      }),
                      icon: const Icon(Icons.remove_circle, color: Colors.red),
                      tooltip: 'Decrease experience',
                    ),
                  Expanded(
                    child: Column(
                      children: [
                        Text(
                          '$_experience',
                          style: const TextStyle(
                            fontSize: 32,
                            fontWeight: FontWeight.bold,
                            color: Colors.teal,
                          ),
                        ),
                        Text(
                          _experience == 1 ? 'Year' : 'Years',
                          style: TextStyle(
                            fontSize: 16,
                            color: Colors.teal.withOpacity(0.7),
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        const Text(
                          'of Experience',
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.grey,
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (_isEditing)
                    IconButton(
                      onPressed: () => setState(() => _experience++),
                      icon: const Icon(Icons.add_circle, color: Colors.green),
                      tooltip: 'Increase experience',
                    ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.green.withOpacity(0.1),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.green.withOpacity(0.3)),
              ),
              child: const Row(
                children: [
                  Icon(Icons.trending_up, color: Colors.green, size: 20),
                  SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'More experience = Higher rates! Clients prefer experienced professionals.',
                      style: TextStyle(fontSize: 12, color: Colors.green),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // --- NEW WORKER SKILL DISPLAY SECTION (from first snippet) ---
  Widget _buildWorkerSkillsSection(Map<String, dynamic> data) {
    // This displays the skill hierarchy (Category -> Task) and stats (rating, jobs)
    // based on the nested structure populated during the AI-driven signup.
    final cwData = data['cwSkillScore'] as Map<String, dynamic>? ?? {}; 
    
    // Attempt to restructure cwSkillScore if it's flat, or rely on the existence of cw_data (if populated)
    // NOTE: Since the new backend uses cwSkillScore for stats and the old used cw_data 
    // for structure, we assume the backend still populates cw_data or use a simpler flat display
    
    // For now, we will use the cw_data structure from the backend, which is assumed
    // to contain Category -> Task Slug -> Task Details for display hierarchy.
    final displayCwData = data['cw_data'] as Map<String, dynamic>? ?? {}; 

    if (displayCwData.isEmpty) {
        return const Text("No canonical skills configured.");
    }
    
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Skill Hierarchy & Performance', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18, color: Colors.teal)),
            const SizedBox(height: 12),
            
            // Iterate over Categories (e.g., Plumber, Electrician)
            ...displayCwData.entries.map((categoryEntry) {
              final category = categoryEntry.key;
              final tasks = categoryEntry.value as Map<String, dynamic>;

              return Card(
                margin: const EdgeInsets.only(top: 8),
                color: Colors.teal.shade50,
                child: ExpansionTile(
                  title: Text(category, style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.teal)),
                  children: tasks.entries.map((taskEntry) {
                    final taskName = taskEntry.value['name'] ?? 'Task';
                    final taskData = taskEntry.value as Map<String, dynamic>;
                    
                    // Fetch rating/stats from the task data structure
                    final tools = List<String>.from(taskData['tools'] ?? []);
                    final rating = taskData['rating'] ?? 5.0;
                    final totalWorks = taskData['total_works'] ?? 0;
                    
                    return ListTile(
                      dense: true,
                      title: Text(taskName),
                      subtitle: Text("Tools: ${tools.join(', ')}"),
                      trailing: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(Icons.star, size: 14, color: Colors.amber),
                              Text(rating.toStringAsFixed(1), style: const TextStyle(fontWeight: FontWeight.bold)),
                            ],
                          ),
                          Text('$totalWorks jobs', style: const TextStyle(fontSize: 10, color: Colors.grey)),
                        ],
                      ),
                    );
                  }).toList(),
                ),
              );
            }).toList(),
          ],
        ),
      ),
    );
  }

  // --- Main Build Method ---

  @override
  Widget build(BuildContext context) {
    final collection = widget.isWorker ? 'workers' : 'users';

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.isWorker ? 'My Worker Profile' : 'My Profile'),
        actions: [
          if (!_isEditing)
            IconButton(
              icon: const Icon(Icons.edit),
              onPressed: () => setState(() => _isEditing = true),
            ),
          IconButton(
            icon: const Icon(Icons.logout),
            tooltip: 'Logout',
            onPressed: () async {
              await FirebaseAuth.instance.signOut();
            },
          ),
        ],
      ),
      body: StreamBuilder<DocumentSnapshot>(
        stream: FirebaseFirestore.instance.collection(collection).doc(widget.userId).snapshots(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (!snapshot.hasData || !snapshot.data!.exists) {
            return const Center(
              child: Text(
                "Profile data not found.\nPlease try restarting the app.",
                textAlign: TextAlign.center,
              ),
            );
          }

          final data = snapshot.data!.data() as Map<String, dynamic>;

          if (!_isEditing) {
            _loadUserData(data);
          }

          return Form(
            key: _formKey,
            child: DoodleBackground( // Assuming DoodleBackground is a custom widget
              child: SingleChildScrollView(
                controller: _scrollController,
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // --- General User Fields ---
                    _buildTextField(controller: _nameController, label: 'Full Name', icon: Icons.person),
                    _buildTextField(controller: _phoneController, label: 'Primary Phone', icon: Icons.phone, keyboardType: TextInputType.phone),
                    _buildTextField(controller: _altPhoneController, label: 'Alternate Phone', icon: Icons.phone_android, required: false, keyboardType: TextInputType.phone),
                    _buildTextField(controller: _pinController, label: '6-Digit Pincode', icon: Icons.location_on, keyboardType: TextInputType.number),

                    // --- Worker Specific Fields ---
                    if (widget.isWorker) ...[
                      const SizedBox(height: 16),
                      const Divider(),
                      const SizedBox(height: 16),
                      Text('Worker Details', style: Theme.of(context).textTheme.titleLarge),
                      const SizedBox(height: 16),
                      _buildTextField(controller: _descriptionController, label: 'Profile Description (max 200 chars)', icon: Icons.description, maxLines: 3, maxLength: 200),
                      _buildTextField(controller: _hourlyRateController, label: 'Hourly Rate (₹)', icon: Icons.price_change, keyboardType: TextInputType.number),
                      _buildIdDetailsSection(),
                      const SizedBox(height: 16),
                      _buildExperienceSection(),
                      const SizedBox(height: 16),
                      
                      // NEW SKILL DISPLAY SECTION
                      _buildWorkerSkillsSection(data),
                    ],

                    const SizedBox(height: 24),

                    // --- Save/Cancel Button ---
                    if (_isEditing)
                      Row(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          TextButton(
                            onPressed: () => setState(() => _isEditing = false),
                            child: const Text('Cancel'),
                          ),
                          const SizedBox(width: 8),
                          ElevatedButton(
                            onPressed: _isLoading ? null : _saveProfile,
                            child: _isLoading 
                              ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                              : const Text('Save Profile'),
                          ),
                        ],
                      )
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}