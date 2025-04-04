import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart' as firebase;
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:fluttertoast/fluttertoast.dart';
import 'package:intl/intl.dart';
import '../../utils/app_colors.dart';

class CounselorStudentsScreen extends StatefulWidget {
  const CounselorStudentsScreen({Key? key}) : super(key: key);

  @override
  State<CounselorStudentsScreen> createState() => _CounselorStudentsScreenState();
}

class _CounselorStudentsScreenState extends State<CounselorStudentsScreen> {
  final firebase.FirebaseAuth _firebaseAuth = firebase.FirebaseAuth.instance;
  final SupabaseClient _supabase = Supabase.instance.client;

  bool _isLoading = true;
  List<Map<String, dynamic>> _students = [];
  Map<String, int> _appointmentCounts = {};
  String? _errorMessage;
  String _searchQuery = '';
  final TextEditingController _searchController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _loadStudents();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadStudents() async {
    if (_firebaseAuth.currentUser == null) return;

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final currentUser = _firebaseAuth.currentUser!;

      // Get all appointments for this counselor, excluding anonymous ones for student listing
      final appointmentsData = await _supabase
          .from('appointments')
          .select('student_id, status, is_anonymous')
          .eq('counselor_id', currentUser.uid)
          .not('status', 'eq', 'cancelled');

      print('Loaded appointments: ${appointmentsData.length}');

      // Filter out anonymous appointments for student listing
      final nonAnonymousAppointments = appointmentsData
          .where((appointment) => !(appointment['is_anonymous'] as bool? ?? false))
          .toList();

      // Extract unique student IDs from non-anonymous appointments only
      final studentIds = nonAnonymousAppointments
          .map((appointment) => appointment['student_id'] as String?)
          .where((id) => id != null)
          .toSet();

      if (studentIds.isEmpty) {
        setState(() {
          _students = [];
          _isLoading = false;
        });
        return;
      }

      // Count non-anonymous appointments per student
      Map<String, int> appointmentCounts = {};
      for (var appointment in nonAnonymousAppointments) {
        final studentId = appointment['student_id'] as String?;
        if (studentId != null) {
          appointmentCounts[studentId] = (appointmentCounts[studentId] ?? 0) + 1;
        }
      }

      // Fetch student profiles one by one
      List<Map<String, dynamic>> students = [];
      for (var studentId in studentIds) {
        if (studentId == null) continue;

        try {
          final studentData = await _supabase
              .from('user_profiles')
              .select('*')
              .eq('user_id', studentId)
              .single();

          // Add appointment count to student data
          studentData['appointment_count'] = appointmentCounts[studentId] ?? 0;

          // Get the latest non-anonymous appointment
          final latestAppointment = await _supabase
              .from('appointments')
              .select('*')
              .eq('counselor_id', currentUser.uid)
              .eq('student_id', studentId)
              .eq('is_anonymous', false)  // Only get non-anonymous appointments
              .not('status', 'eq', 'cancelled')
              .order('appointment_date', ascending: false)
              .limit(1)
              .maybeSingle();

          if (latestAppointment != null) {
            studentData['latest_appointment'] = latestAppointment;
          }

          students.add(studentData);
        } catch (e) {
          print('Error fetching student profile: $e');
        }
      }

      // Sort students by name
      students.sort((a, b) {
        final aName = a['full_name'] as String? ?? '';
        final bName = b['full_name'] as String? ?? '';
        return aName.compareTo(bName);
      });

      setState(() {
        _students = students;
        _appointmentCounts = appointmentCounts;
        _isLoading = false;
      });
    } catch (e) {
      print('Error loading students: $e');
      setState(() {
        _errorMessage = 'Failed to load students: $e';
        _isLoading = false;
      });

      Fluttertoast.showToast(
        msg: "Error loading students: $e",
        toastLength: Toast.LENGTH_LONG,
        backgroundColor: Colors.red,
      );
    }
  }

  void _filterStudents(String query) {
    setState(() {
      _searchQuery = query;
    });
  }

  List<Map<String, dynamic>> get _filteredStudents {
    if (_searchQuery.isEmpty) {
      return _students;
    }

    final query = _searchQuery.toLowerCase();
    return _students.where((student) {
      final name = (student['full_name'] as String? ?? '').toLowerCase();
      final email = (student['email'] as String? ?? '').toLowerCase();
      return name.contains(query) || email.contains(query);
    }).toList();
  }

  void _showStudentDetails(Map<String, dynamic> student) {
    final studentId = student['user_id'] as String?;
    if (studentId == null) return;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => DraggableScrollableSheet(
        initialChildSize: 0.7,
        minChildSize: 0.5,
        maxChildSize: 0.95,
        expand: false,
        builder: (context, scrollController) => StudentDetailsSheet(
          student: student,
          appointmentCount: _appointmentCounts[studentId] ?? 0,
          scrollController: scrollController,
          onClose: () => Navigator.pop(context),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'My Students',
          style: TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.bold,
          ),
        ),
        backgroundColor: AppColors.counselorColor,
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh, color: Colors.white),
            onPressed: _loadStudents,
            tooltip: 'Refresh Students',
          ),
        ],
      ),
      body: Column(
        children: [
          // Search bar
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: TextField(
              controller: _searchController,
              decoration: InputDecoration(
                hintText: 'Search students...',
                prefixIcon: const Icon(Icons.search),
                suffixIcon: _searchQuery.isNotEmpty
                    ? IconButton(
                  icon: const Icon(Icons.clear),
                  onPressed: () {
                    _searchController.clear();
                    _filterStudents('');
                  },
                )
                    : null,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(color: Colors.grey.shade300),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(color: Colors.grey.shade300),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(color: AppColors.counselorColor),
                ),
                filled: true,
                fillColor: Colors.white,
                contentPadding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
              ),
              onChanged: _filterStudents,
            ),
          ),

          // Student count
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16.0),
            child: Row(
              children: [
                Text(
                  '${_filteredStudents.length} ${_filteredStudents.length == 1 ? 'Student' : 'Students'}',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: Colors.grey.shade700,
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 8),

          // Student list
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : (_errorMessage != null
                ? _buildErrorView()
                : _students.isEmpty
                ? _buildEmptyView()
                : _buildStudentList()),
          ),
        ],
      ),
    );
  }

  Widget _buildErrorView() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.error_outline, size: 48, color: Colors.red),
          const SizedBox(height: 16),
          const Text(
            'Error loading students',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          Text(_errorMessage ?? 'Unknown error'),
          const SizedBox(height: 24),
          ElevatedButton(
            onPressed: _loadStudents,
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.counselorColor,
            ),
            child: const Text('Retry'),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyView() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(
            Icons.people,
            size: 80,
            color: AppColors.counselorColor,
          ),
          const SizedBox(height: 16),
          const Text(
            'No Students Yet',
            style: TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            'You don\'t have any students yet',
            style: TextStyle(
              fontSize: 16,
              color: AppColors.textSecondary,
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            'Students will appear here once they schedule appointments with you',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 14,
              color: AppColors.textSecondary,
            ),
          ),
          const SizedBox(height: 24),
          ElevatedButton(
            onPressed: _loadStudents,
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.counselorColor,
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
            ),
            child: const Text('Refresh'),
          ),
        ],
      ),
    );
  }

  Widget _buildStudentList() {
    final filteredStudents = _filteredStudents;

    if (filteredStudents.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(
              Icons.search_off,
              size: 64,
              color: Colors.grey,
            ),
            const SizedBox(height: 16),
            const Text(
              'No matching students',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'No students found matching "$_searchQuery"',
              style: const TextStyle(
                fontSize: 14,
                color: AppColors.textSecondary,
              ),
            ),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _loadStudents,
      child: ListView.builder(
        padding: const EdgeInsets.only(bottom: 16),
        itemCount: filteredStudents.length,
        itemBuilder: (context, index) {
          final student = filteredStudents[index];
          final studentId = student['user_id'] as String?;
          final appointmentCount = studentId != null ? (_appointmentCounts[studentId] ?? 0) : 0;
          final latestAppointment = student['latest_appointment'] as Map<String, dynamic>?;
          final isOnline = student['is_online'] ?? false;

          return _buildStudentCard(
            student: student,
            appointmentCount: appointmentCount,
            latestAppointment: latestAppointment,
            isOnline: isOnline,
          );
        },
      ),
    );
  }

  Widget _buildStudentCard({
    required Map<String, dynamic> student,
    required int appointmentCount,
    required bool isOnline,
    Map<String, dynamic>? latestAppointment,
  }) {
    final fullName = student['full_name'] as String? ?? 'Unknown Student';
    final email = student['email'] as String? ?? 'No email';

    String lastAppointmentText = 'No appointments yet';
    if (latestAppointment != null) {
      final appointmentDate = DateTime.parse(latestAppointment['appointment_date']);
      final now = DateTime.now();
      final isUpcoming = appointmentDate.isAfter(now);

      if (isUpcoming) {
        lastAppointmentText = 'Next: ${DateFormat('MMM d, yyyy').format(appointmentDate)}';
      } else {
        lastAppointmentText = 'Last: ${DateFormat('MMM d, yyyy').format(appointmentDate)}';
      }
    }

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      elevation: 2,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
      ),
      child: InkWell(
        onTap: () => _showStudentDetails(student),
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              // Avatar with online indicator
              Stack(
                children: [
                  CircleAvatar(
                    backgroundColor: AppColors.counselorColor,
                    radius: 24,
                    child: const Icon(
                      Icons.person,
                      color: Colors.white,
                      size: 24,
                    ),
                  ),
                  if (isOnline)
                    Positioned(
                      right: 0,
                      bottom: 0,
                      child: Container(
                        width: 12,
                        height: 12,
                        decoration: BoxDecoration(
                          color: Colors.green,
                          shape: BoxShape.circle,
                          border: Border.all(color: Colors.white, width: 2),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.green.withOpacity(0.4),
                              blurRadius: 4,
                              spreadRadius: 1,
                            ),
                          ],
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Row(
                            children: [
                              Text(
                                fullName,
                                style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 16,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                              const SizedBox(width: 8),
                              // Online status text indicator
                              Text(
                                isOnline ? 'Online' : 'Offline',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: isOnline ? Colors.green : Colors.grey,
                                  fontWeight: isOnline ? FontWeight.bold : FontWeight.normal,
                                ),
                              ),
                            ],
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(
                            color: AppColors.counselorColor.withOpacity(0.1),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Text(
                            '$appointmentCount ${appointmentCount == 1 ? 'session' : 'sessions'}',
                            style: const TextStyle(
                              color: AppColors.counselorColor,
                              fontWeight: FontWeight.bold,
                              fontSize: 12,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      email,
                      style: TextStyle(
                        color: Colors.grey.shade600,
                        fontSize: 14,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        Icon(
                          Icons.calendar_today,
                          size: 14,
                          color: Colors.grey.shade600,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          lastAppointmentText,
                          style: TextStyle(
                            color: Colors.grey.shade600,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const Icon(
                Icons.chevron_right,
                color: Colors.grey,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class StudentDetailsSheet extends StatefulWidget {
  final Map<String, dynamic> student;
  final int appointmentCount;
  final ScrollController scrollController;
  final VoidCallback onClose;

  const StudentDetailsSheet({
    Key? key,
    required this.student,
    required this.appointmentCount,
    required this.scrollController,
    required this.onClose,
  }) : super(key: key);

  @override
  State<StudentDetailsSheet> createState() => _StudentDetailsSheetState();
}

class _StudentDetailsSheetState extends State<StudentDetailsSheet> {
  final SupabaseClient _supabase = Supabase.instance.client;
  final firebase.FirebaseAuth _firebaseAuth = firebase.FirebaseAuth.instance;

  bool _isLoading = true;
  List<Map<String, dynamic>> _appointments = [];
  int _anonymousAppointmentsCount = 0;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _loadStudentAppointments();
  }

  Future<void> _loadStudentAppointments() async {
    if (_firebaseAuth.currentUser == null) return;

    final studentId = widget.student['user_id'] as String?;
    if (studentId == null) return;

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final currentUser = _firebaseAuth.currentUser!;

      // First, count anonymous appointments separately
      final anonymousAppointmentsResponse = await _supabase
          .from('appointments')
          .select()
          .eq('counselor_id', currentUser.uid)
          .eq('student_id', studentId)
          .eq('is_anonymous', true);

      // Get all non-anonymous appointments between this counselor and student
      final appointmentsData = await _supabase
          .from('appointments')
          .select('*')
          .eq('counselor_id', currentUser.uid)
          .eq('student_id', studentId)
          .eq('is_anonymous', false)  // Only get non-anonymous appointments
          .order('appointment_date', ascending: false);

      print('Loaded student appointments: ${appointmentsData.length}');
      print('Anonymous appointments count: ${anonymousAppointmentsResponse.length}');

      setState(() {
        _appointments = List<Map<String, dynamic>>.from(appointmentsData);
        _anonymousAppointmentsCount = anonymousAppointmentsResponse.length;
        _isLoading = false;
      });
    } catch (e) {
      print('Error loading student appointments: $e');
      setState(() {
        _errorMessage = 'Failed to load appointments: $e';
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final fullName = widget.student['full_name'] as String? ?? 'Unknown Student';
    final email = widget.student['email'] as String? ?? 'No email';
    final phone = widget.student['phone'] as String? ?? 'No phone number';
    final isOnline = widget.student['is_online'] ?? false;

    // Total appointments includes both anonymous and non-anonymous
    final totalAppointments = _appointments.length + _anonymousAppointmentsCount;

    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Handle
          Center(
            child: Container(
              margin: const EdgeInsets.only(top: 8),
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.grey.shade300,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),

          // Header
          Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                // Avatar with online indicator
                Stack(
                  children: [
                    CircleAvatar(
                      backgroundColor: AppColors.counselorColor,
                      radius: 30,
                      child: const Icon(
                        Icons.person,
                        color: Colors.white,
                        size: 30,
                      ),
                    ),
                    if (isOnline)
                      Positioned(
                        right: 0,
                        bottom: 0,
                        child: Container(
                          width: 14,
                          height: 14,
                          decoration: BoxDecoration(
                            color: Colors.green,
                            shape: BoxShape.circle,
                            border: Border.all(color: Colors.white, width: 2),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.green.withOpacity(0.4),
                                blurRadius: 4,
                                spreadRadius: 1,
                              ),
                            ],
                          ),
                        ),
                      ),
                  ],
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              fullName,
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 20,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          // Online status badge
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                            decoration: BoxDecoration(
                              color: isOnline ? Colors.green.withOpacity(0.1) : Colors.grey.withOpacity(0.1),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Container(
                                  width: 8,
                                  height: 8,
                                  margin: const EdgeInsets.only(right: 4),
                                  decoration: BoxDecoration(
                                    color: isOnline ? Colors.green : Colors.grey,
                                    shape: BoxShape.circle,
                                  ),
                                ),
                                Text(
                                  isOnline ? 'Online' : 'Offline',
                                  style: TextStyle(
                                    color: isOnline ? Colors.green : Colors.grey,
                                    fontWeight: FontWeight.bold,
                                    fontSize: 12,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: AppColors.counselorColor.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Text(
                          '$totalAppointments ${totalAppointments == 1 ? 'session' : 'sessions'}',
                          style: const TextStyle(
                            color: AppColors.counselorColor,
                            fontWeight: FontWeight.bold,
                            fontSize: 12,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close),
                  onPressed: widget.onClose,
                ),
              ],
            ),
          ),

          const Divider(),

          // Contact info
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Contact Information',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                  ),
                ),
                const SizedBox(height: 12),
                _buildContactItem(
                  icon: Icons.email,
                  label: 'Email',
                  value: email,
                ),
                if (phone != 'No phone number')
                  _buildContactItem(
                    icon: Icons.phone,
                    label: 'Phone',
                    value: phone,
                  ),
                // Last active time
                if (!isOnline && widget.student['last_active_at'] != null)
                  _buildContactItem(
                    icon: Icons.access_time,
                    label: 'Last Active',
                    value: _formatLastActive(widget.student['last_active_at']),
                  ),
              ],
            ),
          ),

          const Divider(),

          // Appointment history
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'Appointment History',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                  ),
                ),
                if (!_isLoading && totalAppointments > 0)
                  Text(
                    '$totalAppointments ${totalAppointments == 1 ? 'appointment' : 'appointments'}',
                    style: TextStyle(
                      color: Colors.grey.shade600,
                      fontSize: 14,
                    ),
                  ),
              ],
            ),
          ),

          // Anonymous appointments note (if any)
          if (_anonymousAppointmentsCount > 0)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16.0),
              child: Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.grey.shade100,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.grey.shade300),
                ),
                child: Row(
                  children: [
                    Icon(
                      Icons.info_outline,
                      size: 20,
                      color: Colors.grey.shade700,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        'This student has $_anonymousAppointmentsCount anonymous ${_anonymousAppointmentsCount == 1 ? 'appointment' : 'appointments'} that are not shown here to protect their privacy.',
                        style: TextStyle(
                          fontSize: 14,
                          color: Colors.grey.shade700,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),

          const SizedBox(height: 8),

          // Appointment list
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : (_errorMessage != null
                ? _buildErrorView()
                : _appointments.isEmpty
                ? _buildEmptyAppointmentsView()
                : _buildAppointmentsList()),
          ),
        ],
      ),
    );
  }

  String _formatLastActive(String lastActiveTime) {
    try {
      final lastActive = DateTime.parse(lastActiveTime);
      final now = DateTime.now();
      final difference = now.difference(lastActive);

      if (difference.inMinutes < 1) {
        return 'Just now';
      } else if (difference.inMinutes < 60) {
        return '${difference.inMinutes} ${difference.inMinutes == 1 ? 'minute' : 'minutes'} ago';
      } else if (difference.inHours < 24) {
        return '${difference.inHours} ${difference.inHours == 1 ? 'hour' : 'hours'} ago';
      } else if (difference.inDays < 7) {
        return '${difference.inDays} ${difference.inDays == 1 ? 'day' : 'days'} ago';
      } else {
        return DateFormat('MMM d, yyyy').format(lastActive);
      }
    } catch (e) {
      return 'Unknown';
    }
  }

  Widget _buildContactItem({
    required IconData icon,
    required String label,
    required String value,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            icon,
            size: 20,
            color: AppColors.counselorColor,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: TextStyle(
                    color: Colors.grey.shade600,
                    fontSize: 12,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  value,
                  style: const TextStyle(
                    fontSize: 14,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildErrorView() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.error_outline, size: 48, color: Colors.red),
          const SizedBox(height: 16),
          const Text(
            'Error loading appointments',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          Text(_errorMessage ?? 'Unknown error'),
          const SizedBox(height: 24),
          ElevatedButton(
            onPressed: _loadStudentAppointments,
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.counselorColor,
            ),
            child: const Text('Retry'),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyAppointmentsView() {
    if (_anonymousAppointmentsCount > 0) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.calendar_today,
              size: 48,
              color: Colors.grey.shade400,
            ),
            const SizedBox(height: 16),
            const Text(
              'Only anonymous appointments',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'This student only has anonymous appointments with you',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 14,
                color: Colors.grey.shade600,
              ),
            ),
          ],
        ),
      );
    }

    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.calendar_today,
            size: 48,
            color: Colors.grey.shade400,
          ),
          const SizedBox(height: 16),
          const Text(
            'No appointments yet',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'You have no appointments with this student',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 14,
              color: Colors.grey.shade600,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAppointmentsList() {
    return ListView.builder(
      controller: widget.scrollController,
      padding: const EdgeInsets.only(bottom: 16),
      itemCount: _appointments.length,
      itemBuilder: (context, index) {
        final appointment = _appointments[index];
        final appointmentDate = DateTime.parse(appointment['appointment_date']);
        final status = appointment['status'] as String? ?? 'pending';
        final title = appointment['title'] as String? ?? 'Counseling Session';
        final description = appointment['description'] as String? ?? '';

        final now = DateTime.now();
        final isUpcoming = appointmentDate.isAfter(now);

        Color statusColor;
        switch (status.toLowerCase()) {
          case 'confirmed':
            statusColor = Colors.green;
            break;
          case 'pending':
            statusColor = Colors.blue;
            break;
          case 'cancelled':
            statusColor = Colors.red;
            break;
          case 'completed':
            statusColor = Colors.purple;
            break;
          case 'rescheduled':
            statusColor = Colors.orange;
            break;
          default:
            statusColor = Colors.grey;
        }

        return Card(
          margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          elevation: 1,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      DateFormat('MMMM d, yyyy').format(appointmentDate),
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: statusColor.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        _capitalizeFirst(status),
                        style: TextStyle(
                          color: statusColor,
                          fontWeight: FontWeight.bold,
                          fontSize: 12,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Icon(
                      Icons.access_time,
                      size: 16,
                      color: Colors.grey.shade600,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      DateFormat('h:mm a').format(appointmentDate),
                      style: TextStyle(
                        color: Colors.grey.shade600,
                        fontSize: 14,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  title,
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 14,
                  ),
                ),
                if (description.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(
                    description,
                    style: TextStyle(
                      color: Colors.grey.shade700,
                      fontSize: 14,
                    ),
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],

                // Show counselor notes for completed appointments
                if (status == 'completed' &&
                    appointment['counselor_notes'] != null &&
                    appointment['counselor_notes'].toString().isNotEmpty) ...[
                  const SizedBox(height: 8),
                  const Divider(),
                  const SizedBox(height: 4),
                  Text(
                    'Your Notes:',
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.grey.shade600,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    appointment['counselor_notes'],
                    style: TextStyle(
                      fontSize: 14,
                      color: Colors.grey.shade800,
                      fontStyle: FontStyle.italic,
                    ),
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ],
            ),
          ),
        );
      },
    );
  }

  String _capitalizeFirst(String text) {
    if (text.isEmpty) return text;
    return text.substring(0, 1).toUpperCase() + text.substring(1);
  }
}

