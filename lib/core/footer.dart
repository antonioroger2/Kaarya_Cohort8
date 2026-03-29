import 'package:flutter/material.dart';
import '../../core/design_tokens.dart';

// ─────────────────────────────────────────────
//  Typewriter Text Widget
// ─────────────────────────────────────────────
class TypewriterText extends StatefulWidget {
  final List<String> texts;
  final Duration typingSpeed;
  final Duration pauseBetweenTexts;
  final TextStyle? style;

  const TypewriterText({
    super.key,
    required this.texts,
    this.typingSpeed = const Duration(milliseconds: 100),
    this.pauseBetweenTexts = const Duration(seconds: 2),
    this.style,
  });

  @override
  State<TypewriterText> createState() => _TypewriterTextState();
}

class _TypewriterTextState extends State<TypewriterText> {
  int _currentTextIndex = 0;
  String _displayedText = '';
  int _charIndex = 0;
  bool _isTyping = true;

  @override
  void initState() {
    super.initState();
    _startTyping();
  }

  void _startTyping() {
    if (_currentTextIndex < widget.texts.length) {
      final text = widget.texts[_currentTextIndex];
      if (_charIndex < text.length) {
        Future.delayed(widget.typingSpeed, () {
          if (mounted) {
            setState(() {
              _displayedText = text.substring(0, _charIndex + 1);
              _charIndex++;
            });
            _startTyping();
          }
        });
      } else {
        // Finished typing current text, pause then move to next
        Future.delayed(widget.pauseBetweenTexts, () {
          if (mounted) {
            setState(() {
              _currentTextIndex = (_currentTextIndex + 1) % widget.texts.length;
              _charIndex = 0;
              _displayedText = '';
            });
            _startTyping();
          }
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Text(
      _displayedText,
      style: widget.style ?? const TextStyle(fontSize: 16, color: Colors.black87),
      textAlign: TextAlign.center,
    );
  }
}

// ─────────────────────────────────────────────
//  App Footer Widget
// ─────────────────────────────────────────────
class AppFooter extends StatelessWidget {
  const AppFooter({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 32.0, horizontal: 16.0),
      color: Colors.grey.shade50,
      child: Column(
        children: [
          // Typewriter text
          TypewriterText(
            texts: [
              "Blue collar Gig Services"
              "Fair, hyperlocal work.",
              "No middlemen.",
              "No contracts.",
              "Workers are the boss.",
              "Empowering Indian Blue-collar workforce."
            ],
            style: const TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w600,
              color: AppDesignTokens.primary,
            ),
          ),
          const SizedBox(height: 24),
          // Trust badges and T&C
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // Trust badges (placeholder icons)
              Icon(Icons.verified, color: AppDesignTokens.primary, size: 24),
              const SizedBox(width: 8),
              Icon(Icons.security, color: AppDesignTokens.primary, size: 24),
              const SizedBox(width: 8),
              Icon(Icons.shield, color: AppDesignTokens.primary, size: 24),
              const SizedBox(width: 16),
              // T&C link
              TextButton(
                onPressed: () {
                  // TODO: Navigate to T&C page
                },
                child: const Text(
                  'Terms & Conditions',
                  style: TextStyle(color: AppDesignTokens.primary, fontWeight: FontWeight.w500),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}