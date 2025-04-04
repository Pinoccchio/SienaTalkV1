import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart' as firebase;
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:fluttertoast/fluttertoast.dart';
import 'package:intl/intl.dart';
import '../../utils/app_colors.dart';

class AdminAppointmentsScreen extends StatefulWidget {
  const AdminAppointmentsScreen({Key? key}) : super(key: key);

  @override
  State<AdminAppointmentsScreen> createState() => _AdminAppointmentsScreenState();
}

class _AdminAppointmentsScreenState extends State<AdminAppointmentsScreen> with SingleTickerProviderStateMixin {
  final firebase.FirebaseAuth _firebaseAuth = firebase.FirebaseAuth.instance;
  final SupabaseClient _supabase = Supabase.instance.client;

  bool _isLoading = true;
  List<Map<String, dynamic>> _appointments = [];
  String? _errorMessage;
  String _searchQuery = '';
  final TextEditingController _searchController = TextEditingController();

  // Filter options
  String _selectedStatus = 'All';
  DateTime? _selectedDate;

  // Tab controller for status filtering
  late TabController _tabController;

  final List<String> _statusFilters = [
    'All',
    'Pending',
    'Confirmed',
    'Completed',
    'Cancelled',
  ];

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: _statusFilters.length, vsync: this);
    _tabController.addListener(_handleTabSelection);
    _loadAppointments();
  }

  void _handleTabSelection() {
    if (_tabController.indexIsChanging) {
      setState(() {
        _selectedStatus = _statusFilters[_tabController.index];
      });
      _loadAppointments();
    }
  }

  @override
  void dispose() {
    _searchController.dispose();
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _loadAppointments() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      // Build query based on filters - FIX: Order must be the last operation before awaiting
      var query = _supabase
          .from('appointments')
          .select('*');

      // Apply status filter if not 'All'
      if (_selectedStatus != 'All') {
        query = query.eq('status', _selectedStatus.toLowerCase());
      }

      // Apply date filter if selected
      if (_selectedDate != null) {
        final dateString = DateFormat('yyyy-MM-dd').format(_selectedDate!);
        query = query.gte('appointment_date', '$dateString 00:00:00')
            .lte('appointment_date', '$dateString 23:59:59');
      }

      // Order by date - must be the last operation
      final data = await query.order('appointment_date', ascending: false);

      // Process appointments to include names
      List<Map<String, dynamic>> processedAppointments = [];

      for (var appointment in data) {
        final appointmentWithNames = Map<String, dynamic>.from(appointment);
        final isAnonymous = appointment['is_anonymous'] as bool? ?? false;

        // Get student name (only if not anonymous)
        if (isAnonymous) {
          appointmentWithNames['student_name'] = 'Anonymous Student';
        } else {
          try {
            final studentData = await _supabase
                .from('user_profiles')
                .select('full_name')
                .eq('user_id', appointment['student_id'])
                .single();

            appointmentWithNames['student_name'] = studentData['full_name'] ?? 'Unknown Student';
          } catch (e) {
            appointmentWithNames['student_name'] = 'Unknown Student';
          }
        }

        // Get counselor name
        try {
          final counselorData = await _supabase
              .from('user_profiles')
              .select('full_name')
              .eq('user_id', appointment['counselor_id'])
              .single();

          appointmentWithNames['counselor_name'] = counselorData['full_name'] ?? 'Unknown Counselor';
        } catch (e) {
          appointmentWithNames['counselor_name'] = 'Unknown Counselor';
        }

        processedAppointments.add(appointmentWithNames);
      }

      setState(() {
        _appointments = processedAppointments;
        _isLoading = false;
      });
    } catch (e) {
      print('Error loading appointments: $e');
      setState(() {
        _errorMessage = 'Failed to load appointments: $e';
        _isLoading = false;
      });

      Fluttertoast.showToast(
        msg: "Error loading appointments: $e",
        toastLength: Toast.LENGTH_LONG,
        backgroundColor: Colors.red,
      );
    }
  }

  void _filterAppointments(String query) {
    setState(() {
      _searchQuery = query;
    });
  }

  Future<void> _selectDate(BuildContext context) async {
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate ?? DateTime.now(),
      firstDate: DateTime(2020),
      lastDate: DateTime(2030),
    );

    if (picked != null && picked != _selectedDate) {
      setState(() {
        _selectedDate = picked;
      });
      _loadAppointments();
    }
  }

  void _clearDateFilter() {
    setState(() {
      _selectedDate = null;
    });
    _loadAppointments();
  }

  List<Map<String, dynamic>> get _filteredAppointments {
    if (_searchQuery.isEmpty) {
      return _appointments;
    }

    final query = _searchQuery.toLowerCase();
    return _appointments.where((appointment) {
      final isAnonymous = appointment['is_anonymous'] as bool? ?? false;
      final studentName = (appointment['student_name'] as String? ?? '').toLowerCase();
      final counselorName = (appointment['counselor_name'] as String? ?? '').toLowerCase();
      final title = (appointment['title'] as String? ?? '').toLowerCase();

      // For anonymous appointments, don't search by student name
      if (isAnonymous) {
        return "anonymous".contains(query) ||
            counselorName.contains(query) ||
            title.contains(query);
      }

      return studentName.contains(query) ||
          counselorName.contains(query) ||
          title.contains(query);
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Appointments',
          style: TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.bold,
          ),
        ),
        backgroundColor: AppColors.adminColor,
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh, color: Colors.white),
            onPressed: _loadAppointments,
            tooltip: 'Refresh Appointments',
          ),
        ],
        bottom: TabBar(
          controller: _tabController,
          isScrollable: true,
          indicatorColor: Colors.white,
          labelColor: Colors.white,
          unselectedLabelColor: Colors.white70,
          tabs: _statusFilters.map((status) => Tab(text: status)).toList(),
        ),
      ),
      body: Column(
        children: [
          // Search and filter bar
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              children: [
                TextField(
                  controller: _searchController,
                  decoration: InputDecoration(
                    hintText: 'Search appointments...',
                    prefixIcon: const Icon(Icons.search),
                    suffixIcon: _searchQuery.isNotEmpty
                        ? IconButton(
                      icon: const Icon(Icons.clear),
                      onPressed: () {
                        _searchController.clear();
                        _filterAppointments('');
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
                      borderSide: const BorderSide(color: AppColors.adminColor),
                    ),
                    filled: true,
                    fillColor: Colors.white,
                    contentPadding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
                  ),
                  onChanged: _filterAppointments,
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    // Date filter
                    OutlinedButton.icon(
                      onPressed: () => _selectDate(context),
                      icon: const Icon(Icons.calendar_today),
                      label: Text(_selectedDate == null
                          ? 'Filter by Date'
                          : 'Date: ${DateFormat('MMM d, yyyy').format(_selectedDate!)}'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: AppColors.adminColor,
                        side: const BorderSide(color: AppColors.adminColor),
                      ),
                    ),
                    if (_selectedDate != null) ...[
                      const SizedBox(width: 8),
                      IconButton(
                        icon: const Icon(Icons.clear),
                        onPressed: _clearDateFilter,
                        tooltip: 'Clear date filter',
                      ),
                    ],
                  ],
                ),
              ],
            ),
          ),

          // Appointment count
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16.0),
            child: Row(
              children: [
                Text(
                  '${_filteredAppointments.length} ${_filteredAppointments.length == 1 ? 'Appointment' : 'Appointments'}',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: Colors.grey.shade700,
                  ),
                ),
              ],
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
                ? _buildEmptyView()
                : _buildAppointmentList()),
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
            onPressed: _loadAppointments,
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.adminColor,
            ),
            child: const Text('Retry'),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyView() {
    String message = 'There are no appointments';

    if (_selectedStatus != 'All') {
      message = 'There are no ${_selectedStatus.toLowerCase()} appointments';
    }

    if (_selectedDate != null) {
      final dateStr = DateFormat('MMMM d, yyyy').format(_selectedDate!);
      message += ' on $dateStr';
    }

    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(
            Icons.calendar_today,
            size: 80,
            color: AppColors.adminColor,
          ),
          const SizedBox(height: 16),
          const Text(
            'No Appointments Found',
            style: TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            message,
            style: const TextStyle(
              fontSize: 16,
              color: AppColors.textSecondary,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 24),
          ElevatedButton(
            onPressed: _loadAppointments,
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.adminColor,
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
            ),
            child: const Text('Refresh'),
          ),
        ],
      ),
    );
  }

  Widget _buildAppointmentList() {
    final filteredAppointments = _filteredAppointments;

    if (filteredAppointments.isEmpty) {
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
              'No matching appointments',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'No appointments found matching "$_searchQuery"',
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
      onRefresh: _loadAppointments,
      child: ListView.builder(
        padding: const EdgeInsets.only(bottom: 16),
        itemCount: filteredAppointments.length,
        itemBuilder: (context, index) {
          final appointment = filteredAppointments[index];
          final studentName = appointment['student_name'] as String? ?? 'Unknown Student';
          final counselorName = appointment['counselor_name'] as String? ?? 'Unknown Counselor';
          final appointmentDate = DateTime.parse(appointment['appointment_date']);
          final date = DateFormat('MMM d, yyyy').format(appointmentDate);
          final time = DateFormat('h:mm a').format(appointmentDate);
          final status = appointment['status'] as String? ?? 'pending';
          final isAnonymous = appointment['is_anonymous'] as bool? ?? false;

          return Card(
            margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            elevation: 2,
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
                      Expanded(
                        child: Text(
                          '$date at $time',
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 16,
                          ),
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
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Icon(
                        isAnonymous ? Icons.visibility_off : Icons.person,
                        size: 16,
                        color: isAnonymous ? Colors.grey.shade700 : AppColors.studentColor,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        'Student: $studentName',
                        style: TextStyle(
                          fontSize: 14,
                          fontStyle: isAnonymous ? FontStyle.italic : FontStyle.normal,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      const Icon(
                        Icons.person,
                        size: 16,
                        color: AppColors.counselorColor,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        'Counselor: $counselorName',
                        style: const TextStyle(
                          fontSize: 14,
                        ),
                      ),
                    ],
                  ),

                  // Show title and reason for all appointments
                  const SizedBox(height: 8),
                  const Divider(),
                  const SizedBox(height: 4),

                  // Show title if available
                  if (appointment['title'] != null && appointment['title'].toString().isNotEmpty) ...[
                    Text(
                      'Title:',
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.grey.shade600,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      appointment['title'],
                      style: TextStyle(
                        fontSize: 14,
                        color: Colors.grey.shade800,
                        fontWeight: FontWeight.w500,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 8),
                  ],

                  // Show reason if available
                  if (appointment['description'] != null && appointment['description'].toString().isNotEmpty) ...[
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
                      appointment['description'],
                      style: TextStyle(
                        fontSize: 14,
                        color: Colors.grey.shade800,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],

                  // Show anonymous notice if applicable
                  if (isAnonymous) ...[
                    const SizedBox(height: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 8),
                      decoration: BoxDecoration(
                        color: Colors.grey.shade200,
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.privacy_tip,
                            size: 14,
                            color: Colors.grey.shade600,
                          ),
                          const SizedBox(width: 4),
                          Flexible(
                            child: Text(
                              'Anonymous appointment - student identity hidden',
                              style: TextStyle(
                                fontSize: 12,
                                color: Colors.grey.shade600,
                                fontStyle: FontStyle.italic,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ],
              ),
            ),
          );
        },
      ),
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

