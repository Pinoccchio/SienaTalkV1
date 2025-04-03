import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart' as firebase;
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:fluttertoast/fluttertoast.dart';

import '../../utils/app_colors.dart';
import '../../widgets/feature_card.dart';

class CounselorHomeScreen extends StatefulWidget {
  const CounselorHomeScreen({Key? key}) : super(key: key);

  @override
  State<CounselorHomeScreen> createState() => _CounselorHomeScreenState();
}

class _CounselorHomeScreenState extends State<CounselorHomeScreen> {
  final firebase.FirebaseAuth _firebaseAuth = firebase.FirebaseAuth.instance;
  final SupabaseClient _supabase = Supabase.instance.client;

  bool _isLoading = true;
  String _userName = "Counselor";
  String? _errorMessage;
  int _activeStudents = 0;
  int _pendingAppointments = 0;

  @override
  void initState() {
    super.initState();
    _loadUserData();
  }

  Future<void> _loadUserData() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final currentUser = _firebaseAuth.currentUser;

      if (currentUser == null) {
        throw Exception('No authenticated user found');
      }

      // Fetch user profile from Supabase
      Map<String, dynamic>? userProfile;

      // Try multiple approaches to fetch user profile
      try {
        // Approach 1: Try RPC function
        try {
          final rpcData = await _supabase.rpc(
            'get_user_profile',
            params: {'user_id_param': currentUser.uid},
          );

          if (rpcData != null && rpcData.isNotEmpty) {
            userProfile = rpcData[0];
          }
        } catch (rpcError) {
          print('RPC error: $rpcError');
          // Continue to next approach
        }

        // Approach 2: Try direct query
        if (userProfile == null) {
          final data = await _supabase
              .from('user_profiles')
              .select('*')
              .eq('user_id', currentUser.uid)
              .limit(1)
              .maybeSingle();

          if (data != null) {
            userProfile = data;
          }
        }

        if (userProfile != null) {
          // Extract user name from profile
          final fullName = userProfile['full_name'] as String? ?? 'Counselor';
          // Get first name only
          final firstName = fullName.split(' ').first;

          setState(() {
            _userName = firstName;
          });

          print('Loaded user profile: $userProfile');
        } else {
          // Use Firebase display name as fallback
          if (currentUser.displayName != null && currentUser.displayName!.isNotEmpty) {
            final firstName = currentUser.displayName!.split(' ').first;
            setState(() {
              _userName = firstName;
            });
          }
        }

        // Fetch active students count (mock data for now)
        _activeStudents = 12;

        // Fetch pending appointments count (mock data for now)
        _pendingAppointments = 5;

      } catch (profileError) {
        print('Error fetching user profile: $profileError');
        // Use Firebase display name as fallback
        if (currentUser.displayName != null && currentUser.displayName!.isNotEmpty) {
          final firstName = currentUser.displayName!.split(' ').first;
          setState(() {
            _userName = firstName;
          });
        }
      }

