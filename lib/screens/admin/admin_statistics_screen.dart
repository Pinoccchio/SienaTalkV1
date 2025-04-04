import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart' as firebase;
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:fluttertoast/fluttertoast.dart';
import 'package:intl/intl.dart';
import '../../utils/app_colors.dart';

class AdminStatisticsScreen extends StatefulWidget {
  const AdminStatisticsScreen({Key? key}) : super(key: key);

  @override
  State<AdminStatisticsScreen> createState() => _AdminStatisticsScreenState();
}

class _AdminStatisticsScreenState extends State<AdminStatisticsScreen> with SingleTickerProviderStateMixin {
  final firebase.FirebaseAuth _firebaseAuth = firebase.FirebaseAuth.instance;
  final SupabaseClient _supabase = Supabase.instance.client;

  bool _isLoading = true;
  String? _errorMessage;

  // Statistics data
  Map<String, int> _appointmentsByStatus = {};
  Map<String, int> _appointmentsByMonth = {};
  Map<String, int> _appointmentsByCounselor = {};
  Map<String, Map<String, int>> _appointmentsByMonthAndStatus = {};
  Map<String, Map<String, int>> _appointmentsByMonthAndDay = {};
  int _totalAppointments = 0;
  int _totalStudents = 0;
  int _totalCounselors = 0;
  double _averageAppointmentsPerStudent = 0;

