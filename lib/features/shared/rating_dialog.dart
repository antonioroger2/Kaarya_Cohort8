import 'package:flutter/material.dart';

class RatingDialog extends StatefulWidget {
  final String workerName;
  const RatingDialog({super.key, required this.workerName});

  @override
  State<RatingDialog> createState() => _RatingDialogState();
}

class _RatingDialogState extends State<RatingDialog> {
  double _rating = 5.0;

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text('Rate ${widget.workerName}'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text('How would you rate this service?'),
          const SizedBox(height: 16),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: List.generate(5, (index) {
              return IconButton(
                onPressed: () => setState(() => _rating = index + 1.0),
                icon: Icon(
                  index < _rating ? Icons.star : Icons.star_border,
                  color: Colors.amber,
                  size: 32,
                ),
              );
            }),
          ),
          const SizedBox(height: 8),
          Text(
            '${_rating.toInt()} star${_rating != 1.0 ? 's' : ''}',
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(), 
          child: const Text('Cancel'),
        ),
        ElevatedButton(
          onPressed: () => Navigator.of(context).pop(_rating), 
          child: const Text('Submit Rating'),
        ),
      ],
    );
  }
}