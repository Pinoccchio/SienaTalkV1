import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:firebase_auth/firebase_auth.dart' as firebase;
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:fluttertoast/fluttertoast.dart';
import '../utils/app_colors.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({Key? key}) : super(key: key);

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> with SingleTickerProviderStateMixin {
  late AnimationController _animationController;
  late Animation<double> _animation;

  final firebase.FirebaseAuth _firebaseAuth = firebase.FirebaseAuth.instance;
  final SupabaseClient _supabase = Supabase.instance.client;

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    );
    _animation = CurvedAnimation(
      parent: _animationController,
      curve: Curves.easeInOut,
    );
    _animationController.forward();

    // Add listener to navigate after animation completes
    _animationController.addStatusListener((status) {
      if (status == AnimationStatus.completed) {
        _checkAuthStatus();
      }
    });
  }

  Future<void> _checkAuthStatus() async {
    try {
      // Check if user is already signed in
      final currentUser = _firebaseAuth.currentUser;

      if (currentUser != null) {
        print('User already signed in: ${currentUser.email}');

        // User is signed in, fetch their profile to determine user type
        await _fetchUserProfileAndNavigate(currentUser);
      } else {
        // No user is signed in, navigate to sign in screen
        print('No user signed in, navigating to sign in screen');
        if (mounted) {
          Navigator.pushReplacementNamed(context, '/signin');
        }
      }
    } catch (e) {
      print('Error checking auth status: $e');
      // On error, navigate to sign in screen
      if (mounted) {
        Navigator.pushReplacementNamed(context, '/signin');
      }
    }
  }

  Future<void> _fetchUserProfileAndNavigate(firebase.User currentUser) async {
    try {
      // Try multiple approaches to fetch user profile
      Map<String, dynamic>? userProfile;
      String? userType;

      // Approach 1: Try RPC function
      try {
        final rpcData = await _supabase.rpc(
          'get_user_profile',
          params: {'user_id_param': currentUser.uid},
        );

        if (rpcData != null && rpcData.isNotEmpty) {
          userProfile = rpcData[0];
          userType = userProfile?['user_type']?.toString().toLowerCase();
        }
      } catch (rpcError) {
        print('RPC error: $rpcError');
        // Continue to next approach
      }

      // Approach 2: Try direct query
      if (userType == null) {
        try {
          final data = await _supabase
              .from('user_profiles')
              .select('user_type')
              .eq('user_id', currentUser.uid)
              .limit(1)
              .maybeSingle();

          if (data != null) {
            userType = data['user_type']?.toString().toLowerCase();
          }
        } catch (queryError) {
          print('Query error: $queryError');
          // Continue to next approach
        }
      }

      // Approach 3: Try raw SQL query through RPC
      if (userType == null) {
        try {
          final rawData = await _supabase.rpc(
            'get_user_type_by_id',
            params: {'uid': currentUser.uid},
          );

          if (rawData != null) {
            userType = rawData.toString().toLowerCase();
          }
        } catch (rawError) {
          print('Raw query error: $rawError');
        }
      }

      // Update online status
      try {
        final now = DateTime.now().toIso8601String();
        await _supabase
            .from('user_profiles')
            .update({
          'is_online': true,
          'last_active_at': now,
        })
            .eq('user_id', currentUser.uid);
        print('Updated online status to true');
      } catch (updateError) {
        print('Error updating online status: $updateError');
        // Continue even if update fails
      }

      // Navigate based on user type
      if (mounted) {
        if (userType == 'student') {
          print('Navigating to student home screen');
          Navigator.pushReplacementNamed(context, '/student_home');
        } else if (userType == 'counselor') {
          print('Navigating to counselor home screen');
          Navigator.pushReplacementNamed(context, '/counselor_home');
        } else if (userType == 'admin') {
          print('Admin interface not implemented yet');
          Fluttertoast.showToast(
              msg: "Admin interface coming soon",
              toastLength: Toast.LENGTH_LONG,
              gravity: ToastGravity.BOTTOM,
              backgroundColor: Colors.orange,
              textColor: Colors.white,
              fontSize: 16.0
          );
          // For now, go to sign in screen
          Navigator.pushReplacementNamed(context, '/signin');
        } else {
          // Unknown or null user type, go to sign in screen
          print('Unknown user type or error fetching profile: $userType');
          Fluttertoast.showToast(
              msg: "Error determining user type. Please sign in again.",
              toastLength: Toast.LENGTH_LONG,
              gravity: ToastGravity.BOTTOM,
              backgroundColor: Colors.red,
              textColor: Colors.white,
              fontSize: 16.0
          );
          Navigator.pushReplacementNamed(context, '/signin');
        }
      }
    } catch (e) {
      print('Error fetching user profile: $e');
      // On error, navigate to sign in screen
      if (mounted) {
        Navigator.pushReplacementNamed(context, '/signin');
      }
    }
  }

  @override
  void dispose() {
    _animationController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: const SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: Brightness.dark,
        systemNavigationBarColor: Colors.white,
        systemNavigationBarIconBrightness: Brightness.dark,
      ),
      child: Scaffold(
        backgroundColor: Colors.white,
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // Logo animation
              ScaleTransition(
                scale: _animation,
                child: Container(
                  width: 120,
                  height: 120,
                  decoration: BoxDecoration(
                    color: Colors.white,
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color: AppColors.primary.withOpacity(0.2),
                        blurRadius: 15,
                        offset: const Offset(0, 5),
                      ),
                    ],
                  ),
                  child: const Center(
                    child: Text(
                      "ST",
                      style: TextStyle(
                        color: AppColors.primary,
                        fontSize: 48,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 24),
              // App name with fade in animation
              FadeTransition(
                opacity: _animation,
                child: const Text(
                  "SienaTalk",
                  style: TextStyle(
                    fontSize: 32,
                    fontWeight: FontWeight.bold,
                    color: AppColors.textPrimary,
                  ),
                ),
              ),
              const SizedBox(height: 8),
              // Tagline with fade in animation
              FadeTransition(
                opacity: _animation,
                child: const Text(
                  "Connect. Counsel. Succeed.",
                  style: TextStyle(
                    fontSize: 16,
                    color: AppColors.textSecondary,
                  ),
                ),
              ),
              const SizedBox(height: 48),
              // Loading indicator
              const CircularProgressIndicator(
                valueColor: AlwaysStoppedAnimation<Color>(AppColors.primary),
              ),
            ],
          ),
        ),
      ),
    );
  }
}