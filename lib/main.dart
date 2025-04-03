import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:sienatalk/screens/counselor/counselor_container.dart';
import 'package:sienatalk/screens/student/student_home_screen_container.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:provider/provider.dart';
import 'splash_screen.dart';
import 'utils/app_colors.dart';
import 'providers/auth_provider.dart';
import 'screens/auth/sign_in_screen.dart';
import 'screens/auth/sign_up_screen.dart';
import 'screens/auth/forgot_password_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Set preferred orientations
  SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
  ]);

  // Set system UI overlay style for status bar and navigation bar
  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
    // Status bar color and brightness
    statusBarColor: Colors.transparent,
    statusBarIconBrightness: Brightness.light,
    statusBarBrightness: Brightness.dark,

    // Navigation bar color and brightness (bottom bar)
    systemNavigationBarColor: AppColors.primaryDark,
    systemNavigationBarIconBrightness: Brightness.light,
    systemNavigationBarDividerColor: Colors.transparent,
  ));

  // Initialize Firebase
  await Firebase.initializeApp();

  // Initialize Supabase with your credentials
  await Supabase.initialize(
    url: 'https://citlykrxdlkcxskwgbpp.supabase.co',
    anonKey: 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImNpdGx5a3J4ZGxrY3hza3dnYnBwIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NDMzNDExOTcsImV4cCI6MjA1ODkxNzE5N30.BVt1wmzm3YaIqrWAFSWMR2LeWx3nj1doVRtGKcgAyIg',
  );

  runApp(const SienaTalkApp());
}

class SienaTalkApp extends StatelessWidget {
  const SienaTalkApp({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => UserAuthProvider()),
      ],
      child: MaterialApp(
        title: 'SienaTalk',
        debugShowCheckedModeBanner: false,
        theme: ThemeData(
          primaryColor: AppColors.primary,
          colorScheme: ColorScheme.fromSeed(
            seedColor: AppColors.primary,
            primary: AppColors.primary,
            secondary: AppColors.accent,
            background: AppColors.background,
          ),
          fontFamily: 'Montserrat',
          useMaterial3: true,
          inputDecorationTheme: InputDecorationTheme(
            filled: true,
            fillColor: Colors.white,
            contentPadding: const EdgeInsets.all(16),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(color: AppColors.divider),
            ),
          ),
        ),
        initialRoute: '/',
        routes: {
          '/': (context) => const SplashScreen(),
          '/signin': (context) => const SignInScreen(),
          '/sign_in': (context) => const SignInScreen(), // Add this route to handle both formats
          '/signup': (context) => const SignUpScreen(initialUserType: 'Student'),
          '/forgot_password': (context) => const ForgotPasswordScreen(),
          '/student_home': (context) => const StudentHomeScreenContainer(),
          '/counselor_home': (context) => const Scaffold(body: Center(child: Text('Counselor Home'))), // Placeholder
          '/admin_home': (context) => const Scaffold(body: Center(child: Text('Admin Home'))), // Placeholder
          '/counselor_home': (context) => const CounselorContainer(),

        },
        // Handle unknown routes
        onUnknownRoute: (settings) {
          return MaterialPageRoute(
            builder: (context) => const SignInScreen(),
          );
        },
      ),
    );
  }
}