  // For monthly view
  late TabController _tabController;
  DateTime _selectedMonth = DateTime.now();
  List<String> _tabTitles = ['Overview', 'Monthly', 'Counselors'];

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: _tabTitles.length, vsync: this);
    _loadStatistics();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _loadStatistics() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      // Load total counts by executing separate count queries
      final studentsCountQuery = await _supabase
          .from('user_profiles')
          .select('user_id')  // Changed from 'id' to 'user_id'
          .eq('user_type', 'student');

      _totalStudents = studentsCountQuery.length;

      final counselorsCountQuery = await _supabase
          .from('user_profiles')
          .select('user_id')  // Changed from 'id' to 'user_id'
          .eq('user_type', 'counselor');

      _totalCounselors = counselorsCountQuery.length;

      // Load all appointments for statistics
      final appointmentsData = await _supabase
          .from('appointments')
          .select()
          .order('appointment_date', ascending: false);

      _totalAppointments = appointmentsData.length;

      // Calculate average appointments per student
      if (_totalStudents > 0) {
        _averageAppointmentsPerStudent = _totalAppointments / _totalStudents;
      }

      // Process appointments by status
      Map<String, int> statusCounts = {};
      for (var appointment in appointmentsData) {
        final status = appointment['status'] as String? ?? 'unknown';
        statusCounts[status] = (statusCounts[status] ?? 0) + 1;
      }
      _appointmentsByStatus = statusCounts;

      // Process appointments by month
      Map<String, int> monthCounts = {};
      Map<String, Map<String, int>> monthStatusCounts = {};
      Map<String, Map<String, int>> monthDayCounts = {};

      for (var appointment in appointmentsData) {
        final date = DateTime.parse(appointment['appointment_date']);
        final monthKey = DateFormat('MMM yyyy').format(date);
        final status = appointment['status'] as String? ?? 'unknown';
        final dayOfWeek = DateFormat('EEEE').format(date); // Monday, Tuesday, etc.
        final dayOfMonth = date.day.toString(); // 1, 2, 3, etc.

        // Count by month
        monthCounts[monthKey] = (monthCounts[monthKey] ?? 0) + 1;

        // Count by month and status
        if (!monthStatusCounts.containsKey(monthKey)) {
          monthStatusCounts[monthKey] = {};
        }
        monthStatusCounts[monthKey]![status] = (monthStatusCounts[monthKey]![status] ?? 0) + 1;

        // Count by month and day
        final monthYearKey = DateFormat('yyyy-MM').format(date); // 2023-01, 2023-02, etc.
        if (!monthDayCounts.containsKey(monthYearKey)) {
          monthDayCounts[monthYearKey] = {};
        }
        monthDayCounts[monthYearKey]![dayOfMonth] = (monthDayCounts[monthYearKey]![dayOfMonth] ?? 0) + 1;
      }

      _appointmentsByMonth = monthCounts;
      _appointmentsByMonthAndStatus = monthStatusCounts;
      _appointmentsByMonthAndDay = monthDayCounts;

      // Process appointments by counselor
      Map<String, int> counselorCounts = {};
      Map<String, String> counselorNames = {};

      for (var appointment in appointmentsData) {
        final counselorId = appointment['counselor_id'] as String?;
        if (counselorId != null) {
          counselorCounts[counselorId] = (counselorCounts[counselorId] ?? 0) + 1;

          // Get counselor name if not already fetched
          if (!counselorNames.containsKey(counselorId)) {
            try {
              final counselorData = await _supabase
                  .from('user_profiles')
                  .select('full_name')
                  .eq('user_id', counselorId)
                  .single();

              counselorNames[counselorId] = counselorData['full_name'] ?? 'Unknown Counselor';
            } catch (e) {
              counselorNames[counselorId] = 'Unknown Counselor';
            }
          }
        }
      }

      // Convert counselor IDs to names in the counts
      Map<String, int> counselorNameCounts = {};
      counselorCounts.forEach((id, count) {
        final name = counselorNames[id] ?? 'Unknown Counselor';
        counselorNameCounts[name] = count;
      });

      _appointmentsByCounselor = counselorNameCounts;

      setState(() {
        _isLoading = false;
      });
    } catch (e) {
      print('Error loading statistics: $e');
      setState(() {
        _errorMessage = 'Failed to load statistics: $e';
        _isLoading = false;
      });

      Fluttertoast.showToast(
        msg: "Error loading statistics: $e",
        toastLength: Toast.LENGTH_LONG,
        backgroundColor: Colors.red,
      );
    }
  }

  void _previousMonth() {
    setState(() {
      _selectedMonth = DateTime(_selectedMonth.year, _selectedMonth.month - 1, 1);
    });
  }

  void _nextMonth() {
    setState(() {
      _selectedMonth = DateTime(_selectedMonth.year, _selectedMonth.month + 1, 1);
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Statistics',
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
            onPressed: _loadStatistics,
            tooltip: 'Refresh Statistics',
          ),
        ],
        bottom: TabBar(
          controller: _tabController,
          indicatorColor: Colors.white,
          labelColor: Colors.white,
          unselectedLabelColor: Colors.white70,
          tabs: _tabTitles.map((title) => Tab(text: title)).toList(),
        ),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : (_errorMessage != null
          ? _buildErrorView()
          : TabBarView(
        controller: _tabController,
        children: [
          _buildOverviewTab(),
          _buildMonthlyTab(),
          _buildCounselorsTab(),
        ],
      )),
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
            'Error loading statistics',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          Text(_errorMessage ?? 'Unknown error'),
          const SizedBox(height: 24),
          ElevatedButton(
            onPressed: _loadStatistics,
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.adminColor,
            ),
            child: const Text('Retry'),
          ),
        ],
      ),
    );
  }

  Widget _buildOverviewTab() {
    return RefreshIndicator(
      onRefresh: _loadStatistics,
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Summary cards
            _buildSummaryCards(),
            const SizedBox(height: 24),

            // Appointments by status
            const Text(
              'Appointments by Status',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: AppColors.textPrimary,
              ),
            ),
            const SizedBox(height: 16),
            _buildStatusChart(),
            const SizedBox(height: 24),

            // Monthly appointments
            const Text(
              'Monthly Appointments',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: AppColors.textPrimary,
              ),
            ),
            const SizedBox(height: 16),
            _buildMonthlyChart(),
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }

  Widget _buildMonthlyTab() {
    final monthYearStr = DateFormat('MMMM yyyy').format(_selectedMonth);
    final monthYearKey = DateFormat('yyyy-MM').format(_selectedMonth);
    final monthKey = DateFormat('MMM yyyy').format(_selectedMonth);

    // Get appointments for the selected month
    final appointmentsThisMonth = _appointmentsByMonth[monthKey] ?? 0;

    // Get status breakdown for the selected month
    final statusBreakdown = _appointmentsByMonthAndStatus[monthKey] ?? {};

    // Get day breakdown for the selected month
    final dayBreakdown = _appointmentsByMonthAndDay[monthYearKey] ?? {};

    // Calculate the number of days in the month
    final daysInMonth = DateTime(_selectedMonth.year, _selectedMonth.month + 1, 0).day;

    return RefreshIndicator(
      onRefresh: _loadStatistics,
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Month selector
            Card(
              elevation: 2,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        IconButton(
                          icon: const Icon(Icons.chevron_left),
                          onPressed: _previousMonth,
                          tooltip: 'Previous Month',
                        ),
                        Text(
                          monthYearStr,
                          style: const TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        IconButton(
                          icon: const Icon(Icons.chevron_right),
                          onPressed: _nextMonth,
                          tooltip: 'Next Month',
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    Text(
                      'Total Appointments: $appointmentsThisMonth',
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: AppColors.adminColor,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 24),

            // Status breakdown for the month
            const Text(
              'Appointment Status Breakdown',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: AppColors.textPrimary,
              ),
            ),
            const SizedBox(height: 16),
            _buildMonthStatusBreakdown(statusBreakdown, appointmentsThisMonth),
            const SizedBox(height: 24),

            // Daily breakdown for the month
            const Text(
              'Daily Appointment Distribution',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: AppColors.textPrimary,
              ),
            ),
            const SizedBox(height: 16),
            _buildMonthDailyBreakdown(dayBreakdown, daysInMonth),
            const SizedBox(height: 24),

            // Calendar view
            const Text(
              'Calendar View',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: AppColors.textPrimary,
              ),
            ),
            const SizedBox(height: 16),
            _buildCalendarView(dayBreakdown, daysInMonth),
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }

  Widget _buildCounselorsTab() {
    return RefreshIndicator(
      onRefresh: _loadStatistics,
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Counselor performance
            const Text(
              'Counselor Performance',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: AppColors.textPrimary,
              ),
            ),
            const SizedBox(height: 16),
            _buildCounselorPerformanceChart(),
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }

  Widget _buildSummaryCards() {
    return GridView.count(
      crossAxisCount: 2,
      crossAxisSpacing: 16,
      mainAxisSpacing: 16,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      children: [
        _buildSummaryCard(
          title: 'Total Appointments',
          value: _totalAppointments.toString(),
          icon: Icons.calendar_today,
          color: Colors.blue,
        ),
        _buildSummaryCard(
          title: 'Total Students',
          value: _totalStudents.toString(),
          icon: Icons.school,
          color: AppColors.studentColor,
        ),
        _buildSummaryCard(
          title: 'Total Counselors',
          value: _totalCounselors.toString(),
          icon: Icons.people,
          color: AppColors.counselorColor,
        ),
        _buildSummaryCard(
          title: 'Avg. Appointments',
          value: _averageAppointmentsPerStudent.toStringAsFixed(1),
          icon: Icons.analytics,
          color: Colors.purple,
        ),
      ],
    );
  }

  Widget _buildSummaryCard({
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
    );
  }

  Widget _buildStatusChart() {
    if (_appointmentsByStatus.isEmpty) {
      return _buildEmptyChartMessage('No appointment status data available');
    }

    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: _appointmentsByStatus.entries.map((entry) {
            final status = _capitalizeFirst(entry.key);
            final count = entry.value;
            final percentage = _totalAppointments > 0
                ? (count / _totalAppointments * 100).toStringAsFixed(1)
                : '0';

            return Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        status,
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      Text(
                        '$count ($percentage%)',
                        style: TextStyle(
                          color: _getStatusColor(entry.key),
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  LinearProgressIndicator(
                    value: _totalAppointments > 0 ? count / _totalAppointments : 0,
                    backgroundColor: Colors.grey.shade200,
                    valueColor: AlwaysStoppedAnimation<Color>(_getStatusColor(entry.key)),
                    minHeight: 8,
                    borderRadius: BorderRadius.circular(4),
                  ),
                ],
              ),
            );
          }).toList(),
        ),
      ),
    );
  }

  Widget _buildMonthlyChart() {
    if (_appointmentsByMonth.isEmpty) {
      return _buildEmptyChartMessage('No monthly appointment data available');
    }

    // Sort months chronologically
    final sortedMonths = _appointmentsByMonth.entries.toList()
      ..sort((a, b) {
        final aDate = DateFormat('MMM yyyy').parse(a.key);
        final bDate = DateFormat('MMM yyyy').parse(b.key);
        return aDate.compareTo(bDate);
      });

    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: sortedMonths.map((entry) {
            final month = entry.key;
            final count = entry.value;
            final maxCount = sortedMonths.map((e) => e.value).reduce((a, b) => a > b ? a : b);

            return Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        month,
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      Text(
                        count.toString(),
                        style: const TextStyle(
                          color: AppColors.adminColor,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  LinearProgressIndicator(
                    value: maxCount > 0 ? count / maxCount : 0,
                    backgroundColor: Colors.grey.shade200,
                    valueColor: const AlwaysStoppedAnimation<Color>(AppColors.adminColor),
                    minHeight: 8,
                    borderRadius: BorderRadius.circular(4),
                  ),
                ],
              ),
            );
          }).toList(),
        ),
      ),
    );
  }

  Widget _buildMonthStatusBreakdown(Map<String, int> statusBreakdown, int totalMonthAppointments) {
    if (statusBreakdown.isEmpty) {
      return _buildEmptyChartMessage('No status data available for this month');
    }

    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: statusBreakdown.entries.map((entry) {
            final status = _capitalizeFirst(entry.key);
            final count = entry.value;
            final percentage = totalMonthAppointments > 0
                ? (count / totalMonthAppointments * 100).toStringAsFixed(1)
                : '0';

            return Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        status,
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      Text(
                        '$count ($percentage%)',
                        style: TextStyle(
                          color: _getStatusColor(entry.key),
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  LinearProgressIndicator(
                    value: totalMonthAppointments > 0 ? count / totalMonthAppointments : 0,
                    backgroundColor: Colors.grey.shade200,
                    valueColor: AlwaysStoppedAnimation<Color>(_getStatusColor(entry.key)),
                    minHeight: 8,
                    borderRadius: BorderRadius.circular(4),
                  ),
                ],
              ),
            );
          }).toList(),
        ),
      ),
    );
  }

  Widget _buildMonthDailyBreakdown(Map<String, int> dayBreakdown, int daysInMonth) {
    if (dayBreakdown.isEmpty) {
      return _buildEmptyChartMessage('No daily data available for this month');
    }

    // Find the maximum number of appointments in a day
    final maxDailyCount = dayBreakdown.values.isEmpty
        ? 0
        : dayBreakdown.values.reduce((a, b) => a > b ? a : b);

    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Busiest Day: ${_getBusiestDay(dayBreakdown)}',
              style: const TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 16,
                color: AppColors.adminColor,
              ),
            ),
            const SizedBox(height: 16),
            GridView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 7,
                childAspectRatio: 1,
                crossAxisSpacing: 4,
                mainAxisSpacing: 4,
              ),
              itemCount: daysInMonth,
              itemBuilder: (context, index) {
                final day = (index + 1).toString();
                final count = dayBreakdown[day] ?? 0;
                final intensity = maxDailyCount > 0
                    ? count / maxDailyCount
                    : 0.0;

                return Container(
                  decoration: BoxDecoration(
                    color: AppColors.adminColor.withOpacity(intensity * 0.8),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        day,
                        style: TextStyle(
                          color: intensity > 0.5 ? Colors.white : Colors.black,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      if (count > 0)
                        Text(
                          count.toString(),
                          style: TextStyle(
                            color: intensity > 0.5 ? Colors.white : Colors.black,
                            fontSize: 12,
                          ),
                        ),
                    ],
                  ),
                );
              },
            ),
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(
                  width: 16,
                  height: 16,
                  color: AppColors.adminColor.withOpacity(0.1),
                ),
                const SizedBox(width: 4),
                const Text('Low'),
                const SizedBox(width: 16),
                Container(
                  width: 16,
                  height: 16,
                  color: AppColors.adminColor.withOpacity(0.5),
                ),
                const SizedBox(width: 4),
                const Text('Medium'),
                const SizedBox(width: 16),
                Container(
                  width: 16,
                  height: 16,
                  color: AppColors.adminColor.withOpacity(0.8),
                ),
                const SizedBox(width: 4),
                const Text('High'),
              ],
            ),
          ],
        ),
      ),
    );
  }

  String _getBusiestDay(Map<String, int> dayBreakdown) {
    if (dayBreakdown.isEmpty) return 'None';

    String busiestDay = '1';
    int maxCount = 0;

    dayBreakdown.forEach((day, count) {
      if (count > maxCount) {
        maxCount = count;
        busiestDay = day;
      }
    });

    return 'Day $busiestDay with $maxCount appointments';
  }

  Widget _buildCalendarView(Map<String, int> dayBreakdown, int daysInMonth) {
    // Get the first day of the month
    final firstDay = DateTime(_selectedMonth.year, _selectedMonth.month, 1);
    final firstDayOfWeek = firstDay.weekday; // 1 = Monday, 7 = Sunday

    // Adjust for Sunday as first day of week (0 = Sunday, 6 = Saturday)
    final startOffset = firstDayOfWeek % 7;

    // Calculate total calendar cells needed (days + empty cells)
    final totalCells = startOffset + daysInMonth;
    final totalRows = (totalCells / 7).ceil();

    // Find the maximum number of appointments in a day
    final maxDailyCount = dayBreakdown.values.isEmpty
        ? 0
        : dayBreakdown.values.reduce((a, b) => a > b ? a : b);

    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            // Day headers
            Row(
              children: const [
                Expanded(child: Center(child: Text('Sun', style: TextStyle(fontWeight: FontWeight.bold)))),
                Expanded(child: Center(child: Text('Mon', style: TextStyle(fontWeight: FontWeight.bold)))),
                Expanded(child: Center(child: Text('Tue', style: TextStyle(fontWeight: FontWeight.bold)))),
                Expanded(child: Center(child: Text('Wed', style: TextStyle(fontWeight: FontWeight.bold)))),
                Expanded(child: Center(child: Text('Thu', style: TextStyle(fontWeight: FontWeight.bold)))),
                Expanded(child: Center(child: Text('Fri', style: TextStyle(fontWeight: FontWeight.bold)))),
                Expanded(child: Center(child: Text('Sat', style: TextStyle(fontWeight: FontWeight.bold)))),
              ],
            ),
            const SizedBox(height: 8),
            // Calendar grid
            GridView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 7,
                childAspectRatio: 1,
                crossAxisSpacing: 2,
                mainAxisSpacing: 2,
              ),
              itemCount: totalRows * 7,
              itemBuilder: (context, index) {
                // Calculate day number (1-based)
                final dayNumber = index - startOffset + 1;

                // Check if this cell is a valid day in the month
                if (dayNumber < 1 || dayNumber > daysInMonth) {
                  return Container(color: Colors.grey.shade100);
                }

                final day = dayNumber.toString();
                final count = dayBreakdown[day] ?? 0;
                final intensity = maxDailyCount > 0
                    ? count / maxDailyCount
                    : 0.0;

                return Container(
                  decoration: BoxDecoration(
                    color: count > 0
                        ? AppColors.adminColor.withOpacity(0.1 + intensity * 0.7)
                        : Colors.white,
                    border: Border.all(color: Colors.grey.shade300),
                  ),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        day,
                        style: TextStyle(
                          fontWeight: count > 0 ? FontWeight.bold : FontWeight.normal,
                        ),
                      ),
                      if (count > 0)
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: AppColors.adminColor,
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Text(
                            count.toString(),
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                    ],
                  ),
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCounselorPerformanceChart() {
    if (_appointmentsByCounselor.isEmpty) {
      return _buildEmptyChartMessage('No counselor performance data available');
    }

    // Sort counselors by appointment count (descending)
    final sortedCounselors = _appointmentsByCounselor.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: sortedCounselors.map((entry) {
            final counselorName = entry.key;
            final count = entry.value;
            final maxCount = sortedCounselors.first.value;

            return Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Expanded(
                        child: Text(
                          counselorName,
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        '$count appointments',
                        style: const TextStyle(
                          color: AppColors.counselorColor,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  LinearProgressIndicator(
                    value: maxCount > 0 ? count / maxCount : 0,
                    backgroundColor: Colors.grey.shade200,
                    valueColor: const AlwaysStoppedAnimation<Color>(AppColors.counselorColor),
                    minHeight: 8,
                    borderRadius: BorderRadius.circular(4),
                  ),
                ],
              ),
            );
          }).toList(),
        ),
      ),
    );
  }

  Widget _buildEmptyChartMessage(String message) {
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
      ),
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Center(
          child: Column(
            children: [
              Icon(
                Icons.bar_chart,
                size: 48,
                color: Colors.grey.shade400,
              ),
              const SizedBox(height: 16),
              Text(
                message,
                style: TextStyle(
                  color: Colors.grey.shade600,
                  fontSize: 16,
                ),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
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