      setState(() {
        _isLoading = false;
      });

    } catch (e) {
      print('Error loading user data: $e');
      setState(() {
        _errorMessage = 'Failed to load data: $e';
        _isLoading = false;
      });

      Fluttertoast.showToast(
          msg: "Error loading data: $e",
          toastLength: Toast.LENGTH_LONG,
          gravity: ToastGravity.BOTTOM,
          backgroundColor: Colors.red,
          textColor: Colors.white,
          fontSize: 16.0
      );
    }
  }

  // Update only the _signOut method in the CounselorHomeScreen class

  Future<void> _signOut() async {
    try {
      final userId = _firebaseAuth.currentUser?.uid;

      if (userId != null) {
        // Try multiple approaches to update online status
        bool updateSuccess = false;

        // Approach 1: Try RPC function
        try {
          await _supabase.rpc(
            'sign_out_user',
            params: {'user_id_param': userId},
          );
          print('Set user offline via RPC before signing out');
          updateSuccess = true;
        } catch (rpcError) {
          print('RPC error: $rpcError');
          // Continue to next approach
        }

        // Approach 2: Try direct update if RPC failed
        if (!updateSuccess) {
          try {
            final now = DateTime.now().toIso8601String();
            final response = await _supabase
                .from('user_profiles')
                .update({
              'is_online': false,
              'last_active_at': now,
            })
                .eq('user_id', userId);
            print('Set user offline via direct update: $response');
            updateSuccess = true;
          } catch (updateError) {
            print('Direct update error: $updateError');
          }
        }

        // Approach 3: Try raw SQL through another RPC if all else fails
        if (!updateSuccess) {
          try {
            await _supabase.rpc(
              'execute_raw_update',
              params: {
                'query_text': "UPDATE user_profiles SET is_online = false, last_active_at = NOW() WHERE user_id = '$userId'"
              },
            );
            print('Set user offline via raw SQL');
          } catch (rawError) {
            print('Raw SQL error: $rawError');
          }
        }
      }

      // Sign out from Firebase regardless of status update success
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
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_errorMessage != null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.error_outline, size: 48, color: Colors.red),
            const SizedBox(height: 16),
            Text(
              'Error loading data',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Text(_errorMessage ?? 'Unknown error'),
            const SizedBox(height: 24),
            ElevatedButton(
              onPressed: _loadUserData,
              child: const Text('Retry'),
            ),
          ],
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Counselor Dashboard'),
        backgroundColor: AppColors.counselorColor,
        actions: [
          IconButton(
            icon: const Icon(Icons.notifications_outlined),
            onPressed: () {
              Fluttertoast.showToast(
                msg: "Notifications coming soon!",
                toastLength: Toast.LENGTH_SHORT,
                gravity: ToastGravity.BOTTOM,
              );
            },
          ),
          IconButton(
            icon: const Icon(Icons.settings_outlined),
            onPressed: () {
              Fluttertoast.showToast(
                msg: "Settings coming soon!",
                toastLength: Toast.LENGTH_SHORT,
                gravity: ToastGravity.BOTTOM,
              );
            },
          ),
        ],
      ),
      drawer: Drawer(
        child: ListView(
          padding: EdgeInsets.zero,
          children: [
            DrawerHeader(
              decoration: const BoxDecoration(
                color: AppColors.counselorColor,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const CircleAvatar(
                    radius: 30,
                    backgroundColor: Colors.white,
                    child: Icon(
                      Icons.person,
                      size: 30,
                      color: AppColors.counselorColor,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    'Dr. $_userName',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const Text(
                    'Counselor',
                    style: TextStyle(
                      color: Colors.white70,
                      fontSize: 14,
                    ),
                  ),
                ],
              ),
            ),
            ListTile(
              leading: const Icon(Icons.dashboard_outlined),
              title: const Text('Dashboard'),
              selected: true,
              selectedTileColor: AppColors.counselorColor.withOpacity(0.1),
              onTap: () {
                Navigator.pop(context);
              },
            ),
            ListTile(
              leading: const Icon(Icons.people_outline),
              title: const Text('My Students'),
              onTap: () {
                Navigator.pop(context);
                Fluttertoast.showToast(
                  msg: "Students list coming soon!",
                  toastLength: Toast.LENGTH_SHORT,
                  gravity: ToastGravity.BOTTOM,
                );
              },
            ),
            ListTile(
              leading: const Icon(Icons.calendar_today_outlined),
              title: const Text('Appointments'),
              onTap: () {
                Navigator.pop(context);
                Fluttertoast.showToast(
                  msg: "Appointments coming soon!",
                  toastLength: Toast.LENGTH_SHORT,
                  gravity: ToastGravity.BOTTOM,
                );
              },
            ),
            ListTile(
              leading: const Icon(Icons.chat_outlined),
              title: const Text('Messages'),
              onTap: () {
                Navigator.pop(context);
                Fluttertoast.showToast(
                  msg: "Messages coming soon!",
                  toastLength: Toast.LENGTH_SHORT,
                  gravity: ToastGravity.BOTTOM,
                );
              },
            ),
            const Divider(),
            ListTile(
              leading: const Icon(Icons.help_outline),
              title: const Text('Help & Support'),
              onTap: () {
                Navigator.pop(context);
                Fluttertoast.showToast(
                  msg: "Help & Support coming soon!",
                  toastLength: Toast.LENGTH_SHORT,
                  gravity: ToastGravity.BOTTOM,
                );
              },
            ),
            ListTile(
              leading: const Icon(Icons.logout),
              title: const Text('Sign Out'),
              onTap: _signOut,
            ),
          ],
        ),
      ),
      body: RefreshIndicator(
        onRefresh: _loadUserData,
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          child: Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Welcome message
                Text(
                  'Welcome, Dr. $_userName!',
                  style: const TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                    color: AppColors.textPrimary,
                  ),
                ),
                const SizedBox(height: 8),
                const Text(
                  'Here\'s your dashboard overview',
                  style: TextStyle(
                    fontSize: 16,
                    color: AppColors.textSecondary,
                  ),
                ),
                const SizedBox(height: 24),

                // Stats cards
                Row(
                  children: [
                    Expanded(
                      child: _buildStatCard(
                        title: 'Active Students',
                        value: _activeStudents.toString(),
                        icon: Icons.people,
                        color: AppColors.counselorColor,
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: _buildStatCard(
                        title: 'Pending Appointments',
                        value: _pendingAppointments.toString(),
                        icon: Icons.calendar_today,
                        color: Colors.orange,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 24),

                // Today's appointments
                const Text(
                  'Today\'s Appointments',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: AppColors.textPrimary,
                  ),
                ),
                const SizedBox(height: 16),

                // Appointment list
                _buildAppointmentList(),
                const SizedBox(height: 24),

                // Quick actions
                const Text(
                  'Quick Actions',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: AppColors.textPrimary,
                  ),
                ),
                const SizedBox(height: 16),

                // Feature cards
                Row(
                  children: [
                    Expanded(
                      child: FeatureCard(
                        icon: Icons.chat_bubble_outlined,
                        title: 'Message Students',
                        onTap: () {
                          Fluttertoast.showToast(
                            msg: "Messaging feature coming soon!",
                            toastLength: Toast.LENGTH_SHORT,
                            gravity: ToastGravity.BOTTOM,
                          );
                        },
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: FeatureCard(
                        icon: Icons.calendar_today_outlined,
                        title: 'Schedule Appointments',
                        onTap: () {
                          Fluttertoast.showToast(
                            msg: "Scheduling feature coming soon!",
                            toastLength: Toast.LENGTH_SHORT,
                            gravity: ToastGravity.BOTTOM,
                          );
                        },
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(
                      child: FeatureCard(
                        icon: Icons.assessment_outlined,
                        title: 'Student Reports',
                        onTap: () {
                          Fluttertoast.showToast(
                            msg: "Reports feature coming soon!",
                            toastLength: Toast.LENGTH_SHORT,
                            gravity: ToastGravity.BOTTOM,
                          );
                        },
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: FeatureCard(
                        icon: Icons.article_outlined,
                        title: 'Resources',
                        onTap: () {
                          Fluttertoast.showToast(
                            msg: "Resources feature coming soon!",
                            toastLength: Toast.LENGTH_SHORT,
                            gravity: ToastGravity.BOTTOM,
                          );
                        },
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 24),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildStatCard({
    required String title,
    required String value,
    required IconData icon,
    required Color color,
  }) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                icon,
                color: color,
                size: 24,
              ),
              const Spacer(),
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: color.withOpacity(0.1),
                  shape: BoxShape.circle,
                ),
                child: Text(
                  value,
                  style: TextStyle(
                    color: color,
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            title,
            style: const TextStyle(
              color: AppColors.textSecondary,
              fontSize: 14,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAppointmentList() {
    // Mock data for appointments
    final appointments = [
      {
        'name': 'John Doe',
        'time': '10:00 AM',
        'status': 'Confirmed',
        'avatar': 'J',
      },
      {
        'name': 'Jane Smith',
        'time': '11:30 AM',
        'status': 'Pending',
        'avatar': 'J',
      },
      {
        'name': 'Mike Johnson',
        'time': '2:00 PM',
        'status': 'Confirmed',
        'avatar': 'M',
      },
    ];

    if (appointments.isEmpty) {
      return const Card(
        child: Padding(
          padding: EdgeInsets.all(16.0),
          child: Center(
            child: Text(
              'No appointments scheduled for today',
              style: TextStyle(
                color: AppColors.textSecondary,
              ),
            ),
          ),
        ),
      );
    }

    return Column(
      children: appointments.map((appointment) {
        final isConfirmed = appointment['status'] == 'Confirmed';

        return Card(
          margin: const EdgeInsets.only(bottom: 12),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          child: Padding(
            padding: const EdgeInsets.all(16.0),
            child: Row(
              children: [
                CircleAvatar(
                  backgroundColor: AppColors.counselorColor.withOpacity(0.2),
                  child: Text(
                    appointment['avatar'] as String,
                    style: const TextStyle(
                      color: AppColors.counselorColor,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        appointment['name'] as String,
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                        ),
                      ),
                      Text(
                        appointment['time'] as String,
                        style: const TextStyle(
                          color: AppColors.textSecondary,
                        ),
                      ),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: isConfirmed
                        ? Colors.green.withOpacity(0.1)
                        : Colors.orange.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    appointment['status'] as String,
                    style: TextStyle(
                      color: isConfirmed ? Colors.green : Colors.orange,
                      fontWeight: FontWeight.bold,
                      fontSize: 12,
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      }).toList(),
    );
  }
}