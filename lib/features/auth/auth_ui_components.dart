import 'package:flutter/material.dart';
import 'dart:math' as math;
import '/../../core/theme.dart'; 
class AuthStyles {
    static const Color richBlack = Color(0xFF050505);   static const Color darkCard = Color(0xFF121212);    static const Color surface = Color(0xFF1E1E1E);   
    static const Color neonGreen = Color(0xFF00E676);
  static const Color brightTeal = Color(0xFF00E5FF);
  
    static const Color textWhite = Color(0xFFFFFFFF);
  static const Color textGrey = Color(0xFF9E9E9E);
  static const Color borderDark = Color(0xFF333333);

    static const Color primaryBlue = neonGreen;
  static const Color primaryTeal = brightTeal;
  static const Color surfaceColor = darkCard;
  static const Color darkText = textWhite;
  static const Color lightText = textGrey;

    static const LinearGradient greenGradient = LinearGradient(
    colors: [neonGreen, brightTeal],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );
  
  static const LinearGradient darkGradient = LinearGradient(
    colors: [richBlack, Color(0xFF0F1115)],
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
  );
}

class AnimatedGradientBackground extends StatefulWidget {
  final Widget child;
  const AnimatedGradientBackground({super.key, required this.child});

  @override
  State<AnimatedGradientBackground> createState() =>
      _AnimatedGradientBackgroundState();
}

class _AnimatedGradientBackgroundState
    extends State<AnimatedGradientBackground>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(seconds: 10),
      vsync: this,
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        return Container(
          decoration: BoxDecoration(
            gradient: RadialGradient(
              center: Alignment(
                math.sin(_controller.value * 2 * math.pi) * 0.3,
                math.cos(_controller.value * 2 * math.pi) * 0.3,
              ),
              radius: 1.5,
              colors: [
                Color(0xFF0A1F1C),                 AuthStyles.richBlack,
              ],
              stops: const [0.0, 0.8],
            ),
          ),
          child: DoodleBackground(child: widget.child),
        );
      },
      child: widget.child,
    );
  }
}

