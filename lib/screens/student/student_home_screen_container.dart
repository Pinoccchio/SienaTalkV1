import 'package:flutter/material.dart';
import '../../utils/app_colors.dart';
import 'student_home_screen.dart';
import 'student_chat_screen.dart';
import 'student_appointments_screen.dart';
import 'student_profile_screen.dart';

class StudentHomeScreenContainer extends StatefulWidget {
  const StudentHomeScreenContainer({Key? key}) : super(key: key);

  @override
  State<StudentHomeScreenContainer> createState() => _StudentHomeScreenContainerState();
}

class _StudentHomeScreenContainerState extends State<StudentHomeScreenContainer> {
  int _currentIndex = 0;

  // Method to navigate to a specific tab
  void _navigateToTab(int index) {
    setState(() {
      _currentIndex = index;
    });
  }

  @override
  Widget build(BuildContext context) {
    // Create screens list with navigation callback for the home screen
    final List<Widget> screens = [
      StudentHomeScreen(onNavigate: _navigateToTab),
      const StudentChatScreen(),
      const StudentAppointmentsScreen(),
      const StudentProfileScreen(),
    ];

    return Scaffold(
      // AppBar removed from here - each screen will have its own AppBar
      body: screens[_currentIndex],
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _currentIndex,
        onTap: _navigateToTab,
        type: BottomNavigationBarType.fixed,
        backgroundColor: Colors.white,
        selectedItemColor: AppColors.primary,
        unselectedItemColor: Colors.grey,
        selectedLabelStyle: const TextStyle(fontWeight: FontWeight.w600),
        unselectedLabelStyle: const TextStyle(fontWeight: FontWeight.w600),
        items: const [
          BottomNavigationBarItem(
            icon: Icon(Icons.home_outlined),
            activeIcon: Icon(Icons.home),
            label: 'Home',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.chat_bubble_outline),
            activeIcon: Icon(Icons.chat_bubble),
            label: 'Chat',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.calendar_today_outlined),
            activeIcon: Icon(Icons.calendar_today),
            label: 'Appointments',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.person_outline),
            activeIcon: Icon(Icons.person),
            label: 'Profile',
          ),
        ],
      ),
    );
  }
}