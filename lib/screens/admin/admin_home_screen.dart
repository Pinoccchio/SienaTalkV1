import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart' as firebase;
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:fluttertoast/fluttertoast.dart';
import '../../utils/app_colors.dart';
import '../../widgets/feature_card.dart';
import 'admin_students_screen.dart';

class AdminHomeScreen extends StatefulWidget {
  final Function(int)? onNavigate;

  const AdminHomeScreen({Key? key, this.onNavigate}) : super(key: key);

  @override
  State<AdminHomeScreen> createState() => _AdminHomeScreenState();
}

class _AdminHomeScreenState extends State<AdminHomeScreen> {
  final firebase.FirebaseAuth _firebaseAuth = firebase.FirebaseAuth.instance;
  final SupabaseClient _supabase = Supabase.instance.client;

  bool _isLoading = true;
  String _userName = "Admin";
  String? _errorMessage;
  int _totalCounselors = 0;
  int _totalStudents = 0;
  int _activeConversations = 0;
  int _totalAppointments = 0;

  @override
  void initState() {
    super.initState();
    _loadUserData();
    _loadDashboardStats();
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
          final fullName = userProfile['full_name'] as String? ?? 'Admin';
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

  Future<void> _loadDashboardStats() async {
    try {
      // Load total counselors count
      final counselorsData = await _supabase
          .from('user_profiles')
          .select('user_id')
          .eq('user_type', 'counselor');

      setState(() {
        _totalCounselors = counselorsData.length;
      });

      // Load total students count
      final studentsData = await _supabase
          .from('user_profiles')
          .select('user_id')
          .eq('user_type', 'student');

      setState(() {
        _totalStudents = studentsData.length;
      });

      // Load active conversations (unique student-counselor pairs with messages)
      try {
        // Get distinct sender-receiver pairs from messages
        final conversationsData = await _supabase
            .from('messages')
            .select('sender_id, receiver_id')
            .order('created_at', ascending: false)
            .limit(100);

        // Count unique conversations
        final Set<String> uniqueConversations = {};
        for (var message in conversationsData) {
          final senderId = message['sender_id'] as String;
          final receiverId = message['receiver_id'] as String;

          // Create a unique key for each conversation (sorted to ensure same key regardless of who sent/received)
          final participants = [senderId, receiverId]..sort();
          final conversationKey = '${participants[0]}_${participants[1]}';

          uniqueConversations.add(conversationKey);
        }

        setState(() {
          _activeConversations = uniqueConversations.length;
        });
      } catch (e) {
        print('Error loading active conversations count: $e');
        setState(() {
          _activeConversations = 0;
        });
      }

      // Load total appointments count
      final appointmentsData = await _supabase
          .from('appointments')
          .select('id');

      setState(() {
        _totalAppointments = appointmentsData.length;
      });

    } catch (e) {
      print('Error loading dashboard stats: $e');
      Fluttertoast.showToast(
        msg: "Error loading statistics: $e",
        toastLength: Toast.LENGTH_SHORT,
        gravity: ToastGravity.BOTTOM,
        backgroundColor: Colors.red,
      );
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  void _navigateToStudentsScreen() {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (context) => const AdminStudentsScreen()),
    );
  }

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
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    if (_errorMessage != null) {
      return Scaffold(
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.error_outline, size: 48, color: Colors.red),
              const SizedBox(height: 16),
              const Text(
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
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Admin Dashboard',
          style: TextStyle(color: Colors.white),
        ),
        backgroundColor: AppColors.adminColor,
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      drawer: Drawer(
        child: ListView(
          padding: EdgeInsets.zero,
          children: [
            DrawerHeader(
              decoration: const BoxDecoration(
                color: AppColors.adminColor,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const CircleAvatar(
                    radius: 30,
                    backgroundColor: Colors.white,
                    child: Icon(
                      Icons.admin_panel_settings,
                      size: 30,
                      color: AppColors.adminColor,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    _userName,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const Text(
                    'Administrator',
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
              selectedTileColor: AppColors.adminColor.withOpacity(0.1),
              onTap: () {
                Navigator.pop(context);
                if (widget.onNavigate != null) {
                  widget.onNavigate!(0); // Dashboard
                }
              },
            ),
            ListTile(
              leading: const Icon(Icons.bar_chart_outlined),
              title: const Text('Statistics'),
              onTap: () {
                Navigator.pop(context);
                if (widget.onNavigate != null) {
                  widget.onNavigate!(1); // Statistics
                }
              },
            ),
            ListTile(
              leading: const Icon(Icons.people_outline),
              title: const Text('Counselors'),
              onTap: () {
                Navigator.pop(context);
                if (widget.onNavigate != null) {
                  widget.onNavigate!(2); // Counselors
                }
              },
            ),
            ListTile(
              leading: const Icon(Icons.chat_outlined),
              title: const Text('Chats'),
              onTap: () {
                Navigator.pop(context);
                if (widget.onNavigate != null) {
                  widget.onNavigate!(3); // Chats
                }
              },
            ),
            ListTile(
              leading: const Icon(Icons.calendar_today_outlined),
              title: const Text('Appointments'),
              onTap: () {
                Navigator.pop(context);
                if (widget.onNavigate != null) {
                  widget.onNavigate!(4); // Appointments
                }
              },
            ),
            const Divider(),
            ListTile(
              leading: const Icon(Icons.logout),
              title: const Text('Sign Out'),
              onTap: _signOut,
            ),
          ],
        ),
      ),
      body: RefreshIndicator(
        onRefresh: () async {
          await Future.wait([
            _loadUserData(),
            _loadDashboardStats(),
          ]);
        },
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          child: Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Welcome message
                Text(
                  'Welcome, $_userName!',
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
                GridView.count(
                  crossAxisCount: 2,
                  crossAxisSpacing: 16,
                  mainAxisSpacing: 16,
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  children: [
                    _buildStatCard(
                      title: 'Total Counselors',
                      value: _totalCounselors.toString(),
                      icon: Icons.people,
                      color: AppColors.counselorColor,
                      onTap: () {
                        if (widget.onNavigate != null) {
                          widget.onNavigate!(2); // Navigate to Counselors tab
                        }
                      },
                    ),
                    _buildStatCard(
                      title: 'Total Students',
                      value: _totalStudents.toString(),
                      icon: Icons.school,
                      color: AppColors.studentColor,
                      onTap: _navigateToStudentsScreen,
                    ),
                    _buildStatCard(
                      title: 'Active Conversations',
                      value: _activeConversations.toString(),
                      icon: Icons.chat,
                      color: Colors.teal,
                      onTap: () {
                        if (widget.onNavigate != null) {
                          widget.onNavigate!(3); // Navigate to Chats tab
                        }
                      },
                    ),
                    _buildStatCard(
                      title: 'Total Appointments',
                      value: _totalAppointments.toString(),
                      icon: Icons.calendar_today,
                      color: Colors.purple,
                      onTap: () {
                        if (widget.onNavigate != null) {
                          widget.onNavigate!(4); // Navigate to Appointments tab
                        }
                      },
                    ),
                  ],
                ),
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
                        icon: Icons.people,
                        title: 'Manage Counselors',
                        onTap: () {
                          if (widget.onNavigate != null) {
                            widget.onNavigate!(2); // Navigate to Counselors tab
                          }
                        },
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: FeatureCard(
                        icon: Icons.bar_chart,
                        title: 'View Statistics',
                        onTap: () {
                          if (widget.onNavigate != null) {
                            widget.onNavigate!(1); // Navigate to Statistics tab
                          }
                        },
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),

                // Second row of feature cards
                Row(
                  children: [
                    Expanded(
                      child: FeatureCard(
                        icon: Icons.chat,
                        title: 'View Chats',
                        onTap: () {
                          if (widget.onNavigate != null) {
                            widget.onNavigate!(3); // Navigate to Chats tab
                          }
                        },
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: FeatureCard(
                        icon: Icons.calendar_today,
                        title: 'Manage Appointments',
                        onTap: () {
                          if (widget.onNavigate != null) {
                            widget.onNavigate!(4); // Navigate to Appointments tab
                          }
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
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
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
            const Spacer(),
            Text(
              title,
              style: const TextStyle(
                color: AppColors.textSecondary,
                fontSize: 14,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

