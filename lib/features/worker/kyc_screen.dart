import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';

import '../../core/api_client.dart';

class KycResult {
  KycResult({
    this.name,
    this.idNumber,
    this.expiryDate,
    this.raw = const {},
  });

  final String? name;
  final String? idNumber;
  final DateTime? expiryDate;
  final Map<String, dynamic> raw;

  factory KycResult.fromMap(Map<String, dynamic> map) {
    DateTime? expiry;
    final expiryRaw = map['expiryDate'] ?? map['expiry_date'];
    if (expiryRaw is String) {
      expiry = DateTime.tryParse(expiryRaw);
    } else if (expiryRaw is Map && expiryRaw['seconds'] != null) {
      final seconds = (expiryRaw['seconds'] as num?)?.toInt();
      if (seconds != null) {
        expiry = DateTime.fromMillisecondsSinceEpoch(seconds * 1000);
      }
    }

    return KycResult(
      name: map['name']?.toString() ?? map['fullName']?.toString(),
      idNumber: map['idNumber']?.toString() ?? map['id_number']?.toString(),
      expiryDate: expiry,
      raw: map,
    );
  }
}

class _KycEvaluation {
  const _KycEvaluation({
    required this.nameMatch,
    required this.idMatch,
    required this.isExpired,
  });

  final bool nameMatch;
  final bool idMatch;
  final bool isExpired;
}

class KYCScreen extends ConsumerStatefulWidget {
  const KYCScreen({super.key, required this.workerId});

  final String workerId;

  @override
  ConsumerState<KYCScreen> createState() => _KYCScreenState();
}

class _KYCScreenState extends ConsumerState<KYCScreen> {
  final ImagePicker _picker = ImagePicker();

  bool _loadingProfile = true;
  bool _isSubmitting = false;
  String? _error;

  Map<String, dynamic>? _profile;
  XFile? _selectedFile;
  Uint8List? _previewBytes;
  KycResult? _result;
  _KycEvaluation? _evaluation;

  @override
  void initState() {
    super.initState();
    _loadProfile();
  }

  Future<void> _loadProfile() async {
    try {
      final doc = await FirebaseFirestore.instance
          .collection('workers')
          .doc(widget.workerId)
          .get();

      if (!mounted) return;
      setState(() {
        _profile = doc.data();
        _loadingProfile = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = 'Failed to load profile: ${e.toString().split(':').last}';
        _loadingProfile = false;
      });
    }
  }

