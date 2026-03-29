// lib/app.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'core/theme.dart';
import 'core/design_tokens.dart';
import 'features/auth/auth_wrapper.dart';
import 'features/auth/worker_onboarding_screen.dart';

class KaaryaConnectApp extends ConsumerWidget {
  const KaaryaConnectApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return MaterialApp(
      title: 'Kaarya Connect',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        // Primary Theme
        primarySwatch: Colors.teal,
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: AppDesignTokens.primary,
          secondary: AppDesignTokens.accent,
          tertiary: AppDesignTokens.aiBlue,
        ),
        scaffoldBackgroundColor: AppDesignTokens.surface,
        
        // Custom Theme Extension
        extensions: [
          DoodleBackgroundTheme(
            primaryColor: AppDesignTokens.primary,
            secondaryColor: AppDesignTokens.accent,
            patternDensity: 0.3,
          ),
        ],

        // AppBar Theme
        appBarTheme: AppBarTheme(
          backgroundColor: AppDesignTokens.primary,
          foregroundColor: Colors.black,
          elevation: 0,
          centerTitle: true,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.vertical(bottom: AppDesignTokens.radius)
          ),
        ),

        // Card Theme
        cardTheme: ThemeData().cardTheme.copyWith(
          elevation: 2,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.all(AppDesignTokens.cardRadius),
          ),
          clipBehavior: Clip.antiAlias,
        ),

        // ElevatedButton Theme
        elevatedButtonTheme: ElevatedButtonThemeData(
          style: ElevatedButton.styleFrom(
            backgroundColor: AppDesignTokens.primary,
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.all(AppDesignTokens.radiusSm),
            ),
          ),
        ),

        // InputDecoration Theme
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: AppDesignTokens.surface,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.all(AppDesignTokens.radiusSm),
            borderSide: BorderSide.none,
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.all(AppDesignTokens.radiusSm),
            borderSide: BorderSide(color: AppDesignTokens.primary.withOpacity(0.3)),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.all(AppDesignTokens.radiusSm),
            borderSide: BorderSide(color: AppDesignTokens.primary),
          ),
          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
        ),
      ),
      home: const AuthWrapper(),
      routes: {
        '/worker-onboarding': (context) => const WorkerOnboardingScreen(phoneNumber: '', uid: ''),
      },
    );
  }
}