class ModernMobileHeader extends StatelessWidget {
  const ModernMobileHeader({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(24, 60, 24, 30),
      decoration: BoxDecoration(
        color: AuthStyles.richBlack,
        border: Border(bottom: BorderSide(color: Colors.white.withOpacity(0.05))),
      ),
      child: Row(
        children: [
                    Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              gradient: AuthStyles.greenGradient,
              borderRadius: BorderRadius.circular(12),
              boxShadow: [
                BoxShadow(
                  color: AuthStyles.neonGreen.withOpacity(0.3),
                  blurRadius: 15,
                  spreadRadius: -2,
                )
              ],
            ),
            child: const Center(
              child: Text("KS", style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold, fontSize: 20)),
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: const [
                Text(
                  "kaaryaseva",
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 22,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.5,
                  ),
                ),
                Text(
                  "The Future of Work",
                  style: TextStyle(
                    color: AuthStyles.neonGreen,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 0.5,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class DesktopHeroSection extends StatelessWidget {
  const DesktopHeroSection({super.key});

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
                Container(
          width: 140,
          height: 140,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: LinearGradient(
              colors: [
                AuthStyles.neonGreen.withOpacity(0.1),
                AuthStyles.brightTeal.withOpacity(0.05),
              ],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            border: Border.all(color: AuthStyles.neonGreen.withOpacity(0.5), width: 2),
            boxShadow: [
              BoxShadow(
                color: AuthStyles.neonGreen.withOpacity(0.2),
                blurRadius: 60,
                spreadRadius: 10,
              ),
            ],
          ),
          child: Center(
            child: ShaderMask(
              shaderCallback: (bounds) => AuthStyles.greenGradient.createShader(bounds),
              child: const Text(
                "KS",
                style: TextStyle(fontSize: 50, color: Colors.white, fontWeight: FontWeight.w900),
              ),
            ),
          ),
        ),
        const SizedBox(height: 50),
        const Text(
          "kaaryaseva",
          style: TextStyle(
            fontSize: 56,
            fontWeight: FontWeight.w900,
            letterSpacing: -2,
            color: Colors.white,
          ),
        ),
        const SizedBox(height: 16),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          decoration: BoxDecoration(
            color: AuthStyles.neonGreen.withOpacity(0.1),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: AuthStyles.neonGreen.withOpacity(0.2)),
          ),
          child: const Text(
            "Connecting India’s Informal Workforce",
            style: TextStyle(
              fontSize: 16,
              color: AuthStyles.neonGreen,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ],
    );
  }
}

class ResponsiveAuthLayout extends StatelessWidget {
  final Widget formContent;
  final String title;
  final String subtitle;

  const ResponsiveAuthLayout({
    super.key,
    required this.formContent,
    required this.title,
    required this.subtitle,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AuthStyles.richBlack,
      body: LayoutBuilder(
        builder: (context, constraints) {
          if (constraints.maxWidth > 900) {
                        return Row(
              children: [
                Expanded(
                  flex: 6,
                  child: AnimatedGradientBackground(
                    child: const Center(
                      child: Padding(padding: EdgeInsets.all(60), child: DesktopHeroSection()),
                    ),
                  ),
                ),
                Expanded(
                  flex: 5,
                  child: Container(
                    color: AuthStyles.darkCard,
                    child: Center(
                      child: SingleChildScrollView(
                        padding: const EdgeInsets.symmetric(horizontal: 60, vertical: 40),
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 480),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(title, style: const TextStyle(fontSize: 36, fontWeight: FontWeight.w800, color: Colors.white, letterSpacing: -1)),
                              const SizedBox(height: 12),
                              Text(subtitle, style: const TextStyle(fontSize: 16, color: AuthStyles.textGrey, height: 1.5)),
                              const SizedBox(height: 40),
                              formContent,
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            );
          } else {
                        return Stack(
              children: [
                                Positioned.fill(
                  child: AnimatedGradientBackground(
                    child: Container(),                   ),
                ),
                Column(
                  children: [
                    const ModernMobileHeader(),
                    Expanded(
                      child: ClipRRect(
                        borderRadius: const BorderRadius.vertical(top: Radius.circular(30)),
                        child: Container(
                          color: AuthStyles.darkCard.withOpacity(0.95),                           child: SingleChildScrollView(
                            padding: const EdgeInsets.all(24),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const SizedBox(height: 10),
                                Text(title, style: const TextStyle(fontSize: 28, fontWeight: FontWeight.w800, color: Colors.white)),
                                const SizedBox(height: 8),
                                Text(subtitle, style: const TextStyle(fontSize: 14, color: AuthStyles.textGrey)),
                                const SizedBox(height: 32),
                                formContent,
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            );
          }
        },
      ),
    );
  }
}

InputDecoration proInputDecoration(String label, IconData icon) {
  return InputDecoration(
    labelText: label,
    alignLabelWithHint: true,
    floatingLabelBehavior: FloatingLabelBehavior.auto,
    prefixIcon: Container(
      margin: const EdgeInsets.only(left: 12, right: 8),
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: AuthStyles.surface,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Icon(icon, size: 20, color: AuthStyles.neonGreen),
    ),
    labelStyle: const TextStyle(color: AuthStyles.textGrey, fontSize: 14),
    floatingLabelStyle: const TextStyle(color: AuthStyles.neonGreen, fontWeight: FontWeight.w600),
    filled: true,
    fillColor: AuthStyles.surface,
    border: OutlineInputBorder(
      borderRadius: BorderRadius.circular(16),
      borderSide: BorderSide.none,
    ),
    enabledBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(16),
      borderSide: BorderSide(color: Colors.white.withOpacity(0.05)),
    ),
    focusedBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(16),
      borderSide: const BorderSide(color: AuthStyles.neonGreen, width: 1.5),
    ),
    contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 20),
  );
}