import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart' as firebase;
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:fluttertoast/fluttertoast.dart';
import 'package:intl/intl.dart';
import '../../utils/app_colors.dart';
import '../../widgets/feature_card.dart';

class StudentHomeScreen extends StatefulWidget {
  final Function(int)? onNavigate;

  const StudentHomeScreen({Key? key, this.onNavigate}) : super(key: key);

  @override
  State<StudentHomeScreen> createState() => _StudentHomeScreenState();
}

class _StudentHomeScreenState extends State<StudentHomeScreen> {
  final firebase.FirebaseAuth _firebaseAuth = firebase.FirebaseAuth.instance;
  final SupabaseClient _supabase = Supabase.instance.client;

  bool _isLoading = true;
  String _userName = "Student";
  String? _errorMessage;
  List<Map<String, dynamic>> _upcomingAppointments = [];
  bool _isLoadingAppointments = false;
  Map<String, String> _counselorNames = {};

  @override
  void initState() {
    super.initState();
    _loadUserData();
    _loadUpcomingAppointments();
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

        // Approach 3: Try raw SQL query through RPC
        if (userProfile == null) {
          try {
            final rawData = await _supabase.rpc(
              'get_user_type_by_id',
              params: {'uid': currentUser.uid},
            );

            if (rawData != null) {
              // We only get the user type here, not the full name
              // Use Firebase display name as fallback
              if (currentUser.displayName != null && currentUser.displayName!.isNotEmpty) {
                final firstName = currentUser.displayName!.split(' ').first;
                setState(() {
                  _userName = firstName;
                });
              }
            }
          } catch (rawError) {
            print('Raw query error: $rawError');
          }
        } else {
          // Extract user name from profile
          final fullName = userProfile['full_name'] as String? ?? 'Student';
          // Get first name only
          final firstName = fullName.split(' ').first;

          setState(() {
            _userName = firstName;
          });

          print('Loaded user profile: $userProfile');
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

  Future<void> _loadUpcomingAppointments() async {
    if (_firebaseAuth.currentUser == null) return;

    setState(() {
      _isLoadingAppointments = true;
    });

    try {
      final currentUser = _firebaseAuth.currentUser!;
      final now = DateTime.now();
      final formattedNow = now.toIso8601String();

      // Fetch only confirmed upcoming appointments
      final appointmentsData = await _supabase
          .from('appointments')
          .select('*')
          .eq('student_id', currentUser.uid)
          .eq('status', 'confirmed')  // Only get confirmed appointments
          .gte('appointment_date', formattedNow)
          .order('appointment_date', ascending: true)
          .limit(5);

      print('Loaded confirmed appointments: ${appointmentsData.length}');

      // Get counselor names one by one
      Map<String, String> counselorNames = {};

      for (var appointment in appointmentsData) {
        final counselorId = appointment['counselor_id'] as String?;
        if (counselorId != null && !counselorNames.containsKey(counselorId)) {
          try {
            final counselorData = await _supabase
                .from('user_profiles')
                .select('full_name')
                .eq('user_id', counselorId)
                .single();

            counselorNames[counselorId] = counselorData['full_name'] ?? 'Unknown Counselor';
          } catch (e) {
            print('Error fetching counselor name: $e');
            counselorNames[counselorId] = 'Unknown Counselor';
          }
        }
      }

      setState(() {
        _upcomingAppointments = List<Map<String, dynamic>>.from(appointmentsData);
        _counselorNames = counselorNames;
        _isLoadingAppointments = false;
      });
    } catch (e) {
      print('Error loading appointments: $e');
      setState(() {
        _isLoadingAppointments = false;
      });

      Fluttertoast.showToast(
        msg: "Error loading appointments: $e",
        toastLength: Toast.LENGTH_LONG,
        backgroundColor: Colors.red,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Home',
          style: TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.bold,
          ),
        ),
        backgroundColor: AppColors.primary,
        elevation: 0,
        actions: [
          // IconButton(
          //   icon: const Icon(Icons.search, color: Colors.white),
          //   onPressed: () {
          //     // TODO: Show search functionality
          //     Fluttertoast.showToast(
          //       msg: "Search feature coming soon!",
          //       toastLength: Toast.LENGTH_SHORT,
          //       gravity: ToastGravity.BOTTOM,
          //     );
          //   },
          // ),
          // IconButton(
          //   icon: const Icon(Icons.notifications_outlined, color: Colors.white),
          //   onPressed: () {
          //     // TODO: Navigate to notifications screen
          //     Fluttertoast.showToast(
          //       msg: "Notifications feature coming soon!",
          //       toastLength: Toast.LENGTH_SHORT,
          //       gravity: ToastGravity.BOTTOM,
          //     );
          //   },
          // ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : (_errorMessage != null
          ? _buildErrorView()
          : _buildHomeContent()),
    );
  }

  Widget _buildErrorView() {
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

  Widget _buildHomeContent() {
    return RefreshIndicator(
      onRefresh: () async {
        await Future.wait([
          _loadUserData(),
          _loadUpcomingAppointments(),
        ]);
      },
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Welcome banner
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 20),
              decoration: const BoxDecoration(
                color: AppColors.primary,
                borderRadius: BorderRadius.only(
                  bottomLeft: Radius.circular(30),
                  bottomRight: Radius.circular(30),
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Welcome, $_userName!',
                    style: const TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'How can we help you today?',
                    style: TextStyle(
                      fontSize: 16,
                      color: Colors.white70,
                    ),
                  ),
                  const SizedBox(height: 20),

                  // Quick actions
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      _buildQuickAction(
                        icon: Icons.chat_bubble_outline,
                        label: 'Chat',
                        onTap: () {
                          // Navigate to chat screen (index 1)
                          if (widget.onNavigate != null) {
                            widget.onNavigate!(1);
                          }
                        },
                      ),
                      _buildQuickAction(
                        icon: Icons.calendar_today_outlined,
                        label: 'Appointments',
                        onTap: () {
                          // Navigate to appointment scheduling (index 2)
                          if (widget.onNavigate != null) {
                            widget.onNavigate!(2);
                          }
                        },
                      ),
                    ],
                  ),
                ],
              ),
            ),

            // Upcoming appointments
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 24, 20, 12),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    'Upcoming Appointments',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: AppColors.textPrimary,
                    ),
                  ),
                  if (_upcomingAppointments.isNotEmpty)
                    TextButton(
                      onPressed: () {
                        // Navigate to appointments screen (index 2)
                        if (widget.onNavigate != null) {
                          widget.onNavigate!(2);
                        }
                      },
                      child: const Text(
                        'View All',
                        style: TextStyle(
                          color: AppColors.primary,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                ],
              ),
            ),

            _isLoadingAppointments
                ? const Center(
              child: Padding(
                padding: EdgeInsets.all(20.0),
                child: CircularProgressIndicator(),
              ),
            )
                : _upcomingAppointments.isEmpty
                ? _buildEmptyAppointmentsView()
                : SizedBox(
              height: 200, // Increased height to accommodate more content
              child: ListView.builder(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                scrollDirection: Axis.horizontal,
                itemCount: _upcomingAppointments.length,
                itemBuilder: (context, index) {
                  final appointment = _upcomingAppointments[index];
                  final appointmentDate = DateTime.parse(appointment['appointment_date']);

                  // Get counselor name from our map
                  final counselorId = appointment['counselor_id'] as String?;
                  final counselorName = counselorId != null
                      ? _counselorNames[counselorId] ?? 'Unknown Counselor'
                      : 'Unknown Counselor';

                  return _buildAppointmentCard(
                    appointment: appointment,
                    counselorName: counselorName,
                    date: DateFormat('EEE, MMM d').format(appointmentDate),
                    time: DateFormat('h:mm a').format(appointmentDate),
                    isUpcoming: index == 0,
                  );
                },
              ),
            ),

            // Features section
            const Padding(
              padding: EdgeInsets.fromLTRB(20, 24, 20, 12),
              child: Text(
                'Features',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: AppColors.textPrimary,
                ),
              ),
            ),

            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Column(
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: FeatureCard(
                          icon: Icons.chat_bubble_outlined,
                          title: 'Chat with counselors',
                          onTap: () {
                            // Navigate to chat screen (index 1)
                            if (widget.onNavigate != null) {
                              widget.onNavigate!(1);
                            }
                          },
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: FeatureCard(
                          icon: Icons.calendar_today_outlined,
                          title: 'Schedule appointments',
                          onTap: () {
                            // Navigate to appointments screen (index 2)
                            if (widget.onNavigate != null) {
                              widget.onNavigate!(2);
                            }
                          },
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),

            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyAppointmentsView() {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.grey.shade100,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: [
          Icon(
            Icons.calendar_today_outlined,
            size: 40,
            color: Colors.grey.shade400,
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                  'No confirmed appointments',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Schedule a session with a counselor',
                  style: TextStyle(
                    color: Colors.grey.shade600,
                    fontSize: 14,
                  ),
                ),
              ],
            ),
          ),
          ElevatedButton(
            onPressed: () {
              // Navigate to appointments screen (index 2)
              if (widget.onNavigate != null) {
                widget.onNavigate!(2);
              }
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primary,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
            child: const Text('Schedule'),
          ),
        ],
      ),
    );
  }

  Widget _buildQuickAction({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.1),
                  blurRadius: 8,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: Icon(
              icon,
              color: AppColors.primary,
              size: 28,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            label,
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAppointmentCard({
    required Map<String, dynamic> appointment,
    required String counselorName,
    required String date,
    required String time,
    required bool isUpcoming,
  }) {
    final isAnonymous = appointment['is_anonymous'] as bool? ?? false;
    final description = appointment['description'] as String? ?? '';
    final title = appointment['title'] as String? ?? 'Counseling Session';

    return GestureDetector(
      onTap: () {
        // Navigate to appointments screen (index 2)
        if (widget.onNavigate != null) {
          widget.onNavigate!(2);
        }
      },
      child: Container(
        width: 280,
        margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
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
          border: isUpcoming
              ? Border.all(color: AppColors.primary, width: 2)
              : null,
        ),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  CircleAvatar(
                    backgroundColor: isAnonymous ? Colors.grey.shade800 : AppColors.primary,
                    child: Icon(
                        isAnonymous ? Icons.visibility_off : Icons.person,
                        color: Colors.white
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          counselorName,
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 16,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        Text(
                          title,
                          style: const TextStyle(
                            color: AppColors.textSecondary,
                            fontSize: 14,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        if (isAnonymous)
                          Row(
                            children: [
                              Icon(Icons.visibility_off, size: 12, color: Colors.grey.shade600),
                              const SizedBox(width: 4),
                              Text(
                                'Anonymous',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: Colors.grey.shade600,
                                  fontStyle: FontStyle.italic,
                                ),
                              ),
                            ],
                          ),
                      ],
                    ),
                  ),
                  // Green badge for confirmed status
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: Colors.green.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Text(
                      'Confirmed',
                      style: TextStyle(
                        color: Colors.green,
                        fontWeight: FontWeight.bold,
                        fontSize: 10,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    children: [
                      const Icon(
                        Icons.calendar_today,
                        size: 16,
                        color: AppColors.textSecondary,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        date,
                        style: const TextStyle(
                          color: AppColors.textSecondary,
                        ),
                      ),
                    ],
                  ),
                  Row(
                    children: [
                      const Icon(
                        Icons.access_time,
                        size: 16,
                        color: AppColors.textSecondary,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        time,
                        style: const TextStyle(
                          color: AppColors.textSecondary,
                        ),
                      ),
                    ],
                  ),
                ],
              ),

              // Show reason for appointment if available
              if (description.isNotEmpty) ...[
                const SizedBox(height: 12),
                const Divider(height: 1),
                const SizedBox(height: 8),
                Text(
                  'Reason:',
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.grey.shade600,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  description,
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.grey.shade800,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

