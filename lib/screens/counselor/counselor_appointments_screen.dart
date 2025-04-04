import 'dart:async';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart' as firebase;
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:intl/intl.dart';
import 'package:fluttertoast/fluttertoast.dart';
import '../../utils/app_colors.dart';

class CounselorAppointmentsScreen extends StatefulWidget {
  const CounselorAppointmentsScreen({Key? key}) : super(key: key);

  @override
  State<CounselorAppointmentsScreen> createState() => _CounselorAppointmentsScreenState();
}

class _CounselorAppointmentsScreenState extends State<CounselorAppointmentsScreen> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final firebase.FirebaseAuth _firebaseAuth = firebase.FirebaseAuth.instance;
  final SupabaseClient _supabase = Supabase.instance.client;

  String? _currentUserId;
  bool _isLoading = true;
  List<Map<String, dynamic>> _upcomingAppointments = [];
  List<Map<String, dynamic>> _pastAppointments = [];
  List<Map<String, dynamic>> _students = [];
  List<Map<String, dynamic>> _availabilitySlots = [];
  RealtimeChannel? _appointmentsChannel;
  bool _isMounted = true;

  // For appointment rescheduling
  DateTime _selectedDate = DateTime.now().add(const Duration(days: 1));
  TimeOfDay _selectedTime = const TimeOfDay(hour: 9, minute: 0);
  final TextEditingController _notesController = TextEditingController();
  bool _isSubmitting = false;

  // For availability management
  final List<String> _weekdays = ['Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday'];
  Map<String, List<TimeSlot>> _availabilityByDay = {};
  String _selectedDay = '';
  List<TimeSlot> _availableTimeSlots = [];

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _currentUserId = _firebaseAuth.currentUser?.uid;
    _ensureSelectedDateIsValid();
    _initializeAvailabilityByDay();
    _loadData();
    _loadAvailability();
    _setupRealtimeSubscription();
  }

  void _initializeAvailabilityByDay() {
    for (var day in _weekdays) {
      _availabilityByDay[day] = [];
    }
  }

  void _ensureSelectedDateIsValid() {
    final DateTime now = DateTime.now();
    final DateTime startDate = DateTime(now.year, now.month, now.day);

    // If the currently selected date is before today, update it to tomorrow
    if (_selectedDate.isBefore(startDate)) {
      _selectedDate = startDate.add(const Duration(days: 1));
    }

    // Set the selected day based on the date
    _selectedDay = DateFormat('EEEE').format(_selectedDate);
  }

  @override
  void dispose() {
    _isMounted = false;
    _tabController.dispose();
    _notesController.dispose();
    if (_appointmentsChannel != null) {
      _appointmentsChannel!.unsubscribe();
    }
    super.dispose();
  }

  void _setupRealtimeSubscription() {
    if (_currentUserId == null) return;

    // Subscribe to changes in appointments table
    _appointmentsChannel = _supabase
        .channel('public:appointments:counselor')
        .onPostgresChanges(
      event: PostgresChangeEvent.insert,
      schema: 'public',
      table: 'appointments',
      callback: (payload) {
        if (_isMounted && payload.newRecord?['counselor_id'] == _currentUserId) {
          _loadData();
        }
      },
    )
        .onPostgresChanges(
      event: PostgresChangeEvent.update,
      schema: 'public',
      table: 'appointments',
      callback: (payload) {
        if (_isMounted &&
            (payload.oldRecord?['counselor_id'] == _currentUserId ||
                payload.newRecord?['counselor_id'] == _currentUserId)) {
          _loadData();
        }
      },
    )
        .onPostgresChanges(
      event: PostgresChangeEvent.delete,
      schema: 'public',
      table: 'appointments',
      callback: (payload) {
        if (_isMounted && payload.oldRecord?['counselor_id'] == _currentUserId) {
          _loadData();
        }
      },
    )
        .subscribe();
  }

  Future<void> _loadData() async {
    if (_currentUserId == null) return;

    setState(() {
      _isLoading = true;
    });

    try {
      // Load students
      final studentsData = await _supabase
          .from('user_profiles')
          .select('user_id, full_name')
          .eq('user_type', 'student');

      print('Students loaded: ${studentsData.length}');

      // Create a map for quick lookup
      Map<String, Map<String, dynamic>> studentsMap = {};
      for (var student in studentsData) {
        studentsMap[student['user_id']] = student;
      }

      // Load appointments
      final appointmentsData = await _supabase
          .from('appointments')
          .select('*')
          .eq('counselor_id', _currentUserId as String)
          .order('appointment_date', ascending: true);

      print('Appointments loaded: ${appointmentsData.length}');

      // Add student info to each appointment
      for (final appointment in appointmentsData) {
        if (appointment['student_id'] != null) {
          final studentId = appointment['student_id'];
          if (studentsMap.containsKey(studentId)) {
            // Check if anonymous
            final isAnonymous = appointment['is_anonymous'] ?? false;

            if (isAnonymous) {
              // For anonymous appointments, hide student identity
              appointment['student'] = {
                'full_name': 'Anonymous Student',
                'user_id': studentId,
              };
            } else {
              // For regular appointments, show student identity
              appointment['student'] = studentsMap[studentId];
            }
          } else {
            appointment['student'] = {
              'full_name': 'Unknown Student',
              'user_id': studentId,
            };
          }
        }
      }

      final now = DateTime.now();
      final upcoming = <Map<String, dynamic>>[];
      final past = <Map<String, dynamic>>[];

      for (final appointment in appointmentsData) {
        final appointmentDate = DateTime.parse(appointment['appointment_date']);
        final status = appointment['status'] as String? ?? 'pending';

        // Always put completed and cancelled appointments in past
        if (status == 'completed' || status == 'cancelled') {
          past.add(appointment);
        }
        // For other statuses, check the date
        else if (appointmentDate.isAfter(now) ||
            (appointmentDate.day == now.day &&
                appointmentDate.month == now.month &&
                appointmentDate.year == now.year)) {
          upcoming.add(appointment);
        } else {
          past.add(appointment);
        }
      }

      // Sort past appointments by date (most recent first)
      past.sort((a, b) =>
          DateTime.parse(b['appointment_date']).compareTo(DateTime.parse(a['appointment_date']))
      );

      // Sort upcoming appointments by date (earliest first)
      upcoming.sort((a, b) =>
          DateTime.parse(a['appointment_date']).compareTo(DateTime.parse(b['appointment_date']))
      );

      if (mounted) {
        setState(() {
          _students = List<Map<String, dynamic>>.from(studentsData);
          _upcomingAppointments = upcoming;
          _pastAppointments = past;
          _isLoading = false;
        });
      }
    } catch (e) {
      print('Error loading data: $e');
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
        Fluttertoast.showToast(
          msg: "Failed to load appointments: $e",
          toastLength: Toast.LENGTH_LONG,
          backgroundColor: Colors.red,
        );
      }
    }
  }

  Future<void> _loadAvailability() async {
    if (_currentUserId == null) return;

    try {
      // Load availability slots from the database
      final availabilityData = await _supabase
          .from('counselor_availability')
          .select('*')
          .eq('counselor_id', _currentUserId as String);

      // Reset availability map
      _initializeAvailabilityByDay();

      // Populate availability map from database data
      for (var slot in availabilityData) {
        final day = slot['day_of_week'];
        final startTime = TimeOfDay(
          hour: int.parse(slot['start_time'].split(':')[0]),
          minute: int.parse(slot['start_time'].split(':')[1]),
        );
        final endTime = TimeOfDay(
          hour: int.parse(slot['end_time'].split(':')[0]),
          minute: int.parse(slot['end_time'].split(':')[1]),
        );

        if (_availabilityByDay.containsKey(day)) {
          _availabilityByDay[day]!.add(TimeSlot(startTime, endTime));
        }
      }

      // Update available time slots for the selected day
      _updateAvailableTimeSlots();

      if (mounted) {
        setState(() {
          _availabilitySlots = List<Map<String, dynamic>>.from(availabilityData);
        });
      }
    } catch (e) {
      print('Error loading availability: $e');
      Fluttertoast.showToast(
        msg: "Failed to load availability: $e",
        toastLength: Toast.LENGTH_LONG,
        backgroundColor: Colors.red,
      );
    }
  }

  void _updateAvailableTimeSlots() {
    _availableTimeSlots = _availabilityByDay[_selectedDay] ?? [];

    // Sort time slots by start time
    _availableTimeSlots.sort((a, b) {
      final aMinutes = a.startTime.hour * 60 + a.startTime.minute;
      final bMinutes = b.startTime.hour * 60 + b.startTime.minute;
      return aMinutes.compareTo(bMinutes);
    });
  }

  // Helper method to check if a time slot is selected
  bool _isSelectedTimeSlot(TimeSlot slot) {
    final selectedMinutes = _selectedTime.hour * 60 + _selectedTime.minute;
    final slotStartMinutes = slot.startTime.hour * 60 + slot.startTime.minute;
    final slotEndMinutes = slot.endTime.hour * 60 + slot.endTime.minute;

    return selectedMinutes >= slotStartMinutes && selectedMinutes < slotEndMinutes;
  }

  Future<void> _updateAppointmentStatus(String appointmentId, String status) async {
    if (_currentUserId == null) return;

    try {
      await _supabase
          .from('appointments')
          .update({
        'status': status,
        'updated_at': DateTime.now().toIso8601String(),
        'counselor_notes': status == 'completed' ? _notesController.text.trim() : null,
      })
          .eq('id', appointmentId)
          .eq('counselor_id', _currentUserId as String);

      // Update local state
      setState(() {
        for (final apt in _upcomingAppointments) {
          if (apt['id'] == appointmentId) {
            apt['status'] = status;
            if (status == 'completed' || status == 'cancelled') {
              apt['counselor_notes'] = status == 'completed' ? _notesController.text.trim() : null;

              // Move to past appointments if completed or cancelled
              _pastAppointments.add(apt);
              _upcomingAppointments.removeWhere((a) => a['id'] == appointmentId);

              // Sort past appointments by date (most recent first)
              _pastAppointments.sort((a, b) =>
                  DateTime.parse(b['appointment_date']).compareTo(DateTime.parse(a['appointment_date']))
              );
            }
            break;
          }
        }
      });

      Fluttertoast.showToast(
        msg: "Appointment ${_formatStatus(status)} successfully",
        backgroundColor: Colors.green,
      );
    } catch (e) {
      print('Error updating appointment status: $e');
      Fluttertoast.showToast(
        msg: "Failed to update appointment: $e",
        toastLength: Toast.LENGTH_LONG,
        backgroundColor: Colors.red,
      );
    }
  }

  Future<void> _confirmAppointment(String appointmentId) async {
    // Show confirmation dialog
    final bool confirmed = await _showConfirmationDialog(
      'Confirm Appointment',
      'Are you sure you want to confirm this appointment?',
      'Confirm',
    );
    if (!confirmed) return;

    await _updateAppointmentStatus(appointmentId, 'confirmed');
  }

  Future<void> _completeAppointment(String appointmentId) async {
    // First, show a confirmation dialog
    final bool confirmed = await _showConfirmationDialog(
      'Complete Appointment',
      'Are you sure you want to mark this appointment as completed?',
      'Continue',
    );
    if (!confirmed) return;

    // Reset notes controller
    _notesController.clear();

    // Show dialog to add notes
    final bool notesConfirmed = await _showCompletionDialog(appointmentId);
    if (!notesConfirmed) return;

    await _updateAppointmentStatus(appointmentId, 'completed');
  }

  Future<void> _cancelAppointment(String appointmentId) async {
    // Show confirmation dialog
    final bool confirmed = await _showConfirmationDialog(
      'Cancel Appointment',
      'Are you sure you want to cancel this appointment? This action cannot be undone.',
      'Cancel Appointment',
      isDestructive: true,
    );
    if (!confirmed) return;

    await _updateAppointmentStatus(appointmentId, 'cancelled');
  }

  Future<bool> _showConfirmationDialog(String title, String message, String confirmText, {bool isDestructive = false}) async {
    return await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: isDestructive ? Colors.red : AppColors.counselorColor,
              foregroundColor: Colors.white,
            ),
            child: Text(confirmText),
          ),
        ],
      ),
    ) ?? false;
  }

  Future<bool> _showCompletionDialog(String appointmentId) async {
    return await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Add Session Notes'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Add notes about this appointment (optional):'),
            const SizedBox(height: 16),
            TextField(
              controller: _notesController,
              maxLines: 4,
              decoration: InputDecoration(
                hintText: 'Enter session notes here...',
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
                contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.counselorColor,
              foregroundColor: Colors.white,
            ),
            child: const Text('Complete Appointment'),
          ),
        ],
      ),
    ) ?? false;
  }

  void _showRescheduleDialog(Map<String, dynamic> appointment) {
    if (_currentUserId == null) return;

    // Set initial values from the appointment
    final appointmentDate = DateTime.parse(appointment['appointment_date']);

    // Ensure the selected date is not before today
    final DateTime now = DateTime.now();
    final DateTime startDate = DateTime(now.year, now.month, now.day);

    if (appointmentDate.isBefore(startDate)) {
      _selectedDate = startDate.add(const Duration(days: 1));
    } else {
      _selectedDate = appointmentDate;
    }

    _selectedTime = TimeOfDay(hour: appointmentDate.hour, minute: appointmentDate.minute);

    // Update selected day based on the date
    _selectedDay = DateFormat('EEEE').format(_selectedDate);

    // Update available time slots for the selected day
    _updateAvailableTimeSlots();

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) {
          return AlertDialog(
            title: const Text('Reschedule Appointment'),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Date selection
                  const Text('Select New Date', style: TextStyle(fontWeight: FontWeight.bold)),
                  const SizedBox(height: 8),
                  InkWell(
                    onTap: () async {
                      final DateTime now = DateTime.now();
                      // Create a DateTime for the start of today
                      final DateTime startDate = DateTime(now.year, now.month, now.day);

                      final pickedDate = await showDatePicker(
                        context: context,
                        initialDate: _selectedDate.isBefore(startDate) ? startDate : _selectedDate,
                        firstDate: startDate, // Set firstDate to today
                        lastDate: DateTime.now().add(const Duration(days: 90)),
                      );

                      if (pickedDate != null) {
                        setDialogState(() {
                          _selectedDate = pickedDate;
                          // Update selected day and available time slots
                          _selectedDay = DateFormat('EEEE').format(_selectedDate);
                          _updateAvailableTimeSlots();
                        });
                      }
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                      decoration: BoxDecoration(
                        border: Border.all(color: Colors.grey),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.calendar_today, size: 18),
                          const SizedBox(width: 8),
                          Text(DateFormat('EEEE, MMMM d, yyyy').format(_selectedDate)),
                        ],
                      ),
                    ),
                  ),

                  const SizedBox(height: 16),

                  // Available time slots
                  const Text('Your Availability', style: TextStyle(fontWeight: FontWeight.bold)),
                  const SizedBox(height: 8),

                  if (_availableTimeSlots.isEmpty)
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.grey.shade100,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Text(
                        'No availability set for this day',
                        style: TextStyle(
                          fontStyle: FontStyle.italic,
                          color: Colors.grey,
                        ),
                      ),
                    )
                  else
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.grey.shade100,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Available times on $_selectedDay:',
                            style: const TextStyle(fontWeight: FontWeight.w500),
                          ),
                          const SizedBox(height: 8),
                          ...List.generate(_availableTimeSlots.length, (index) {
                            return InkWell(
                              onTap: () {
                                setDialogState(() {
                                  _selectedTime = _availableTimeSlots[index].startTime;
                                });
                              },
                              child: Container(
                                margin: const EdgeInsets.only(bottom: 4),
                                padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 8),
                                decoration: BoxDecoration(
                                  color: _isSelectedTimeSlot(_availableTimeSlots[index])
                                      ? AppColors.counselorColor.withOpacity(0.1)
                                      : Colors.transparent,
                                  borderRadius: BorderRadius.circular(4),
                                  border: _isSelectedTimeSlot(_availableTimeSlots[index])
                                      ? Border.all(color: AppColors.counselorColor)
                                      : null,
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    if (_isSelectedTimeSlot(_availableTimeSlots[index]))
                                      const Icon(Icons.check_circle, size: 14, color: AppColors.counselorColor),
                                    if (_isSelectedTimeSlot(_availableTimeSlots[index]))
                                      const SizedBox(width: 4),
                                    Text(
                                      _availableTimeSlots[index].toString(),
                                      style: TextStyle(
                                        fontWeight: _isSelectedTimeSlot(_availableTimeSlots[index])
                                            ? FontWeight.bold
                                            : FontWeight.normal,
                                        color: _isSelectedTimeSlot(_availableTimeSlots[index])
                                            ? AppColors.counselorColor
                                            : Colors.black,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            );
                          }),
                        ],
                      ),
                    ),

                  const SizedBox(height: 16),

                  // Time selection
                  const Text('Select New Time', style: TextStyle(fontWeight: FontWeight.bold)),
                  const SizedBox(height: 8),
                  InkWell(
                    onTap: () async {
                      final pickedTime = await showTimePicker(
                        context: context,
                        initialTime: _selectedTime,
                      );

                      if (pickedTime != null) {
                        setDialogState(() {
                          _selectedTime = pickedTime;
                        });
                      }
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                      decoration: BoxDecoration(
                        border: Border.all(color: Colors.grey),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.access_time, size: 18),
                          const SizedBox(width: 8),
                          Text(_selectedTime.format(context)),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Cancel'),
              ),
              ElevatedButton(
                onPressed: () async {
                  // Check if the selected time is within your availability
                  bool isTimeAvailable = false;
                  for (var slot in _availableTimeSlots) {
                    final slotStartMinutes = slot.startTime.hour * 60 + slot.startTime.minute;
                    final slotEndMinutes = slot.endTime.hour * 60 + slot.endTime.minute;
                    final selectedMinutes = _selectedTime.hour * 60 + _selectedTime.minute;

                    if (selectedMinutes >= slotStartMinutes && selectedMinutes < slotEndMinutes) {
                      isTimeAvailable = true;
                      break;
                    }
                  }

                  if (!isTimeAvailable && _availableTimeSlots.isNotEmpty) {
                    final bool confirmed = await _showTimeNotAvailableDialog();
                    if (!confirmed) return;
                  }

                  // Show confirmation dialog
                  final bool confirmed = await _showRescheduleConfirmationDialog(appointment);
                  if (!confirmed) return;

                  try {
                    // Format date and time
                    final formattedDate = DateFormat('yyyy-MM-dd').format(_selectedDate);
                    final formattedTime = '${_selectedTime.hour.toString().padLeft(2, '0')}:${_selectedTime.minute.toString().padLeft(2, '0')}:00';
                    final appointmentDateTime = '$formattedDate $formattedTime';

                    await _supabase
                        .from('appointments')
                        .update({
                      'appointment_date': appointmentDateTime,
                      'status': 'rescheduled',
                      'updated_at': DateTime.now().toIso8601String(),
                    })
                        .eq('id', appointment['id'] as String)
                        .eq('counselor_id', _currentUserId as String);

                    // Update local state
                    setState(() {
                      for (final apt in _upcomingAppointments) {
                        if (apt['id'] == appointment['id']) {
                          apt['appointment_date'] = appointmentDateTime;
                          apt['status'] = 'rescheduled';
                          break;
                        }
                      }

                      // Sort appointments by date
                      _upcomingAppointments.sort((a, b) =>
                          DateTime.parse(a['appointment_date']).compareTo(DateTime.parse(b['appointment_date']))
                      );
                    });

                    Navigator.pop(context);

                    Fluttertoast.showToast(
                      msg: "Appointment rescheduled successfully",
                      backgroundColor: Colors.green,
                    );
                  } catch (e) {
                    print('Error rescheduling appointment: $e');
                    Fluttertoast.showToast(
                      msg: "Failed to reschedule appointment: $e",
                      toastLength: Toast.LENGTH_LONG,
                      backgroundColor: Colors.red,
                    );
                  }
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.counselorColor,
                  foregroundColor: Colors.white,
                ),
                child: const Text('Reschedule'),
              ),
            ],
          );
        },
      ),
    );
  }

  Future<bool> _showTimeNotAvailableDialog() async {
    return await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Time Outside Your Availability'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('The selected time is outside your set availability hours.'),
            const SizedBox(height: 16),
            const Text('Available time slots:', style: TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            ..._availableTimeSlots.map((slot) => Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Text('• ${slot.toString()}'),
            )).toList(),
            const SizedBox(height: 16),
            const Text('Would you like to schedule anyway? This may create conflicts in your schedule.'),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.counselorColor,
              foregroundColor: Colors.white,
            ),
            child: const Text('Schedule Anyway'),
          ),
        ],
      ),
    ) ?? false;
  }

  Future<bool> _showRescheduleConfirmationDialog(Map<String, dynamic> appointment) async {
    final studentName = appointment['student'] != null
        ? appointment['student']['full_name'] ?? 'Unknown Student'
        : 'Unknown Student';

    final formattedDate = DateFormat('EEEE, MMMM d, yyyy').format(_selectedDate);
    final formattedTime = _selectedTime.format(context);
    final title = appointment['title'] ?? 'Counseling Session';
    final isAnonymous = appointment['is_anonymous'] ?? false;

    return await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Confirm Reschedule'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Are you sure you want to reschedule this appointment?'),
            const SizedBox(height: 16),
            Text('Student: $studentName', style: const TextStyle(fontWeight: FontWeight.bold)),
            Text('New Date: $formattedDate', style: const TextStyle(fontWeight: FontWeight.bold)),
            Text('New Time: $formattedTime', style: const TextStyle(fontWeight: FontWeight.bold)),
            Text('Title: $title', style: const TextStyle(fontWeight: FontWeight.bold)),
            if (isAnonymous)
              const Text(
                'This is an anonymous appointment',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  color: Colors.red,
                ),
              ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.counselorColor,
              foregroundColor: Colors.white,
            ),
            child: const Text('Confirm'),
          ),
        ],
      ),
    ) ?? false;
  }

  void _showAvailabilityManagementScreen() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => CounselorAvailabilityScreen(
          counselorId: _currentUserId!,
          initialAvailability: _availabilityByDay,
          onAvailabilityUpdated: () {
            _loadAvailability();
          },
        ),
      ),
    );
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
        backgroundColor: AppColors.counselorColor,
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.access_time, color: Colors.white),
            onPressed: _showAvailabilityManagementScreen,
            tooltip: 'Manage Availability',
          ),
          IconButton(
            icon: const Icon(Icons.refresh, color: Colors.white),
            onPressed: _loadData,
          ),
        ],
        bottom: TabBar(
          controller: _tabController,
          indicatorColor: Colors.white,
          indicatorWeight: 3,
          labelColor: Colors.white,
          unselectedLabelColor: Colors.white70,
          labelStyle: const TextStyle(fontWeight: FontWeight.bold),
          tabs: const [
            Tab(text: 'Upcoming'),
            Tab(text: 'Past'),
          ],
        ),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : TabBarView(
        controller: _tabController,
        children: [
          // Upcoming appointments
          _buildAppointmentsList(
            appointments: _upcomingAppointments,
            isUpcoming: true,
          ),

          // Past appointments
          _buildAppointmentsList(
            appointments: _pastAppointments,
            isUpcoming: false,
          ),
        ],
      ),
    );
  }

  Widget _buildAppointmentsList({
    required List<Map<String, dynamic>> appointments,
    required bool isUpcoming,
  }) {
    if (appointments.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              isUpcoming ? Icons.event_available : Icons.history,
              size: 64,
              color: Colors.grey.shade400,
            ),
            const SizedBox(height: 16),
            Text(
              isUpcoming ? 'No upcoming appointments' : 'No past appointments',
              style: TextStyle(
                fontSize: 16,
                color: Colors.grey.shade600,
              ),
            ),
          ],
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: appointments.length,
      itemBuilder: (context, index) {
        final appointment = appointments[index];
        final appointmentDate = DateTime.parse(appointment['appointment_date']);
        final studentName = appointment['student'] != null
            ? appointment['student']['full_name'] ?? 'Unknown Student'
            : 'Unknown Student';

        return _buildAppointmentCard(
          appointment: appointment,
          studentName: studentName,
          date: DateFormat('EEE, MMM d').format(appointmentDate),
          time: DateFormat('h:mm a').format(appointmentDate),
          status: appointment['status'] ?? 'pending',
          isUpcoming: isUpcoming,
          isAnonymous: appointment['is_anonymous'] ?? false,
        );
      },
    );
  }

  Widget _buildAppointmentCard({
    required Map<String, dynamic> appointment,
    required String studentName,
    required String date,
    required String time,
    required String status,
    required bool isUpcoming,
    required bool isAnonymous,
  }) {
    final statusColor = _getStatusColor(status);
    final appointmentDate = DateTime.parse(appointment['appointment_date']);
    final now = DateTime.now();
    final isToday = appointmentDate.day == now.day &&
        appointmentDate.month == now.month &&
        appointmentDate.year == now.year;

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
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
        border: isUpcoming && (status == 'pending' || status == 'confirmed')
            ? Border.all(color: isToday ? Colors.orange : AppColors.counselorColor, width: 2)
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
                  backgroundColor: isAnonymous ? Colors.grey.shade800 : Colors.blue,
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
                        studentName,
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                        ),
                      ),
                      Text(
                        appointment['title'] ?? 'Counseling Session',
                        style: const TextStyle(
                          color: AppColors.textSecondary,
                          fontSize: 14,
                        ),
                      ),
                      if (isAnonymous)
                        Row(
                          children: [
                            Icon(Icons.visibility_off, size: 12, color: Colors.grey.shade600),
                            const SizedBox(width: 4),
                            Text(
                              'Anonymous appointment',
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
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: statusColor.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    _formatStatus(status),
                    style: TextStyle(
                      color: statusColor,
                      fontWeight: FontWeight.bold,
                      fontSize: 12,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: Row(
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
                ),
                Expanded(
                  child: Row(
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
                ),
              ],
            ),

            if (appointment['description'] != null && appointment['description'].toString().isNotEmpty) ...[
              const SizedBox(height: 12),
              const Divider(),
              const SizedBox(height: 8),
              Text(
                'Reason for appointment:',
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
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
              ),
            ],

            if (appointment['counselor_notes'] != null && appointment['counselor_notes'].toString().isNotEmpty) ...[
              const SizedBox(height: 12),
              const Divider(),
              const SizedBox(height: 8),
              Text(
                'Counselor notes:',
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
                ),
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
              ),
            ],

            if (isUpcoming && (status == 'pending' || status == 'confirmed' || status == 'rescheduled')) ...[
              const SizedBox(height: 16),
              const Divider(),
              const SizedBox(height: 8),

              // Action buttons based on status
              if (status == 'pending' || status == 'rescheduled')
                Row(
                  children: [
                    Expanded(
                      child: ElevatedButton(
                        onPressed: () => _confirmAppointment(appointment['id'] as String),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.counselorColor,
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                        ),
                        child: const Text('Confirm'),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () => _showRescheduleDialog(appointment),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: AppColors.counselorColor,
                          side: const BorderSide(color: AppColors.counselorColor),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                        ),
                        child: const Text('Reschedule'),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: ElevatedButton(
                        onPressed: () => _cancelAppointment(appointment['id'] as String),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.red,
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                        ),
                        child: const Text('Cancel'),
                      ),
                    ),
                  ],
                ),

              if (status == 'confirmed')
                Row(
                  children: [
                    Expanded(
                      child: ElevatedButton(
                        onPressed: () => _completeAppointment(appointment['id'] as String),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.green,
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                        ),
                        child: const Text('Complete'),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () => _showRescheduleDialog(appointment),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: AppColors.counselorColor,
                          side: const BorderSide(color: AppColors.counselorColor),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                        ),
                        child: const Text('Reschedule'),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: ElevatedButton(
                        onPressed: () => _cancelAppointment(appointment['id'] as String),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.red,
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                        ),
                        child: const Text('Cancel'),
                      ),
                    ),
                  ],
                ),
            ],
          ],
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

  String _formatStatus(String status) {
    // Capitalize first letter
    return status.substring(0, 1).toUpperCase() + status.substring(1);
  }
}

