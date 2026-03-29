

import 'package:flutter/material.dart';
import 'package:flutter/services.dart'; 
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart'; 
import '../worker/kyc_screen.dart';


class DoodleBackground extends StatelessWidget {
  final Widget child;
  const DoodleBackground({super.key, required this.child});
  @override
  Widget build(BuildContext context) {
    return Container(
      color: const Color(0xFFF8F9FA), 
      child: child,
    );
  }
}


class AppColors {
  static const Color primaryTeal = Color(0xFF008080); 
  static const Color secondaryTeal = Color(0xFF4DB6AC); 
  static const Color primaryBackground = Color(0xFFF8F9FA);
  static const Color secondaryBackground = Colors.white;
  static const Color errorRed = Color(0xFFD32F2F);
  static const Color successGreen = Color(0xFF388E3C);
}


class ProfileScreen extends StatefulWidget {
  final String userId;
  final bool isWorker;

  const ProfileScreen({super.key, required this.userId, required this.isWorker});

  @override
  ProfileScreenState createState() => ProfileScreenState();
}

class ProfileScreenState extends State<ProfileScreen> {
  final _formKey = GlobalKey<FormState>();
  bool _isEditing = false;
  bool _isLoading = false; 
  late Stream<DocumentSnapshot> _profileStream;

  
  final _nameController = TextEditingController();
  final _phoneController = TextEditingController();
  final _altPhoneController = TextEditingController();
  final _pinController = TextEditingController();

  
  final _descriptionController = TextEditingController();
  final _hourlyRateController = TextEditingController();
  final _idNumberController = TextEditingController();

  String _idType = 'Aadhar';
  int _experience = 0;

  final ScrollController _scrollController = ScrollController();

  
  String _formatCurrency(num val) {
    final formatter = NumberFormat.currency(locale: 'en_IN', symbol: '₹', decimalDigits: 0);
    return formatter.format(val);
  }

  @override
  void initState() {
    super.initState();
    _profileStream = _buildProfileStream();
  }

