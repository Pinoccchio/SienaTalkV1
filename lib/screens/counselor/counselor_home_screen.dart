import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart' as firebase;
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:fluttertoast/fluttertoast.dart';
import 'package:intl/intl.dart';

import '../../utils/app_colors.dart';
import '../../widgets/feature_card.dart';

class CounselorHomeScreen extends StatefulWidget {
  final Function(int)? onNavigate;

  const CounselorHomeScreen({Key? key, this.onNavigate}) : super(key: key);

  @override
  State<CounselorHomeScreen> createState() => _CounselorHomeScreenState();
}

class _CounselorHomeScreenState extends State<CounselorHomeScreen> {
  final firebase.FirebaseAuth _firebaseAuth = firebase.FirebaseAuth.instance;
  final SupabaseClient _supabase = Supabase.instance.client;

  bool _isLoading = true;
  String _userName = "Counselor";
  String? _errorMessage;
  int _onlineStudents = 0;
  int _offlineStudents = 0;
  int _totalStudents = 0;
  int _pendingAppointments = 0;
  List<Map<String, dynamic>> _todayAppointments = [];

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

        // Load active students count
        await _loadStudentsCounts(currentUser.uid);

        // Load pending appointments count
        await _loadPendingAppointmentsCount(currentUser.uid);

