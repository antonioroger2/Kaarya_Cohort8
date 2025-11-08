// lib/features/shared/report_dialog.dart
import 'package:flutter/material.dart';

class ReportDialog extends StatefulWidget {
  final String reportType;
  const ReportDialog({super.key, required this.reportType});

  @override
  State<ReportDialog> createState() => _ReportDialogState();
}

class _ReportDialogState extends State<ReportDialog> {
  final _reasonController = TextEditingController();
  String _selectedReason = '';
  final List<String> _commonReasons = [
    'Poor service quality',
    'Unprofessional behavior',
    'Did not show up',
    'Charged extra amount',
    'Safety concerns',
    'Damaged property',
    'False advertising',
    'Other'
  ];

  @override
  void dispose() {
    _reasonController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Report Issue'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              widget.reportType,
              style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.red),
            ),
            const SizedBox(height: 16),
            const Text('Select a reason:'),
            const SizedBox(height: 8),
            // Reason radio buttons
            ..._commonReasons.map((reason) => RadioListTile<String>(
              title: Text(reason),
              value: reason,
              groupValue: _selectedReason,
              onChanged: (value) => setState(() => _selectedReason = value!),
              dense: true,
            )),
            
            const SizedBox(height: 16),
            
            // Other reason text field
            if (_selectedReason == 'Other')
              TextField(
                controller: _reasonController,
                decoration: const InputDecoration(
                  labelText: 'Please specify the reason',
                  border: OutlineInputBorder(),
                ),
                maxLines: 3,
              ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(), // Returns null
          child: const Text('Cancel'),
        ),
        ElevatedButton(
          onPressed: () {
            final reason = _selectedReason == 'Other'
                ? _reasonController.text.trim()
                : _selectedReason;
            
            if (reason.isNotEmpty) {
              Navigator.of(context).pop(reason); // Returns the selected/entered reason
            }
          },
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.red,
            foregroundColor: Colors.white,
          ),
          child: const Text('Submit Report'),
        ),
      ],
    );
  }
}