// TimeSlot class to represent a time range
class TimeSlot {
  final TimeOfDay startTime;
  final TimeOfDay endTime;

  TimeSlot(this.startTime, this.endTime);

  @override
  String toString() {
    return '${_formatTimeOfDay(startTime)} - ${_formatTimeOfDay(endTime)}';
  }

  String _formatTimeOfDay(TimeOfDay time) {
    final hour = time.hour.toString().padLeft(2, '0');
    final minute = time.minute.toString().padLeft(2, '0');
    final period = time.hour < 12 ? 'AM' : 'PM';
    final displayHour = time.hourOfPeriod == 0 ? 12 : time.hourOfPeriod;
    return '$displayHour:${minute.padLeft(2, '0')} $period';
  }
}

// Counselor Availability Screen
class CounselorAvailabilityScreen extends StatefulWidget {
  final String counselorId;
  final Map<String, List<TimeSlot>> initialAvailability;
  final VoidCallback onAvailabilityUpdated;

  const CounselorAvailabilityScreen({
    Key? key,
    required this.counselorId,
    required this.initialAvailability,
    required this.onAvailabilityUpdated,
  }) : super(key: key);

  @override
  State<CounselorAvailabilityScreen> createState() => _CounselorAvailabilityScreenState();
}

class _CounselorAvailabilityScreenState extends State<CounselorAvailabilityScreen> {
  late Map<String, List<TimeSlot>> _availability;
  final SupabaseClient _supabase = Supabase.instance.client;
  bool _isLoading = false;
  final List<String> _weekdays = ['Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday'];
  bool _hasChanges = false;