        // Load today's appointments
        await _loadTodayAppointments(currentUser.uid);

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

      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }

    } catch (e) {
      print('Error loading user data: $e');
      if (mounted) {
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
  }

  Future<void> _loadStudentsCounts(String counselorId) async {
    try {
      // Get all students who have had appointments with this counselor
      final appointmentsData = await _supabase
          .from('appointments')
          .select('student_id')
          .eq('counselor_id', counselorId)
          .not('status', 'eq', 'cancelled');

      // Extract unique student IDs
      final studentIds = appointmentsData
          .map((appointment) => appointment['student_id'] as String?)
          .where((id) => id != null)
          .toSet();

      // Get all student profiles
      List<Map<String, dynamic>> studentsData = [];
      if (studentIds.isNotEmpty) {
        // Convert Set to List for the query
        final studentIdsList = studentIds.toList();

        // Fetch all student profiles that match our student IDs
        studentsData = await _supabase
            .from('user_profiles')
            .select('user_id, is_online')
            .eq('user_type', 'student')
            .filter('user_id', 'in', studentIdsList);
      }

      // Count online and offline students
      int onlineCount = 0;
      int offlineCount = 0;

      for (var student in studentsData) {
        final isOnline = student['is_online'] as bool? ?? false;
        if (isOnline) {
          onlineCount++;
        } else {
          offlineCount++;
        }
      }

      if (mounted) {
        setState(() {
          _onlineStudents = onlineCount;
          _offlineStudents = offlineCount;
          _totalStudents = studentsData.length;
        });
      }
    } catch (e) {
      print('Error loading students counts: $e');
      // Set default values in case of error
      if (mounted) {
        setState(() {
          _onlineStudents = 0;
          _offlineStudents = 0;
          _totalStudents = 0;
        });
      }
    }
  }

  Future<void> _loadPendingAppointmentsCount(String counselorId) async {
    try {
      // Get count of pending appointments for this counselor
      final data = await _supabase
          .from('appointments')
          .select('id')
          .eq('counselor_id', counselorId)
          .eq('status', 'pending');

      if (mounted) {
        setState(() {
          _pendingAppointments = data.length;
        });
      }
    } catch (e) {
      print('Error loading pending appointments count: $e');
      // Set a default value in case of error
      if (mounted) {
        setState(() {
          _pendingAppointments = 0;
        });
      }
    }
  }

  Future<void> _loadTodayAppointments(String counselorId) async {
    try {
      // Get today's date range - this ensures it's always the current day
      final now = DateTime.now();
      final today = DateTime(now.year, now.month, now.day);
      final tomorrow = today.add(const Duration(days: 1));

      final todayStart = today.toIso8601String();
      final todayEnd = tomorrow.toIso8601String();

      // Get appointments for today
      final appointmentsData = await _supabase
          .from('appointments')
          .select('*, student_id, is_anonymous')
          .eq('counselor_id', counselorId)
          .gte('appointment_date', todayStart)
          .lt('appointment_date', todayEnd)
          .order('appointment_date');

      // Fetch student details for each appointment
      List<Map<String, dynamic>> appointments = [];
      for (var appointment in appointmentsData) {
        final studentId = appointment['student_id'] as String?;
        final isAnonymous = appointment['is_anonymous'] as bool? ?? false;

        if (studentId != null) {
          try {
            final appointmentWithStudent = Map<String, dynamic>.from(appointment);

            if (isAnonymous) {
              // For anonymous appointments, hide student identity
              appointmentWithStudent['student_name'] = 'Anonymous Student';
              appointmentWithStudent['avatar'] = 'A';
            } else {
              // For regular appointments, fetch and show student name
              final studentData = await _supabase
                  .from('user_profiles')
                  .select('full_name')
                  .eq('user_id', studentId)
                  .single();

              appointmentWithStudent['student_name'] = studentData['full_name'] ?? 'Unknown Student';
              appointmentWithStudent['avatar'] = studentData['full_name']?.toString().isNotEmpty == true
                  ? studentData['full_name'].toString()[0].toUpperCase()
                  : 'S';
            }

            appointments.add(appointmentWithStudent);
          } catch (e) {
            print('Error fetching student details: $e');
            // Add appointment with default student name
            final appointmentWithStudent = Map<String, dynamic>.from(appointment);

            if (isAnonymous) {
              appointmentWithStudent['student_name'] = 'Anonymous Student';
              appointmentWithStudent['avatar'] = 'A';
            } else {
              appointmentWithStudent['student_name'] = 'Unknown Student';
              appointmentWithStudent['avatar'] = 'S';
            }

            appointments.add(appointmentWithStudent);
          }
        }
      }

      if (mounted) {
        setState(() {
          _todayAppointments = appointments;
        });
      }
    } catch (e) {
      print('Error loading today\'s appointments: $e');
      // Set an empty list in case of error
      if (mounted) {
        setState(() {
          _todayAppointments = [];
        });
      }
    }
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
          'Counselor Dashboard',
          style: TextStyle(color: Colors.white),
        ),
        backgroundColor: AppColors.counselorColor,
        iconTheme: const IconThemeData(color: Colors.white), // This makes the menu icon white
        actions: [
          // Commented out notification and settings icons as requested
          // IconButton(
          //   icon: const Icon(Icons.notifications_outlined),
          //   onPressed: () {
          //     Fluttertoast.showToast(
          //       msg: "Notifications coming soon!",
          //       toastLength: Toast.LENGTH_SHORT,
          //       gravity: ToastGravity.BOTTOM,
          //     );
          //   },
          // ),
          // IconButton(
          //   icon: const Icon(Icons.settings_outlined),
          //   onPressed: () {
          //     Fluttertoast.showToast(
          //       msg: "Settings coming soon!",
          //       toastLength: Toast.LENGTH_SHORT,
          //       gravity: ToastGravity.BOTTOM,
          //     );
          //   },
          // ),
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
                    _userName,
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
                if (widget.onNavigate != null) {
                  widget.onNavigate!(0);
                }
              },
            ),
            ListTile(
              leading: const Icon(Icons.people_outline),
              title: const Text('My Students'),
              onTap: () {
                Navigator.pop(context);
                if (widget.onNavigate != null) {
                  widget.onNavigate!(1);
                }
              },
            ),
            ListTile(
              leading: const Icon(Icons.calendar_today_outlined),
              title: const Text('Appointments'),
              onTap: () {
                Navigator.pop(context);
                if (widget.onNavigate != null) {
                  widget.onNavigate!(2);
                }
              },
            ),
            ListTile(
              leading: const Icon(Icons.chat_outlined),
              title: const Text('Messages'),
              onTap: () {
                Navigator.pop(context);
                if (widget.onNavigate != null) {
                  widget.onNavigate!(3);
                }
              },
            ),
            const Divider(),
            // Removed Help & Support option as requested
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
                Row(
                  children: [
                    Expanded(
                      child: GestureDetector(
                        onTap: () {
                          if (widget.onNavigate != null) {
                            widget.onNavigate!(1); // Navigate to Students tab
                          }
                        },
                        child: _buildStudentsCard(),
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: GestureDetector(
                        onTap: () {
                          if (widget.onNavigate != null) {
                            widget.onNavigate!(2); // Navigate to Appointments tab
                          }
                        },
                        child: _buildStatCard(
                          title: 'Pending Appointments',
                          value: _pendingAppointments.toString(),
                          icon: Icons.calendar_today,
                          color: Colors.orange,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 24),

                // Today's appointments
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text(
                      'Today\'s Appointments',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: AppColors.textPrimary,
                      ),
                    ),
                    if (_todayAppointments.isNotEmpty)
                      TextButton(
                        onPressed: () {
                          if (widget.onNavigate != null) {
                            widget.onNavigate!(2); // Navigate to Appointments tab
                          }
                        },
                        child: const Text(
                          'View All',
                          style: TextStyle(
                            color: AppColors.counselorColor,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                  ],
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
                          if (widget.onNavigate != null) {
                            widget.onNavigate!(3); // Navigate to Messages tab
                          }
                        },
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: FeatureCard(
                        icon: Icons.calendar_today_outlined,
                        title: 'Schedule Appointments',
                        onTap: () {
                          if (widget.onNavigate != null) {
                            widget.onNavigate!(2); // Navigate to Appointments tab
                          }
                        },
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 24), // Increased height to add more space at the bottom
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildStudentsCard() {
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
              const Icon(
                Icons.people,
                color: AppColors.counselorColor,
                size: 24,
              ),
              const Spacer(),
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: AppColors.counselorColor.withOpacity(0.1),
                  shape: BoxShape.circle,
                ),
                child: Text(
                  _totalStudents.toString(),
                  style: const TextStyle(
                    color: AppColors.counselorColor,
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          const Text(
            'My Students',
            style: TextStyle(
              color: AppColors.textSecondary,
              fontSize: 14,
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              _buildStatusIndicator(
                count: _onlineStudents,
                label: 'Online',
                color: Colors.green,
              ),
              const SizedBox(width: 12),
              _buildStatusIndicator(
                count: _offlineStudents,
                label: 'Offline',
                color: Colors.grey,
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildStatusIndicator({
    required int count,
    required String label,
    required Color color,
  }) {
    return Row(
      children: [
        Container(
          width: 10,
          height: 10,
          decoration: BoxDecoration(
            color: color,
            shape: BoxShape.circle,
          ),
        ),
        const SizedBox(width: 4),
        Text(
          '$count $label',
          style: TextStyle(
            fontSize: 12,
            color: color,
            fontWeight: FontWeight.bold,
          ),
        ),
      ],
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
    if (_todayAppointments.isEmpty) {
      return Card(
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Center(
            child: Column(
              children: [
                Icon(
                  Icons.event_busy,
                  size: 48,
                  color: Colors.grey.shade400,
                ),
                const SizedBox(height: 16),
                const Text(
                  'No appointments scheduled for today',
                  style: TextStyle(
                    color: AppColors.textSecondary,
                    fontSize: 16,
                  ),
                ),
                const SizedBox(height: 16),
                ElevatedButton(
                  onPressed: () {
                    if (widget.onNavigate != null) {
                      widget.onNavigate!(2); // Navigate to Appointments tab
                    }
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.counselorColor,
                  ),
                  child: const Text('Schedule Appointment'),
                ),
              ],
            ),
          ),
        ),
      );
    }

    return Column(
      children: _todayAppointments.map((appointment) {
        final studentName = appointment['student_name'] as String? ?? 'Unknown Student';
        final appointmentDate = DateTime.parse(appointment['appointment_date']);
        final time = DateFormat('h:mm a').format(appointmentDate);
        final status = appointment['status'] as String? ?? 'pending';
        final avatar = appointment['avatar'] as String? ?? 'S';
        final isAnonymous = appointment['is_anonymous'] as bool? ?? false;

        return Card(
          margin: const EdgeInsets.only(bottom: 12),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          child: InkWell(
            onTap: () {
              if (widget.onNavigate != null) {
                widget.onNavigate!(2); // Navigate to Appointments tab
              }
            },
            borderRadius: BorderRadius.circular(12),
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Row(
                children: [
                  CircleAvatar(
                    backgroundColor: isAnonymous
                        ? Colors.grey.shade800
                        : AppColors.counselorColor.withOpacity(0.2),
                    child: Text(
                      avatar,
                      style: TextStyle(
                        color: isAnonymous ? Colors.white : AppColors.counselorColor,
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
                          studentName,
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 16,
                          ),
                        ),
                        Row(
                          children: [
                            Text(
                              time,
                              style: const TextStyle(
                                color: AppColors.textSecondary,
                              ),
                            ),
                            if (isAnonymous)
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                margin: const EdgeInsets.only(left: 8),
                                decoration: BoxDecoration(
                                  color: Colors.grey.shade800,
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                child: const Text(
                                  'Anonymous',
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontSize: 10,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                          ],
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
                      color: _getStatusColor(status).withOpacity(0.1),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      _capitalizeFirst(status),
                      style: TextStyle(
                        color: _getStatusColor(status),
                        fontWeight: FontWeight.bold,
                        fontSize: 12,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      }).toList(),
    );
  }

  Color _getStatusColor(String status) {
    switch (status.toLowerCase()) {
      case 'confirmed':
        return Colors.green;
      case 'pending':
        return Colors.blue;
      case 'cancelled':
        return Colors.red;
      case 'completed':
        return Colors.purple;
      case 'rescheduled':
        return Colors.orange;
      default:
        return Colors.grey;
    }
  }

  String _capitalizeFirst(String text) {
    if (text.isEmpty) return text;
    return text.substring(0, 1).toUpperCase() + text.substring(1).toLowerCase();
  }
}