  Future<void> _pickImage() async {
    try {
      final picked = await _picker.pickImage(
        source: ImageSource.gallery,
        imageQuality: 85,
      );
      if (picked == null) return;

      final bytes = await picked.readAsBytes();
      if (!mounted) return;
      setState(() {
        _selectedFile = picked;
        _previewBytes = bytes;
        _error = null;
        _result = null;
        _evaluation = null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = 'Unable to pick image: ${e.toString().split(':').last}');
    }
  }

  Future<void> _submitKyc() async {
    if (_selectedFile == null || _previewBytes == null) {
      setState(() => _error = 'Please select an ID image first.');
      return;
    }

    setState(() {
      _isSubmitting = true;
      _error = null;
    });

    try {
      final idType = _profile?['idDetails']?['type']?.toString() ?? 'Aadhar';
      final apiResult = await ApiClient.uploadKycDocument(
        workerId: widget.workerId,
        bytes: _previewBytes!,
        filename: _selectedFile!.name,
        idType: idType,
      );

      final parsed = KycResult.fromMap(apiResult);
      final evaluation = _evaluateAgainstProfile(parsed);

      if (!mounted) return;
      setState(() {
        _result = parsed;
        _evaluation = evaluation;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('KYC submitted for Azure OCR verification.')),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = e.toString().replaceFirst('Exception: ', ''));
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  _KycEvaluation _evaluateAgainstProfile(KycResult result) {
    final profileName = _profile?['name']?.toString().toLowerCase().trim();
    final extractedName = result.name?.toLowerCase().trim();
    final nameMatch = profileName != null && extractedName != null
        ? extractedName.contains(profileName) || profileName.contains(extractedName)
        : false;

    final profileId = _profile?['idDetails']?['number']
        ?.toString()
        .replaceAll(RegExp(r'\s'), '')
        .toUpperCase();
    final extractedId = result.idNumber
        ?.replaceAll(RegExp(r'\s'), '')
        .toUpperCase();
    final idMatch = profileId != null && extractedId != null
        ? extractedId.contains(profileId) || profileId.contains(extractedId)
        : false;

    final isExpired = result.expiryDate != null && result.expiryDate!.isBefore(DateTime.now());

    return _KycEvaluation(
      nameMatch: nameMatch,
      idMatch: idMatch,
      isExpired: isExpired,
    );
  }

  String _formatDate(DateTime? date) {
    if (date == null) return '—';
    return DateFormat('dd MMM yyyy').format(date);
  }

  Widget _buildStatusChip({required IconData icon, required String label, required bool ok}) {
    return Chip(
      avatar: Icon(icon, size: 16, color: ok ? Colors.green : Colors.red),
      label: Text(label),
      backgroundColor: ok ? Colors.green.withOpacity(0.1) : Colors.red.withOpacity(0.1),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final header = _profile != null
        ? Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                _profile?['name']?.toString() ?? 'Worker Profile',
                style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 6),
              Text(
                'ID: ${_profile?['idDetails']?['type'] ?? 'Aadhar'} • ${_profile?['idDetails']?['number'] ?? 'Not added'}',
                style: const TextStyle(color: Colors.black54),
              ),
            ],
          )
        : null;

    return Scaffold(
      appBar: AppBar(
        title: const Text('KYC Verification'),
        backgroundColor: Colors.teal,
        foregroundColor: Colors.white,
      ),
      body: _loadingProfile
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (header != null) header,
                  const SizedBox(height: 12),
                  Card(
                    elevation: 2,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    child: Padding(
                      padding: const EdgeInsets.all(16.0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('Upload Government ID', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
                          const SizedBox(height: 8),
                          const Text(
                            'We will send this image to Azure Form Recognizer via FastAPI to extract Name, ID Number, and Expiry Date. Data is matched against your profile to protect marketplace trust.',
                          ),
                          const SizedBox(height: 12),
                          Row(
                            children: [
                              ElevatedButton.icon(
                                onPressed: _isSubmitting ? null : _pickImage,
                                icon: const Icon(Icons.upload_file),
                                label: Text(_selectedFile == null ? 'Choose ID' : 'Replace ID'),
                              ),
                              const SizedBox(width: 12),
                              if (_selectedFile != null)
                                Text(
                                  _selectedFile!.name,
                                  overflow: TextOverflow.ellipsis,
                                ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          if (_previewBytes != null)
                            ClipRRect(
                              borderRadius: BorderRadius.circular(12),
                              child: Image.memory(
                                _previewBytes!,
                                height: 180,
                                width: double.infinity,
                                fit: BoxFit.cover,
                              ),
                            ),
                          const SizedBox(height: 16),
                          ElevatedButton.icon(
                            onPressed: _isSubmitting ? null : _submitKyc,
                            icon: _isSubmitting
                                ? const SizedBox(
                                    height: 16,
                                    width: 16,
                                    child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                                  )
                                : const Icon(Icons.verified_user),
                            label: Text(_isSubmitting ? 'Submitting...' : 'Submit for Verification'),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.teal,
                              foregroundColor: Colors.white,
                              minimumSize: const Size.fromHeight(48),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  if (_error != null) ...[
                    const SizedBox(height: 12),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.red.withOpacity(0.08),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: Colors.red.withOpacity(0.3)),
                      ),
                      child: Text(_error!, style: const TextStyle(color: Colors.red)),
                    ),
                  ],
                  if (_result != null && _evaluation != null) ...[
                    const SizedBox(height: 12),
                    Card(
                      elevation: 2,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      child: Padding(
                        padding: const EdgeInsets.all(16.0),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text('OCR Result', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
                            const SizedBox(height: 8),
                            Text('Name: ${_result!.name ?? 'Not detected'}'),
                            Text('ID Number: ${_result!.idNumber ?? 'Not detected'}'),
                            Text('Expiry: ${_formatDate(_result!.expiryDate)}'),
                            const Divider(height: 24),
                            Wrap(
                              spacing: 8,
                              runSpacing: 8,
                              children: [
                                _buildStatusChip(
                                  icon: Icons.person,
                                  label: _evaluation!.nameMatch ? 'Name matched' : 'Name mismatch',
                                  ok: _evaluation!.nameMatch,
                                ),
                                _buildStatusChip(
                                  icon: Icons.badge,
                                  label: _evaluation!.idMatch ? 'ID matched' : 'ID mismatch',
                                  ok: _evaluation!.idMatch,
                                ),
                                _buildStatusChip(
                                  icon: Icons.lock_clock,
                                  label: _evaluation!.isExpired ? 'Document expired' : 'Document valid',
                                  ok: !_evaluation!.isExpired,
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                  const SizedBox(height: 16),
                  Card(
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    elevation: 1,
                    child: Padding(
                      padding: const EdgeInsets.all(14.0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: const [
                          Text('Trust & Coverage', style: TextStyle(fontWeight: FontWeight.bold)),
                          SizedBox(height: 6),
                          Text('We cross-reference extracted details with your profile to prevent fraud. Betweenness centrality and Louvain clustering can further flag outlier communities where trust needs reinforcement.'),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
    );
  }
}
