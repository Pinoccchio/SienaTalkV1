import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart' as firebase;
import 'package:sienatalk/screens/counselor/counselor_chat_screen.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:fluttertoast/fluttertoast.dart';
import '../../utils/app_colors.dart';
import 'counselor_home_screen.dart';
import 'counselor_appointments_screen.dart';
import 'counselor_student_screen.dart';

class CounselorContainer extends StatefulWidget {
  const CounselorContainer({Key? key}) : super(key: key);

  @override
  State<CounselorContainer> createState() => _CounselorContainerState();
}

class _CounselorContainerState extends State<CounselorContainer> with WidgetsBindingObserver {
  int _currentIndex = 0;
  final firebase.FirebaseAuth _firebaseAuth = firebase.FirebaseAuth.instance;
  final SupabaseClient _supabase = Supabase.instance.client;
  bool _isAppInBackground = false;
  DateTime? _lastBackgroundTime;

  // Method to navigate to a specific tab
  void _navigateToTab(int index) {
    setState(() {
      _currentIndex = index;
    });
  }

  @override
  void initState() {
    super.initState();
    // Register observer for app lifecycle changes
    WidgetsBinding.instance.addObserver(this);
    // Set user as online when app starts
    _updateOnlineStatus(true);
  }

  @override
  void dispose() {
    // Remove observer when widget is disposed
    WidgetsBinding.instance.removeObserver(this);
    // Set user as offline when widget is disposed
    _updateOnlineStatus(false);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);

    // Handle app lifecycle state changes
    switch (state) {
      case AppLifecycleState.resumed:
      // App is in the foreground and visible to the user
        if (_isAppInBackground) {
          _isAppInBackground = false;

          // If app was in background for more than 5 minutes, update last_active_at
          if (_lastBackgroundTime != null) {
            final now = DateTime.now();
            final difference = now.difference(_lastBackgroundTime!);
            if (difference.inMinutes >= 5) {
              _updateLastActiveTime();
            }
          }

          // Set user as online
          _updateOnlineStatus(true);
        }
        break;

      case AppLifecycleState.inactive:
      // App is inactive, might be switching between apps
        break;

      case AppLifecycleState.paused:
      // App is in the background
        _isAppInBackground = true;
        _lastBackgroundTime = DateTime.now();

        // Set user as offline when app goes to background
        _updateOnlineStatus(false);
        break;

      case AppLifecycleState.detached:
      // App is detached (terminated)
        _updateOnlineStatus(false);
        break;

      default:
        break;
    }
  }

  Future<void> _updateOnlineStatus(bool isOnline) async {
    final currentUser = _firebaseAuth.currentUser;
    if (currentUser == null) return;

    final userId = currentUser.uid;
    final now = DateTime.now().toIso8601String();

    try {
      print('Updating online status to: $isOnline');

      // Try RPC function first
      try {
        await _supabase.rpc(
          'update_user_online_status',
          params: {
            'user_id_param': userId,
            'is_online_param': isOnline,
            'last_active_param': now
          },
        );
      } catch (rpcError) {
        print('RPC error: $rpcError');

        // Fallback to direct update
        await _supabase
            .from('user_profiles')
            .update({
          'is_online': isOnline,
          'last_active_at': now,
        })
            .eq('user_id', userId);
      }
    } catch (e) {
      print('Error updating online status: $e');
    }
  }

  Future<void> _updateLastActiveTime() async {
    final currentUser = _firebaseAuth.currentUser;
    if (currentUser == null) return;

    final userId = currentUser.uid;
    final now = DateTime.now().toIso8601String();

    try {
      await _supabase
          .from('user_profiles')
          .update({'last_active_at': now})
          .eq('user_id', userId);
    } catch (e) {
      print('Error updating last active time: $e');
    }
  }

  Future<void> _signOut() async {
    try {
      // Set user offline before signing out
      await _updateOnlineStatus(false);

      // Sign out from Firebase
      await _firebaseAuth.signOut();

      // Navigate to sign in screen
      if (mounted) {
        Navigator.pushReplacementNamed(context, '/signin');
      }
    } catch (e) {
      print('Error signing out: $e');
      Fluttertoast.showToast(
        msg: "Error signing out: $e",
        toastLength: Toast.LENGTH_LONG,
        gravity: ToastGravity.BOTTOM,
        backgroundColor: Colors.red,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    // Create screens list with navigation callback for the home screen
    final List<Widget> screens = [
      CounselorHomeScreen(onNavigate: _navigateToTab),
      const CounselorStudentsScreen(),
      const CounselorAppointmentsScreen(),
      const CounselorChatScreen(),
    ];

    return Scaffold(
      body: screens[_currentIndex],
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _currentIndex,
        onTap: _navigateToTab,
        type: BottomNavigationBarType.fixed,
        selectedItemColor: AppColors.counselorColor,
        unselectedItemColor: Colors.grey,
        items: const [
          BottomNavigationBarItem(
            icon: Icon(Icons.dashboard_outlined),
            activeIcon: Icon(Icons.dashboard),
            label: 'Dashboard',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.people_outline),
            activeIcon: Icon(Icons.people),
            label: 'Students',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.calendar_today_outlined),
            activeIcon: Icon(Icons.calendar_today),
            label: 'Appointments',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.chat_outlined),
            activeIcon: Icon(Icons.chat),
            label: 'Messages',
          ),
        ],
      ),
    );
  }
}

