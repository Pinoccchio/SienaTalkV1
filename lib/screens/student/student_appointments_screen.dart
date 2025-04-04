import 'dart:async';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart' as firebase;
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:intl/intl.dart';
import 'package:fluttertoast/fluttertoast.dart';
import '../../utils/app_colors.dart';

class StudentAppointmentsScreen extends StatefulWidget {
  const StudentAppointmentsScreen({Key? key}) : super(key: key);

  @override
  State<StudentAppointmentsScreen> createState() => _StudentAppointmentsScreenState();
}

class _StudentAppointmentsScreenState extends State<StudentAppointmentsScreen> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final firebase.FirebaseAuth _firebaseAuth = firebase.FirebaseAuth.instance;
  final SupabaseClient _supabase = Supabase.instance.client;

  String? _currentUserId;
  bool _isLoading = true;
  List<Map<String, dynamic>> _upcomingAppointments = [];
  List<Map<String, dynamic>> _pastAppointments = [];
  List<Map<String, dynamic>> _counselors = [];
  bool _isAnonymousMode = false;
  Map<String, dynamic>? _userProfile;

  // For appointment creation
  Map<String, dynamic>? _selectedCounselor;
  DateTime _selectedDate = DateTime.now().add(const Duration(days: 1));
  TimeOfDay _selectedTime = const TimeOfDay(hour: 9, minute: 0);
  final TextEditingController _titleController = TextEditingController();
  final TextEditingController _descriptionController = TextEditingController();
  bool _isSubmitting = false;

  // For counselor availability
  Map<String, List<TimeSlot>> _counselorAvailability = {};
  String _selectedDay = '';
  List<TimeSlot> _availableTimeSlots = [];
  RealtimeChannel? _appointmentsChannel;
  bool _isMounted = true;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _currentUserId = _firebaseAuth.currentUser?.uid;
    _ensureSelectedDateIsValid();
    _loadUserProfile();
    _loadData();
    _setupRealtimeSubscription();
  }

  void _setupRealtimeSubscription() {
    if (_currentUserId == null) return;

    // Subscribe to changes in appointments table
    _appointmentsChannel = _supabase
        .channel('public:appointments:student')
        .onPostgresChanges(
      event: PostgresChangeEvent.insert,
      schema: 'public',
      table: 'appointments',
      callback: (payload) {
        if (_isMounted && payload.newRecord?['student_id'] == _currentUserId) {
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
            (payload.oldRecord?['student_id'] == _currentUserId ||
                payload.newRecord?['student_id'] == _currentUserId)) {
          _loadData();
        }
      },
    )
        .onPostgresChanges(
      event: PostgresChangeEvent.delete,
      schema: 'public',
      table: 'appointments',
      callback: (payload) {
        if (_isMounted && payload.oldRecord?['student_id'] == _currentUserId) {
          _loadData();
        }
      },
    )
        .subscribe();
  }

  Future<void> _loadUserProfile() async {
    final userId = _firebaseAuth.currentUser?.uid;
    if (userId == null) return;

    try {
      final data = await _supabase
          .from('user_profiles')
          .select('*')
          .eq('user_id', userId)
          .single();

      if (mounted) {
        setState(() {
          _userProfile = data;
          _isAnonymousMode = data['is_anonymous'] ?? false;
        });
      }
    } catch (e) {
      print('Error loading user profile: $e');
    }
  }

  Future<void> _toggleAnonymousMode() async {
    final userId = _firebaseAuth.currentUser?.uid;
    if (userId == null) return;

    try {
      // Update the user profile
      await _supabase
          .from('user_profiles')
          .update({'is_anonymous': !_isAnonymousMode})
          .eq('user_id', userId);

      if (mounted) {
        setState(() {
          _isAnonymousMode = !_isAnonymousMode;
          if (_userProfile != null) {
            _userProfile!['is_anonymous'] = _isAnonymousMode;
          }
        });
      }

      Fluttertoast.showToast(
        msg: _isAnonymousMode
            ? "Anonymous mode enabled"
            : "Anonymous mode disabled",
        toastLength: Toast.LENGTH_SHORT,
        gravity: ToastGravity.BOTTOM,
        backgroundColor: AppColors.primary,
      );
    } catch (e) {
      print('Error toggling anonymous mode: $e');
      Fluttertoast.showToast(
        msg: "Error changing anonymous mode",
        toastLength: Toast.LENGTH_SHORT,
        gravity: ToastGravity.BOTTOM,
        backgroundColor: Colors.red,
      );
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
    _titleController.dispose();
    _descriptionController.dispose();
    if (_appointmentsChannel != null) {
      _appointmentsChannel!.unsubscribe();
    }
    super.dispose();
  }

  Future<void> _loadData() async {
    if (_currentUserId == null) return;

    setState(() {
      _isLoading = true;
    });

    try {
      // Load counselors
      final counselorsData = await _supabase
          .from('user_profiles')
          .select('user_id, full_name')
          .eq('user_type', 'counselor');

      print('Counselors loaded: ${counselorsData.length}');

      // Load appointments - Using explicit foreign key reference to avoid ambiguity
      // First, get the appointments
      final appointmentsData = await _supabase
          .from('appointments')
          .select('*')
          .eq('student_id', _currentUserId as String)
          .order('appointment_date', ascending: true);

      print('Appointments loaded: ${appointmentsData.length}');

      // Then, for each appointment, get the counselor details
      for (final appointment in appointmentsData) {
        if (appointment['counselor_id'] != null) {
          final counselorData = await _supabase
              .from('user_profiles')
              .select('full_name')
              .eq('user_id', appointment['counselor_id'])
              .single();

          appointment['counselor'] = counselorData;
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
          _counselors = List<Map<String, dynamic>>.from(counselorsData);
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

  Future<void> _loadCounselorAvailability(String counselorId) async {
    try {
      // Reset availability
      _counselorAvailability = {};
      for (var day in ['Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday']) {
        _counselorAvailability[day] = [];
      }

      // Load availability slots from the database
      final availabilityData = await _supabase
          .from('counselor_availability')
          .select('*')
          .eq('counselor_id', counselorId);

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

        if (_counselorAvailability.containsKey(day)) {
          _counselorAvailability[day]!.add(TimeSlot(startTime, endTime));
        }
      }

      // Update available time slots for the selected day
      _updateAvailableTimeSlots();

      if (availabilityData.isEmpty) {
        Fluttertoast.showToast(
          msg: "This counselor has not set their availability yet",
          backgroundColor: Colors.orange,
        );
      }
    } catch (e) {
      print('Error loading counselor availability: $e');
      Fluttertoast.showToast(
        msg: "Failed to load counselor availability",
        backgroundColor: Colors.red,
      );
    }
  }

  void _updateAvailableTimeSlots() {
    _availableTimeSlots = _counselorAvailability[_selectedDay] ?? [];

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

  Future<void> _createAppointment() async {
    if (_currentUserId == null || _selectedCounselor == null) return;

    final title = _titleController.text.trim();
    final description = _descriptionController.text.trim();

    if (title.isEmpty) {
      Fluttertoast.showToast(
        msg: "Please enter a title for the appointment",
        backgroundColor: Colors.red,
      );
      return;
    }

    // Check if the selected time is within the counselor's availability
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
    final bool confirmed = await _showScheduleConfirmationDialog();
    if (!confirmed) return;

    setState(() {
      _isSubmitting = true;
    });

    try {
      // Format date and time
      final formattedDate = DateFormat('yyyy-MM-dd').format(_selectedDate);
      final formattedTime = '${_selectedTime.hour.toString().padLeft(2, '0')}:${_selectedTime.minute.toString().padLeft(2, '0')}:00';
      final appointmentDateTime = '$formattedDate $formattedTime';

      // Create appointment
      final appointmentData = {
        'student_id': _currentUserId as String,
        'counselor_id': _selectedCounselor!['user_id'],
        'title': title,
        'description': description,
        'appointment_date': appointmentDateTime,
        'status': 'pending',
        'is_anonymous': _isAnonymousMode, // Add anonymous flag
      };

      final response = await _supabase
          .from('appointments')
          .insert(appointmentData)
          .select();

      if (mounted) {
        setState(() {
          _isSubmitting = false;
        });

        if (response.isNotEmpty) {
          // Add counselor info to the response
          final newAppointment = response[0];
          newAppointment['counselor'] = {
            'full_name': _selectedCounselor!['full_name'],
          };

          setState(() {
            _upcomingAppointments.add(newAppointment);
            // Sort appointments by date
            _upcomingAppointments.sort((a, b) =>
                DateTime.parse(a['appointment_date']).compareTo(DateTime.parse(b['appointment_date']))
            );
          });

          Navigator.pop(context); // Close the dialog

          Fluttertoast.showToast(
            msg: "Appointment scheduled successfully",
            backgroundColor: Colors.green,
          );

          // Reset form
          _titleController.clear();
          _descriptionController.clear();
          _selectedCounselor = null;
          _selectedDate = DateTime.now().add(const Duration(days: 1));
          _selectedTime = const TimeOfDay(hour: 9, minute: 0);
        }
      }
    } catch (e) {
      print('Error creating appointment: $e');
      if (mounted) {
        setState(() {
          _isSubmitting = false;
        });
        Fluttertoast.showToast(
          msg: "Failed to schedule appointment: $e",
          toastLength: Toast.LENGTH_LONG,
          backgroundColor: Colors.red,
        );
      }
    }
  }

  Future<bool> _showTimeNotAvailableDialog() async {
    return await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Time Not Available'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('The selected time is outside the counselor\'s availability hours.'),
            const SizedBox(height: 16),
            const Text('Available time slots:', style: TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            ..._availableTimeSlots.map((slot) => Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Text('• ${slot.toString()}'),
            )).toList(),
            const SizedBox(height: 16),
            const Text('Would you like to schedule anyway? The counselor may need to reschedule.'),
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
              backgroundColor: AppColors.primary,
              foregroundColor: Colors.white,
            ),
            child: const Text('Schedule Anyway'),
          ),
        ],
      ),
    ) ?? false;
  }

  Future<bool> _showScheduleConfirmationDialog() async {
    if (_selectedCounselor == null) return false;

    final counselorName = _selectedCounselor!['full_name'] ?? 'Unknown';
    final formattedDate = DateFormat('EEEE, MMMM d, yyyy').format(_selectedDate);
    final formattedTime = _selectedTime.format(context);
    final title = _titleController.text.trim();

    return await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Confirm Appointment'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Are you sure you want to schedule this appointment?'),
            const SizedBox(height: 16),
            Text('Counselor: $counselorName', style: const TextStyle(fontWeight: FontWeight.bold)),
            Text('Date: $formattedDate', style: const TextStyle(fontWeight: FontWeight.bold)),
            Text('Time: $formattedTime', style: const TextStyle(fontWeight: FontWeight.bold)),
            Text('Title: $title', style: const TextStyle(fontWeight: FontWeight.bold)),
            if (_isAnonymousMode)
              const Text(
                'This appointment will be anonymous',
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
              backgroundColor: AppColors.primary,
              foregroundColor: Colors.white,
            ),
            child: const Text('Confirm'),
          ),
        ],
      ),
    ) ?? false;
  }

  Future<void> _cancelAppointment(String appointmentId) async {
    if (_currentUserId == null) return;

    // Show confirmation dialog
    final bool confirmed = await _showCancelConfirmationDialog(appointmentId);
    if (!confirmed) return;

    try {
      await _supabase
          .from('appointments')
          .update({'status': 'cancelled'})
          .eq('id', appointmentId)
          .eq('student_id', _currentUserId as String);

      // Update local state
      setState(() {
        for (final appointment in _upcomingAppointments) {
          if (appointment['id'] == appointmentId) {
            appointment['status'] = 'cancelled';

            // Move to past appointments if cancelled
            _pastAppointments.add(appointment);
            _upcomingAppointments.removeWhere((a) => a['id'] == appointmentId);

            // Sort past appointments by date (most recent first)
            _pastAppointments.sort((a, b) =>
                DateTime.parse(b['appointment_date']).compareTo(DateTime.parse(a['appointment_date']))
            );
            break;
          }
        }
      });

      Fluttertoast.showToast(
        msg: "Appointment cancelled successfully",
        backgroundColor: Colors.green,
      );
    } catch (e) {
      print('Error cancelling appointment: $e');
      Fluttertoast.showToast(
        msg: "Failed to cancel appointment: $e",
        toastLength: Toast.LENGTH_LONG,
        backgroundColor: Colors.red,
      );
    }
  }

  Future<bool> _showCancelConfirmationDialog(String appointmentId) async {
    // Find the appointment
    final appointment = _upcomingAppointments.firstWhere(
          (apt) => apt['id'] == appointmentId,
      orElse: () => <String, dynamic>{},
    );

    if (appointment.isEmpty) return false;

    final counselorName = appointment['counselor'] != null
        ? appointment['counselor']['full_name'] ?? 'Unknown Counselor'
        : 'Unknown Counselor';

    final appointmentDate = DateTime.parse(appointment['appointment_date']);
    final formattedDate = DateFormat('EEEE, MMMM d, yyyy').format(appointmentDate);
    final formattedTime = DateFormat('h:mm a').format(appointmentDate);
    final title = appointment['title'] ?? 'Counseling Session';

    return await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Cancel Appointment'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Are you sure you want to cancel this appointment?'),
            const SizedBox(height: 16),
            Text('Counselor: $counselorName', style: const TextStyle(fontWeight: FontWeight.bold)),
            Text('Date: $formattedDate', style: const TextStyle(fontWeight: FontWeight.bold)),
            Text('Time: $formattedTime', style: const TextStyle(fontWeight: FontWeight.bold)),
            Text('Title: $title', style: const TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 16),
            const Text('This action cannot be undone.', style: TextStyle(color: Colors.red)),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Keep Appointment'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              foregroundColor: Colors.white,
            ),
            child: const Text('Cancel Appointment'),
          ),
        ],
      ),
    ) ?? false;
  }

  void _showScheduleDialog() {
    // Reset the selected counselor to ensure dropdown works correctly
    _selectedCounselor = null;
    _counselorAvailability = {};
    _availableTimeSlots = [];

    // Ensure selected date is valid
    _ensureSelectedDateIsValid();

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) {
          return AlertDialog(
            title: const Text('Schedule Appointment'),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Anonymous mode toggle
                  SwitchListTile(
                    title: const Text('Anonymous Appointment',
                        style: TextStyle(fontWeight: FontWeight.bold)),
                    subtitle: const Text('Hide your identity from the counselor'),
                    value: _isAnonymousMode,
                    activeColor: AppColors.primary,
                    onChanged: (value) {
                      setDialogState(() {
                        _isAnonymousMode = value;
                      });
                    },
                  ),
                  const Divider(),

                  // Counselor selection
                  const Text('Select Counselor', style: TextStyle(fontWeight: FontWeight.bold)),
                  const SizedBox(height: 8),

                  // Debug info to check counselors
                  Text('Available counselors: ${_counselors.length}',
                      style: TextStyle(fontSize: 12, color: Colors.grey)),
                  const SizedBox(height: 8),

                  // Fixed dropdown to ensure it's visible and populated
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    decoration: BoxDecoration(
                      border: Border.all(color: Colors.grey),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: DropdownButton<Map<String, dynamic>>(
                      isExpanded: true,
                      hint: const Text('Select a counselor'),
                      value: _selectedCounselor,
                      underline: const SizedBox(), // Remove the default underline
                      items: _counselors.map((counselor) {
                        return DropdownMenuItem<Map<String, dynamic>>(
                          value: counselor,
                          child: Text(counselor['full_name'] ?? 'Unknown'),
                        );
                      }).toList(),
                      onChanged: (value) {
                        setDialogState(() {
                          _selectedCounselor = value;
                          if (value != null) {
                            // Load counselor availability when selected
                            _loadCounselorAvailability(value['user_id']).then((_) {
                              setDialogState(() {
                                // Update available time slots
                                _updateAvailableTimeSlots();
                              });
                            });
                          }
                        });
                      },
                    ),
                  ),

                  const SizedBox(height: 16),

                  // Date selection
                  const Text('Select Date', style: TextStyle(fontWeight: FontWeight.bold)),
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
                  if (_selectedCounselor != null) ...[
                    const Text('Counselor Availability', style: TextStyle(fontWeight: FontWeight.bold)),
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
                                        ? AppColors.primary.withOpacity(0.1)
                                        : Colors.transparent,
                                    borderRadius: BorderRadius.circular(4),
                                    border: _isSelectedTimeSlot(_availableTimeSlots[index])
                                        ? Border.all(color: AppColors.primary)
                                        : null,
                                  ),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      if (_isSelectedTimeSlot(_availableTimeSlots[index]))
                                        const Icon(Icons.check_circle, size: 14, color: AppColors.primary),
                                      if (_isSelectedTimeSlot(_availableTimeSlots[index]))
                                        const SizedBox(width: 4),
                                      Text(
                                        _availableTimeSlots[index].toString(),
                                        style: TextStyle(
                                          fontWeight: _isSelectedTimeSlot(_availableTimeSlots[index])
                                              ? FontWeight.bold
                                              : FontWeight.normal,
                                          color: _isSelectedTimeSlot(_availableTimeSlots[index])
                                              ? AppColors.primary
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
                  ],

                  // Time selection
                  const Text('Select Time', style: TextStyle(fontWeight: FontWeight.bold)),
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

                  const SizedBox(height: 16),

                  // Title
                  const Text('Appointment Title', style: TextStyle(fontWeight: FontWeight.bold)),
                  const SizedBox(height: 8),
                  TextField(
                    controller: _titleController,
                    decoration: InputDecoration(
                      hintText: 'e.g., Career Guidance',
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    ),
                  ),

                  const SizedBox(height: 16),

                  // Description
                  const Text('Description', style: TextStyle(fontWeight: FontWeight.bold)),
                  const SizedBox(height: 8),
                  TextField(
                    controller: _descriptionController,
                    maxLines: 3,
                    decoration: InputDecoration(
                      hintText: 'Describe the reason for your appointment',
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
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
                onPressed: _isSubmitting ? null : _createAppointment,
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  foregroundColor: Colors.white,
                ),
                child: _isSubmitting
                    ? const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Colors.white,
                  ),
                )
                    : const Text('Schedule'),
              ),
            ],
          );
        },
      ),
    );
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

    // Reset availability data
    _counselorAvailability = {};
    _availableTimeSlots = [];

    // Load counselor availability
    if (appointment['counselor_id'] != null) {
      _loadCounselorAvailability(appointment['counselor_id']).then((_) {
        _updateAvailableTimeSlots();
      });
    }

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
                  const Text('Counselor Availability', style: TextStyle(fontWeight: FontWeight.bold)),
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
                                      ? AppColors.primary.withOpacity(0.1)
                                      : Colors.transparent,
                                  borderRadius: BorderRadius.circular(4),
                                  border: _isSelectedTimeSlot(_availableTimeSlots[index])
                                      ? Border.all(color: AppColors.primary)
                                      : null,
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    if (_isSelectedTimeSlot(_availableTimeSlots[index]))
                                      const Icon(Icons.check_circle, size: 14, color: AppColors.primary),
                                    if (_isSelectedTimeSlot(_availableTimeSlots[index]))
                                      const SizedBox(width: 4),
                                    Text(
                                      _availableTimeSlots[index].toString(),
                                      style: TextStyle(
                                        fontWeight: _isSelectedTimeSlot(_availableTimeSlots[index])
                                            ? FontWeight.bold
                                            : FontWeight.normal,
                                        color: _isSelectedTimeSlot(_availableTimeSlots[index])
                                            ? AppColors.primary
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
                  // Check if the selected time is within the counselor's availability
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
                        .eq('student_id', _currentUserId as String);

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
                  backgroundColor: AppColors.primary,
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

  Future<bool> _showRescheduleConfirmationDialog(Map<String, dynamic> appointment) async {
    final counselorName = appointment['counselor'] != null
        ? appointment['counselor']['full_name'] ?? 'Unknown Counselor'
        : 'Unknown Counselor';

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
            Text('Counselor: $counselorName', style: const TextStyle(fontWeight: FontWeight.bold)),
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
              backgroundColor: AppColors.primary,
              foregroundColor: Colors.white,
            ),
            child: const Text('Confirm'),
          ),
        ],
      ),
    ) ?? false;
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
        backgroundColor: AppColors.primary,
        elevation: 0,
        actions: [
          // Anonymous mode toggle
          IconButton(
            icon: Icon(
              _isAnonymousMode ? Icons.visibility_off : Icons.visibility,
              color: Colors.white,
            ),
            onPressed: _toggleAnonymousMode,
            tooltip: _isAnonymousMode ? 'Disable Anonymous Mode' : 'Enable Anonymous Mode',
          ),
          IconButton(
            icon: const Icon(Icons.refresh, color: Colors.white),
            onPressed: _loadData,
            tooltip: 'Refresh Appointments',
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
      body: Column(
        children: [
          // Anonymous mode banner
          if (_isAnonymousMode)
            Container(
              padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
              color: Colors.grey.shade800,
              child: Row(
                children: [
                  const Icon(Icons.visibility_off, color: Colors.white, size: 18),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Anonymous mode is enabled. Your identity will be hidden from counselors.',
                      style: TextStyle(color: Colors.white, fontSize: 12),
                    ),
                  ),
                  TextButton(
                    onPressed: _toggleAnonymousMode,
                    child: const Text(
                      'Disable',
                      style: TextStyle(color: Colors.white),
                    ),
                    style: TextButton.styleFrom(
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      minimumSize: const Size(0, 0),
                    ),
                  ),
                ],
              ),
            ),

          // Tab content
          Expanded(
            child: _isLoading
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
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _showScheduleDialog,
        backgroundColor: AppColors.primary,
        child: const Icon(Icons.add),
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
            if (isUpcoming) ...[
              const SizedBox(height: 16),
              ElevatedButton.icon(
                onPressed: _showScheduleDialog,
                icon: const Icon(Icons.add),
                label: const Text('Schedule Appointment'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  foregroundColor: Colors.white,
                ),
              ),
            ],
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
        final counselorName = appointment['counselor'] != null
            ? appointment['counselor']['full_name'] ?? 'Unknown Counselor'
            : 'Unknown Counselor';

        return _buildAppointmentCard(
          appointment: appointment,
          counselorName: counselorName,
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
    required String counselorName,
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
            ? Border.all(color: isToday ? Colors.orange : AppColors.primary, width: 2)
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
                  backgroundColor: isAnonymous ? Colors.grey.shade800 : AppColors.counselorColor,
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

            // Show counselor notes for completed appointments
            if (!isUpcoming && status == 'completed' &&
                appointment['counselor_notes'] != null &&
                appointment['counselor_notes'].toString().isNotEmpty) ...[
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

            if (isUpcoming && (status == 'pending' || status == 'confirmed' || status == 'rescheduled'))
              Padding(
                padding: const EdgeInsets.only(top: 16),
                child: Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () => _showRescheduleDialog(appointment),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: AppColors.primary,
                          side: const BorderSide(color: AppColors.primary),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                        ),
                        child: const Text('Reschedule'),
                      ),
                    ),
                    const SizedBox(width: 12),
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
              ),
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