import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart' as firebase;
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:fluttertoast/fluttertoast.dart';
import '../../utils/app_colors.dart';
import 'counselor_home_screen.dart';
import 'counselor_appointments_screen.dart';
import 'counselor_messages_screen.dart';
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

  final List<Widget> _screens = [
    const CounselorHomeScreen(),
    const CounselorStudentsScreen(),
    const CounselorAppointmentsScreen(),
    const CounselorMessagesScreen(),
  ];

  @override
  void initState() {
    super.initState();
    // Register observer for app lifecycle changes
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    // Remove observer when widget is disposed
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Handle app lifecycle changes
    final userId = _firebaseAuth.currentUser?.uid;
    if (userId == null) return;

    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.detached ||
        state == AppLifecycleState.inactive) {
      // App is in background or closed, update status to offline
      _updateUserOfflineStatus(userId);
    } else if (state == AppLifecycleState.resumed) {
      // App is in foreground, update status to online
      _updateUserOnlineStatus(userId);
    }
  }

  Future<void> _updateUserOnlineStatus(String userId) async {
    try {
      final now = DateTime.now().toIso8601String();
      await _supabase
          .from('user_profiles')
          .update({
        'is_online': true,
        'last_active_at': now,
      })
          .eq('user_id', userId);
      print('Updated online status to true');
    } catch (e) {
      print('Error updating online status: $e');
    }
  }

  Future<void> _updateUserOfflineStatus(String userId) async {
    try {
      // Use direct update as a fallback approach
      final now = DateTime.now().toIso8601String();
      await _supabase
          .from('user_profiles')
          .update({
        'is_online': false,
        'last_active_at': now,
      })
          .eq('user_id', userId);
      print('Updated online status to false via direct update');
    } catch (e) {
      print('Error updating offline status: $e');
    }
  }

  Future<void> _signOut() async {
    try {
      final userId = _firebaseAuth.currentUser?.uid;

      if (userId != null) {
        // Try to update the online status before signing out
        try {
          final now = DateTime.now().toIso8601String();
          await _supabase
              .from('user_profiles')
              .update({
            'is_online': false,
            'last_active_at': now,
          })
              .eq('user_id', userId);
          print('Set user offline before signing out');
        } catch (e) {
          print('Error updating online status: $e');
          // Continue with sign out even if update fails
        }
      }

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
    return Scaffold(
      body: _screens[_currentIndex],
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _currentIndex,
        onTap: (index) {
          setState(() {
            _currentIndex = index;
          });
        },
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