  @override
  void initState() {
    super.initState();
    // Deep copy the initial availability
    _availability = {};
    for (var entry in widget.initialAvailability.entries) {
      _availability[entry.key] = List<TimeSlot>.from(entry.value);
    }
  }

  Future<void> _saveAvailability() async {
    // Show confirmation dialog before saving
    final bool shouldSave = await _showSaveConfirmationDialog();
    if (!shouldSave) return;

    setState(() {
      _isLoading = true;
    });

    try {
      // First, delete all existing availability slots for this counselor
      await _supabase
          .from('counselor_availability')
          .delete()
          .eq('counselor_id', widget.counselorId);

      // Then, insert all the new availability slots
      final List<Map<String, dynamic>> slotsToInsert = [];

      for (var day in _weekdays) {
        for (var slot in _availability[day] ?? []) {
          slotsToInsert.add({
            'counselor_id': widget.counselorId,
            'day_of_week': day,
            'start_time': '${slot.startTime.hour.toString().padLeft(2, '0')}:${slot.startTime.minute.toString().padLeft(2, '0')}:00',
            'end_time': '${slot.endTime.hour.toString().padLeft(2, '0')}:${slot.endTime.minute.toString().padLeft(2, '0')}:00',
          });
        }
      }

      if (slotsToInsert.isNotEmpty) {
        await _supabase
            .from('counselor_availability')
            .insert(slotsToInsert);
      }

      widget.onAvailabilityUpdated();
      _hasChanges = false;

      Fluttertoast.showToast(
        msg: "Availability saved successfully",
        backgroundColor: Colors.green,
      );

      Navigator.pop(context);
    } catch (e) {
      print('Error saving availability: $e');
      Fluttertoast.showToast(
        msg: "Failed to save availability: $e",
        toastLength: Toast.LENGTH_LONG,
        backgroundColor: Colors.red,
      );
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  Future<bool> _showSaveConfirmationDialog() async {
    return await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Save Availability'),
        content: const Text('Are you sure you want to save these availability settings? This will update your counseling schedule.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.counselorColor,
              foregroundColor: Colors.white,
            ),
            child: const Text('Save'),
          ),
        ],
      ),
    ) ?? false;
  }

  Future<bool> _showDeleteConfirmationDialog(String day, int index) async {
    final slot = _availability[day]![index];
    final formattedSlot = slot.toString();

    return await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Time Slot'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Are you sure you want to delete this time slot?'),
            const SizedBox(height: 16),
            Text('Day: $day', style: const TextStyle(fontWeight: FontWeight.bold)),
            Text('Time: $formattedSlot', style: const TextStyle(fontWeight: FontWeight.bold)),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              foregroundColor: Colors.white,
            ),
            child: const Text('Delete'),
          ),
        ],
      ),
    ) ?? false;
  }

  void _addTimeSlot(String day) async {
    final TimeOfDay? startTime = await showTimePicker(
      context: context,
      initialTime: const TimeOfDay(hour: 9, minute: 0),
      builder: (context, child) {
        return Theme(
          data: ThemeData.light().copyWith(
            colorScheme: const ColorScheme.light(
              primary: AppColors.counselorColor,
            ),
          ),
          child: child!,
        );
      },
    );

    if (startTime == null) return;

    final TimeOfDay? endTime = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(
        hour: (startTime.hour + 1) % 24,
        minute: startTime.minute,
      ),
      builder: (context, child) {
        return Theme(
          data: ThemeData.light().copyWith(
            colorScheme: const ColorScheme.light(
              primary: AppColors.counselorColor,
            ),
          ),
          child: child!,
        );
      },
    );

    if (endTime == null) return;

    // Validate that end time is after start time
    final now = DateTime.now();
    final startDateTime = DateTime(now.year, now.month, now.day, startTime.hour, startTime.minute);
    final endDateTime = DateTime(now.year, now.month, now.day, endTime.hour, endTime.minute);

    if (endDateTime.isBefore(startDateTime) || endDateTime.isAtSameMomentAs(startDateTime)) {
      Fluttertoast.showToast(
        msg: "End time must be after start time",
        backgroundColor: Colors.red,
      );
      return;
    }

    setState(() {
      _availability[day]!.add(TimeSlot(startTime, endTime));
      // Sort time slots by start time
      _availability[day]!.sort((a, b) {
        final aMinutes = a.startTime.hour * 60 + a.startTime.minute;
        final bMinutes = b.startTime.hour * 60 + b.startTime.minute;
        return aMinutes.compareTo(bMinutes);
      });
      _hasChanges = true;
    });
  }

  void _removeTimeSlot(String day, int index) async {
    // Show confirmation dialog before deleting
    final bool shouldDelete = await _showDeleteConfirmationDialog(day, index);
    if (!shouldDelete) return;

    setState(() {
      _availability[day]!.removeAt(index);
      _hasChanges = true;
    });
  }

  @override
  Widget build(BuildContext context) {
    return WillPopScope(
      onWillPop: () async {
        if (_hasChanges) {
          // Show confirmation dialog if there are unsaved changes
          final bool shouldDiscard = await showDialog<bool>(
            context: context,
            builder: (context) => AlertDialog(
              title: const Text('Unsaved Changes'),
              content: const Text('You have unsaved changes. Are you sure you want to discard them?'),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context, false),
                  child: const Text('Cancel'),
                ),
                ElevatedButton(
                  onPressed: () => Navigator.pop(context, true),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.red,
                    foregroundColor: Colors.white,
                  ),
                  child: const Text('Discard'),
                ),
              ],
            ),
          ) ?? false;

          return shouldDiscard;
        }
        return true;
      },
      child: Scaffold(
        appBar: AppBar(
          title: const Text(
            'Manage Availability',
            style: TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.bold,
            ),
          ),
          backgroundColor: AppColors.counselorColor,
          elevation: 0,
          actions: [
            if (_isLoading)
              const Padding(
                padding: EdgeInsets.all(16.0),
                child: SizedBox(
                  width: 24,
                  height: 24,
                  child: CircularProgressIndicator(
                    color: Colors.white,
                    strokeWidth: 2,
                  ),
                ),
              )
            else
              IconButton(
                icon: const Icon(Icons.save, color: Colors.white),
                onPressed: _saveAvailability,
                tooltip: 'Save Availability',
              ),
          ],
        ),
        body: ListView.builder(
          padding: const EdgeInsets.all(16),
          itemCount: _weekdays.length,
          itemBuilder: (context, index) {
            final day = _weekdays[index];
            final slots = _availability[day] ?? [];

            return Card(
              margin: const EdgeInsets.only(bottom: 16),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              elevation: 2,
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          day,
                          style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        ElevatedButton.icon(
                          onPressed: () => _addTimeSlot(day),
                          icon: const Icon(Icons.add, size: 18),
                          label: const Text('Add Time Slot'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppColors.counselorColor,
                            foregroundColor: Colors.white,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(8),
                            ),
                            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    if (slots.isEmpty)
                      Container(
                        padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 12),
                        decoration: BoxDecoration(
                          color: Colors.grey.shade100,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: const Center(
                          child: Text(
                            'No availability set for this day',
                            style: TextStyle(
                              fontStyle: FontStyle.italic,
                              color: Colors.grey,
                            ),
                          ),
                        ),
                      )
                    else
                      ListView.builder(
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        itemCount: slots.length,
                        itemBuilder: (context, slotIndex) {
                          final slot = slots[slotIndex];
                          return Container(
                            margin: const EdgeInsets.only(bottom: 8.0),
                            decoration: BoxDecoration(
                              color: Colors.grey.shade50,
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(color: Colors.grey.shade300),
                            ),
                            child: ListTile(
                              contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                              title: Text(
                                slot.toString(),
                                style: const TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                              leading: Container(
                                width: 40,
                                height: 40,
                                decoration: BoxDecoration(
                                  color: AppColors.counselorColor.withOpacity(0.1),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: const Icon(
                                  Icons.access_time,
                                  color: AppColors.counselorColor,
                                ),
                              ),
                              trailing: IconButton(
                                icon: const Icon(Icons.delete, color: Colors.red),
                                onPressed: () => _removeTimeSlot(day, slotIndex),
                                tooltip: 'Remove Time Slot',
                              ),
                            ),
                          );
                        },
                      ),
                  ],
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}