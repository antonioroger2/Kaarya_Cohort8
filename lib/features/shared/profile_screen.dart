// lib/features/shared/profile_screen.dart
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../core/theme.dart';

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

  final _nameController = TextEditingController();
  final _phoneController = TextEditingController();
  final _altPhoneController = TextEditingController();
  final _pinController = TextEditingController();
  final _descriptionController = TextEditingController();
  final _hourlyRateController = TextEditingController();
  final _idNumberController = TextEditingController();

  String _idType = 'Aadhar';
  int _experience = 0;
  List<Map<String, dynamic>> _workCategories = [];

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

  void _loadUserData(Map<String, dynamic> data) {
    _nameController.text = data['name'] ?? '';
    _phoneController.text = data['phone'] ?? '';
    _altPhoneController.text = data['altPhone'] ?? '';
    _pinController.text = data['pin'] ?? '';

    if (widget.isWorker) {
      _descriptionController.text = data['profileDescription'] ?? '';
      _hourlyRateController.text = (data['perHourCharge'] ?? 0).toString();
      _idNumberController.text = data['idDetails']?['number'] ?? '';
      _idType = data['idDetails']?['type'] ?? 'Aadhar';
      _experience = data['experience'] ?? 0;

      _workCategories = List<Map<String, dynamic>>.from(data['workCategories']?.map((e) => Map<String, dynamic>.from(e)) ?? []);
    }
  }

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

      if (_workCategories.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Please add at least one skill category'), backgroundColor: Colors.red));
        return;
      }

      if (_idNumberController.text.trim().isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Please enter your ID number'), backgroundColor: Colors.red));
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
        'workCategories': _workCategories,
      });
    }

    setState(() => _isEditing = false); 

    try {
      await FirebaseFirestore.instance.collection(collection).doc(widget.userId).set(dataToSave, SetOptions(merge: true));

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Profile saved successfully!'), backgroundColor: Colors.green));

    } catch (e) {
      if (!mounted) return;
      setState(() => _isEditing = true); 
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Failed to save profile: $e'), backgroundColor: Colors.red));
    }
  }

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
            child: DoodleBackground(
              child: SingleChildScrollView(
                controller: _scrollController,
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [

                    _buildTextField(controller: _nameController, label: 'Full Name', icon: Icons.person),
                    _buildTextField(controller: _phoneController, label: 'Primary Phone', icon: Icons.phone, keyboardType: TextInputType.phone),
                    _buildTextField(controller: _altPhoneController, label: 'Alternate Phone', icon: Icons.phone_android, required: false, keyboardType: TextInputType.phone),
                    _buildTextField(controller: _pinController, label: '6-Digit Pincode', icon: Icons.location_on, keyboardType: TextInputType.number),

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
                      _buildWorkCategoriesSection(),
                    ],

                    const SizedBox(height: 24),

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
                            onPressed: _saveProfile,
                            child: const Text('Save Profile'),
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
            if (_idType == 'Drivers License')
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

  Widget _buildWorkCategoriesSection() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text('My Skills & Expertise', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18, color: Colors.teal)),
                if (_isEditing)
                  IconButton(onPressed: _addWorkCategory, icon: const Icon(Icons.add_circle, color: Colors.teal)),
              ],
            ),
            const SizedBox(height: 12),

            if (_workCategories.isEmpty)
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: Colors.teal.withOpacity(0.05),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.teal.withOpacity(0.2)),
                ),
                child: const Column(
                  children: [
                    Icon(Icons.lightbulb_outline, size: 48, color: Colors.teal),
                    SizedBox(height: 8),
                    Text('No skills added yet!', style: TextStyle(fontWeight: FontWeight.w500)),
                    Text('Tap the + button to showcase your expertise', style: TextStyle(fontSize: 12, color: Colors.grey)),
                  ],
                ),
              )
            else

              ..._workCategories.asMap().entries.map((entry) {
                int idx = entry.key;
                Map<String, dynamic> category = entry.value;
                return _buildCategoryEditor(idx, category);
              }),

            const SizedBox(height: 16),

            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.amber.withOpacity(0.1),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.amber.withOpacity(0.3)),
              ),
              child: const Row(
                children: [
                  Icon(Icons.info_outline, color: Colors.amber, size: 20),
                  SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Add specific skills and certifications to attract more clients. Be detailed about your expertise!',
                      style: TextStyle(fontSize: 12, color: Colors.amber),
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

  void _addWorkCategory() {
    setState(() {
      _workCategories.add({'mainCategory': 'Plumber', 'tags': []});
    });

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  Widget _buildCategoryEditor(int index, Map<String, dynamic> category) {

    return StatefulBuilder(
      builder: (context, setState) {
        List<String> tags = List<String>.from(category['tags'] ?? []);
        final tagController = TextEditingController();

        return Card(
          margin: const EdgeInsets.only(bottom: 12),
          elevation: 1,
          child: Padding(
            padding: const EdgeInsets.all(8.0),
            child: Column(
              children: [
                Row(
                  children: [
                    Expanded(
                      child: DropdownButton<String>(
                        value: category['mainCategory'],
                        isExpanded: true,
                        items: ['Plumber', 'Electrician', 'Carpenter', 'Maid', 'Cook', 'Mechanic', 'Mover', 'Babysitter', 'Painter', 'Gardener', 'Security Guard', 'Driver', 'Housekeeper', 'Laundry Service', 'Pet Care', 'Home Tutor', 'AC Technician', 'Appliance Repair', 'Cleaning Service', 'Event Staff'].map((String value) {
                          return DropdownMenuItem<String>(value: value, child: Text(value));
                        }).toList(),
                        onChanged: _isEditing ? (newValue) {

                          this.setState(() {
                            _workCategories[index]['mainCategory'] = newValue!;
                          });
                        } : null,
                      ),
                    ),
                    if (_isEditing)
                      IconButton(
                        icon: const Icon(Icons.delete, color: Colors.redAccent),
                        onPressed: () {

                          this.setState(() {
                            _workCategories.removeAt(index);
                          });
                        },
                      )
                  ],
                ),
                const SizedBox(height: 8),

                Wrap(
                  spacing: 6,
                  children: tags.map((tag) => Chip(
                    label: Text(tag, style: const TextStyle(fontSize: 12)),
                    onDeleted: _isEditing ? () {
                      setState(() {
                        (_workCategories[index]['tags'] as List).remove(tag);
                      });
                    } : null,
                  )).toList(),
                ),

                if (_isEditing && tags.length < 3)
                  Padding(
                    padding: const EdgeInsets.only(top: 8.0),
                    child: TextField(
                      controller: tagController,
                      maxLength: 20,
                      decoration: InputDecoration(
                        labelText: 'Add a skill tag (e.g., "Non-veg expert")',
                        suffixIcon: IconButton(
                          icon: const Icon(Icons.add),
                          onPressed: () {
                            final tag = tagController.text.trim();
                            if (tag.isNotEmpty && !tags.contains(tag)) {

                              setState(() {
                                (_workCategories[index]['tags'] as List).add(tag);
                                tagController.clear();
                              });
                            }
                          },
                        )
                      ),
                    ),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }
}