  @override
  void didUpdateWidget(covariant ProfileScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.userId != widget.userId || oldWidget.isWorker != widget.isWorker) {
      _profileStream = _buildProfileStream();
    }
  }

  Stream<DocumentSnapshot> _buildProfileStream() {
    final collection = widget.isWorker ? 'workers' : 'users';
    return FirebaseFirestore.instance.collection(collection).doc(widget.userId).snapshots();
  }

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
    }
  }

  
  Future<void> _saveProfile() async {
    if (!_formKey.currentState!.validate()) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Please fill all required fields correctly'), backgroundColor: Colors.orange.shade600));
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

      if (hourlyRate == null || hourlyRate < 50) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Please enter a valid hourly rate (min ${_formatCurrency(50)})'), backgroundColor: AppColors.errorRed));
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
      });
    }

    setState(() {
      _isEditing = false;
      _isLoading = true;
    });

    try {
      await FirebaseFirestore.instance.collection(collection).doc(widget.userId).set(dataToSave, SetOptions(merge: true));

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Profile saved successfully!'), backgroundColor: AppColors.successGreen));

    } catch (e) {
      if (!mounted) return;
      setState(() => _isEditing = true); 
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Failed to save profile: ${e.toString().split(':').last}'), backgroundColor: AppColors.errorRed));
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  

  InputDecoration _inputDecoration(String label, IconData icon, {bool enabled = true}) {
    return InputDecoration(
      labelText: label,
      labelStyle: TextStyle(color: enabled ? Colors.black54 : Colors.grey.shade600),
      prefixIcon: Icon(icon, color: enabled ? AppColors.primaryTeal.withOpacity(0.7) : Colors.grey.shade400),
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
      filled: true,
      fillColor: enabled ? AppColors.secondaryBackground : Colors.grey.shade100,
    );
  }

  Widget _buildTextField({
    required TextEditingController controller, 
    required String label, 
    required IconData icon, 
    bool required = true, 
    int? maxLines, 
    int? maxLength, 
    TextInputType? keyboardType,
    List<TextInputFormatter>? inputFormatters,
    String? helperText
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16.0),
      child: TextFormField(
        controller: controller,
        enabled: _isEditing,
        decoration: _inputDecoration(label, icon, enabled: _isEditing).copyWith(
          helperText: helperText,
          counterText: maxLength != null ? null : "",
        ),
        maxLines: maxLines ?? 1,
        maxLength: maxLength,
        keyboardType: keyboardType,
        inputFormatters: inputFormatters,
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
      elevation: 4,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      margin: const EdgeInsets.only(bottom: 16),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'Government ID Verification',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18, color: AppColors.primaryTeal),
                ),
                if (widget.isWorker)
                  TextButton.icon(
                    onPressed: () {
                      Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => KYCScreen(workerId: widget.userId),
                        ),
                      );
                    },
                    icon: const Icon(Icons.verified_user, color: AppColors.primaryTeal),
                    label: const Text('Verify ID (OCR)', style: TextStyle(color: AppColors.primaryTeal)),
                  ),
              ],
            ),
            const Divider(height: 20),
            
            
            DropdownButtonFormField<String>(
              value: _idType,
              items: ['Aadhar', 'PAN', 'Voter ID', 'Drivers License'].map((String value) {
                return DropdownMenuItem<String>(
                  value: value,
                  child: Text(value, style: const TextStyle(color: Colors.black87)),
                );
              }).toList(),
              onChanged: _isEditing ? (newValue) {
                setState(() {
                  _idType = newValue!;
                });
              } : null,
              decoration: _inputDecoration('ID Type', Icons.list_alt, enabled: _isEditing).copyWith(
                filled: !_isEditing,
                fillColor: _isEditing ? AppColors.secondaryBackground : Colors.grey.shade100,
              ),
            ),
            const SizedBox(height: 16),
            
            
            _buildTextField(
              controller: _idNumberController, 
              label: 'ID Number', 
              icon: Icons.badge,
              keyboardType: TextInputType.text,
            ),
            
            if (_idType == 'Drivers License' && widget.isWorker && _isEditing)
              Padding(
                padding: const EdgeInsets.only(top: 4.0),
                child: Text(
                  'Note: Driver\'s License is mandatory for driving-related jobs.', 
                  style: TextStyle(color: AppColors.errorRed, fontSize: 12),
                ),
              )
          ],
        ),
      ),
    );
  }

  Widget _buildExperienceSection() {
    return Card(
      elevation: 4,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      margin: const EdgeInsets.only(bottom: 16),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Professional Experience', 
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18, color: AppColors.primaryTeal)
            ),
            const Divider(height: 20),
            
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: AppColors.secondaryTeal.withOpacity(0.1),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AppColors.secondaryTeal.withOpacity(0.3)),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  
                  _isEditing ? IconButton(
                    onPressed: () => setState(() {
                      if (_experience > 0) _experience--;
                    }),
                    icon: Icon(Icons.remove_circle_outline, color: AppColors.errorRed),
                    tooltip: 'Decrease experience',
                  ) : const SizedBox(width: 48),

                  Expanded(
                    child: Column(
                      children: [
                        Text(
                          '$_experience',
                          style: const TextStyle(
                            fontSize: 40,
                            fontWeight: FontWeight.w900,
                            color: AppColors.primaryTeal,
                          ),
                        ),
                        Text(
                          _experience == 1 ? 'Year' : 'Years',
                          style: TextStyle(
                            fontSize: 16,
                            color: AppColors.primaryTeal.withOpacity(0.8),
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                  ),
                  
                  
                  _isEditing ? IconButton(
                    onPressed: () => setState(() => _experience++),
                    icon: Icon(Icons.add_circle_outline, color: AppColors.successGreen),
                    tooltip: 'Increase experience',
                  ) : const SizedBox(width: 48),
                ],
              ),
            ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: AppColors.primaryTeal.withOpacity(0.05),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  const Icon(Icons.info_outline, color: AppColors.primaryTeal, size: 20),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'This field helps clients determine your credibility and rates.',
                      style: TextStyle(fontSize: 12, color: AppColors.primaryTeal),
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

  
  Widget _buildWorkerSkillsSection(Map<String, dynamic> data) {
    final displayCwData = data['cw_data'] as Map<String, dynamic>? ?? {}; 
    
    
    if (displayCwData.isEmpty) {
        return Card(
           elevation: 4,
           shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
           child: Padding(
             padding: const EdgeInsets.all(16.0),
             child: Column(
               crossAxisAlignment: CrossAxisAlignment.start,
               children: [
                 const Text('Skills & Tools', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18, color: AppColors.primaryTeal)),
                 const Divider(height: 20),
                 Center(
                   child: Text(
                     "No detailed skill data available. Please re-run the AI analysis during onboarding.",
                     textAlign: TextAlign.center,
                     style: TextStyle(color: Colors.grey.shade600),
                   ),
                 ),
               ],
             ),
           ),
        );
    }
    
    return Card(
      elevation: 4,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      margin: const EdgeInsets.only(bottom: 16),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Verified Skills & Tools', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18, color: AppColors.primaryTeal)),
            const Divider(height: 20),
            
            
            ...displayCwData.entries.map((categoryEntry) {
              final category = categoryEntry.key;
              final tasks = categoryEntry.value as Map<String, dynamic>;

              return Card(
                elevation: 1,
                margin: const EdgeInsets.only(top: 8),
                color: Colors.teal.shade50,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                child: ExpansionTile(
                  tilePadding: const EdgeInsets.symmetric(horizontal: 12),
                  leading: Icon(Icons.category, color: AppColors.primaryTeal.withOpacity(0.8)),
                  title: Text(category, style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.black87)),
                  children: tasks.entries.map((taskEntry) {
                    final taskName = taskEntry.value['name'] ?? 'Task';
                    final taskData = taskEntry.value as Map<String, dynamic>;
                    
                    final tools = List<String>.from(taskData['myTools'] ?? []); 
                    final rating = (taskData['rating'] ?? 5.0).toDouble();
                    final totalWorks = taskData['total_works'] ?? 0;
                    
                    return ListTile(
                      dense: true,
                      contentPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 4),
                      title: Text(taskName, style: const TextStyle(fontWeight: FontWeight.w500)),
                      subtitle: Text(
                        "Tools: ${tools.isEmpty ? 'None Selected' : tools.join(', ')}",
                        style: TextStyle(fontSize: 12, color: tools.isEmpty ? AppColors.errorRed : Colors.grey.shade600),
                      ),
                      trailing: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.star, size: 14, color: Colors.amber.shade600),
                              Text(rating.toStringAsFixed(1), style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.black87)),
                            ],
                          ),
                          Text('$totalWorks jobs', style: const TextStyle(fontSize: 10, color: Colors.grey)),
                        ],
                      ),
                    );
                  }).toList(),
                ),
              );
            }),
          ],
        ),
      ),
    );
  }

  

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.primaryBackground,
      appBar: AppBar(
        title: Text(
          widget.isWorker ? 'Profile' : 'Profile',
          style: const TextStyle(
            fontWeight: FontWeight.w900,
            color: Colors.teal,
            fontSize: 18,
          ),
        ),
        centerTitle: false,
        elevation: 0,
        backgroundColor: AppColors.secondaryBackground,
        iconTheme: IconThemeData(color: Colors.black),
        actions: [
          if (!_isEditing)
            IconButton(
              icon: const Icon(Icons.edit, color: AppColors.primaryTeal),
              tooltip: 'Edit Profile',
              onPressed: () => setState(() => _isEditing = true),
            ),
          IconButton(
            icon: const Icon(Icons.logout, color: AppColors.errorRed),
            tooltip: 'Logout',
            onPressed: () async {
              await FirebaseAuth.instance.signOut();
            },
          ),
        ],
      ),
      body: StreamBuilder<DocumentSnapshot>(
        stream: _profileStream,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (!snapshot.hasData || !snapshot.data!.exists) {
            return const Center(
              child: Text(
                "Profile data not found.\nPlease try restarting the app.",
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.grey),
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
                    
                    const Text(
                      'Personal Details',
                      style: TextStyle(fontWeight: FontWeight.bold, fontSize: 22, color: Colors.black87),
                    ),
                    const Divider(height: 25),
                    
                    _buildTextField(controller: _nameController, label: 'Full Name', icon: Icons.person),
                    _buildTextField(controller: _phoneController, label: 'Primary Phone', icon: Icons.phone, keyboardType: TextInputType.phone),
                    _buildTextField(
                      controller: _altPhoneController, 
                      label: 'Alternate Phone', 
                      icon: Icons.phone_android, 
                      required: false, 
                      keyboardType: TextInputType.phone
                    ),
                    _buildTextField(
                      controller: _pinController, 
                      label: 'Pincode', 
                      icon: Icons.location_on, 
                      keyboardType: TextInputType.number,
                      maxLength: 6,
                      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                    ),

                    
                    if (widget.isWorker) ...[
                      const SizedBox(height: 24),
                      const Text(
                        'Professional Information', 
                        style: TextStyle(fontWeight: FontWeight.bold, fontSize: 22, color: Colors.black87)
                      ),
                      const Divider(height: 25),
                      
                      
                      _buildTextField(
                        controller: _descriptionController, 
                        label: 'Profile Description (Max 200 chars)', 
                        icon: Icons.description, 
                        maxLines: 4, 
                        maxLength: 200,
                        helperText: 'A summary for client viewing. Edit the full description using the AI tool.',
                      ),
                      
                      
                      _buildTextField(
                        controller: _hourlyRateController, 
                        label: 'Hourly Rate (Min 50)', 
                        icon: Icons.price_change, 
                        keyboardType: TextInputType.number,
                        inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                        helperText: _formatCurrency(int.tryParse(_hourlyRateController.text) ?? 0),
                      ),
                      
                      _buildIdDetailsSection(),
                      _buildExperienceSection(),
                      
                      
                      _buildWorkerSkillsSection(data),
                    ],

                    const SizedBox(height: 32),

                    
                    if (_isEditing)
                      Row(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          TextButton(
                            onPressed: () => setState(() => _isEditing = false),
                            child: Text('Cancel', style: TextStyle(color: AppColors.errorRed)),
                          ),
                          const SizedBox(width: 12),
                          ElevatedButton.icon(
                            onPressed: _isLoading ? null : _saveProfile,
                            icon: _isLoading 
                              ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                              : const Icon(Icons.check_circle_outline),
                            label: Text('Save Changes'),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: AppColors.primaryTeal,
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))
                            ),
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