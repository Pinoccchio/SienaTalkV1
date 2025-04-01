import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart' as firebase;
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:fluttertoast/fluttertoast.dart';
import '../../utils/app_colors.dart';

class StudentProfileScreen extends StatefulWidget {
  const StudentProfileScreen({Key? key}) : super(key: key);

  @override
  State<StudentProfileScreen> createState() => _StudentProfileScreenState();
}

class _StudentProfileScreenState extends State<StudentProfileScreen> {
  final _formKey = GlobalKey<FormState>();
  late TextEditingController _fullNameController;
  late TextEditingController _emailController;
  late TextEditingController _idNumberController;
  late TextEditingController _departmentController;
  bool _isEditing = false;
  bool _isLoading = true;
  bool _isUpdating = false;
  bool _isAnonymous = false;
  String? _errorMessage;

  // User data
  Map<String, dynamic>? _userData;

  final firebase.FirebaseAuth _firebaseAuth = firebase.FirebaseAuth.instance;
  final SupabaseClient _supabase = Supabase.instance.client;

  @override
  void initState() {
    super.initState();
    _fullNameController = TextEditingController();
    _emailController = TextEditingController();
    _idNumberController = TextEditingController();
    _departmentController = TextEditingController();

    // Load real user data
    _fetchUserData();
  }

  Future<void> _fetchUserData() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final currentUser = _firebaseAuth.currentUser;

      if (currentUser == null) {
        throw Exception('No authenticated user found');
      }

      // Get user email from Firebase
      final email = currentUser.email ?? '';

      // Try using RPC function first (most reliable)
      Map<String, dynamic>? userProfile;

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
        // RPC function might not exist, continue to next approach
      }

      // If RPC failed, try direct query with simplified approach
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

      // If we have a user profile, update the UI
      if (userProfile != null) {
        setState(() {
          _userData = userProfile;
          _fullNameController.text = _userData?['full_name'] ?? '';
          _emailController.text = email;
          _idNumberController.text = _userData?['id_number'] ?? '';
          _departmentController.text = _userData?['department'] ?? '';
          _isAnonymous = _userData?['is_anonymous'] ?? false;
          _isLoading = false;
        });

        print('Fetched user profile: $_userData');
      } else {
        throw Exception('User profile not found');
      }

    } catch (e) {
      print('Error fetching user profile: $e');
      setState(() {
        _errorMessage = 'Failed to load profile: $e';
        _isLoading = false;
      });

      Fluttertoast.showToast(
          msg: "Error loading profile: $e",
          toastLength: Toast.LENGTH_LONG,
          gravity: ToastGravity.BOTTOM,
          backgroundColor: Colors.red,
          textColor: Colors.white,
          fontSize: 16.0
      );
    }
  }

  Future<void> _updateProfile() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _isUpdating = true;
      _errorMessage = null;
    });

    try {
      final currentUser = _firebaseAuth.currentUser;

      if (currentUser == null) {
        throw Exception('No authenticated user found');
      }

      // Update Firebase display name
      await currentUser.updateDisplayName(_fullNameController.text);

      // Update user profile in Supabase using RPC to avoid recursion
      try {
        await _supabase.rpc(
          'update_user_profile',
          params: {
            'uid': currentUser.uid,
            'full_name_param': _fullNameController.text,
            'id_number_param': _idNumberController.text,
            'department_param': _departmentController.text,
            'is_anonymous_param': _isAnonymous,
          },
        );
      } catch (rpcError) {
        print('RPC error: $rpcError');

        // Fallback to direct update if RPC fails
        await _supabase
            .from('user_profiles')
            .update({
          'full_name': _fullNameController.text,
          'id_number': _idNumberController.text,
          'department': _departmentController.text,
          'updated_at': DateTime.now().toIso8601String(),
        })
            .eq('user_id', currentUser.uid);
      }

      // Refresh user data
      await _fetchUserData();

      setState(() {
        _isUpdating = false;
        _isEditing = false;
      });

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Profile updated successfully!'),
          backgroundColor: Colors.green,
        ),
      );

    } catch (e) {
      print('Error updating profile: $e');
      setState(() {
        _errorMessage = 'Failed to update profile: $e';
        _isUpdating = false;
      });

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to update profile: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  Future<void> _toggleAnonymousMode() async {
    setState(() {
      _isUpdating = true;
    });

    try {
      final currentUser = _firebaseAuth.currentUser;

      if (currentUser == null) {
        throw Exception('No authenticated user found');
      }

      // Toggle anonymous mode locally first
      final newAnonymousState = !_isAnonymous;

      // Try to use an RPC function to update the anonymous status
      // This can help avoid infinite recursion issues with policies
      bool updateSuccess = false;

      try {
        // Try using an RPC function if available
        await _supabase.rpc(
          'update_anonymous_status',
          params: {
            'uid': currentUser.uid,
            'is_anonymous_param': newAnonymousState,
          },
        );
        updateSuccess = true;
      } catch (rpcError) {
        print('RPC error: $rpcError');
        // RPC function might not exist, continue to next approach
      }

      // If RPC failed, try a raw SQL approach via a function
      if (!updateSuccess) {
        try {
          await _supabase.rpc(
            'execute_raw_update',
            params: {
              'query_text': 'UPDATE user_profiles SET is_anonymous = $newAnonymousState, updated_at = NOW() WHERE user_id = \'${currentUser.uid}\'',
            },
          );
          updateSuccess = true;
        } catch (rawError) {
          print('Raw query error: $rawError');
        }
      }

      // If both approaches failed, use the direct update as a last resort
      if (!updateSuccess) {
        // Use a more direct approach to avoid recursion
        final response = await _supabase.rest.from('user_profiles')
            .update({
          'is_anonymous': newAnonymousState,
          'updated_at': DateTime.now().toIso8601String(),
        })
            .eq('user_id', currentUser.uid);

        print('Direct update response: ');
      }

      // Update local state regardless of which method succeeded
      setState(() {
        _isAnonymous = newAnonymousState;
        _isUpdating = false;
      });

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Anonymous mode ${newAnonymousState ? 'enabled' : 'disabled'}'),
          backgroundColor: Colors.green,
        ),
      );

    } catch (e) {
      print('Error toggling anonymous mode: $e');

      // Even if the server update fails, update the UI to provide feedback
      setState(() {
        // Toggle the state locally to provide visual feedback
        _isAnonymous = !_isAnonymous;
        _isUpdating = false;
      });

      if (!mounted) return;

      // Show a warning that the change might not persist
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Anonymous mode toggled locally, but server update failed: $e'),
          backgroundColor: Colors.orange,
        ),
      );
    }
  }

  Future<void> _signOut() async {
    try {
      final currentUser = _firebaseAuth.currentUser;

      // Update online status to false before signing out
      if (currentUser != null) {
        try {
          // Try using an RPC function to avoid recursion issues
          try {
            await _supabase.rpc(
              'update_online_status',
              params: {
                'uid': currentUser.uid,
                'is_online_param': false,
              },
            );
          } catch (rpcError) {
            print('RPC error: $rpcError');

            // Fallback to direct update
            await _supabase
                .from('user_profiles')
                .update({
              'is_online': false,
              'last_active_at': DateTime.now().toIso8601String(),
            })
                .eq('user_id', currentUser.uid);
          }

          print('Updated online status to false');
        } catch (updateError) {
          print('Error updating online status: $updateError');
          // Continue with sign out even if update fails
        }
      }

      // Sign out from Firebase
      await _firebaseAuth.signOut();

      if (!mounted) return;

      // Navigate to sign in screen
      Navigator.pushNamedAndRemoveUntil(context, '/signin', (route) => false);

    } catch (e) {
      print('Error signing out: $e');

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to sign out: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  @override
  void dispose() {
    _fullNameController.dispose();
    _emailController.dispose();
    _idNumberController.dispose();
    _departmentController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('My Profile'),
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
        elevation: 0,
        actions: [
          if (!_isLoading && !_isEditing)
            IconButton(
              icon: const Icon(Icons.edit),
              onPressed: () {
                setState(() {
                  _isEditing = true;
                });
              },
            )
          else if (!_isLoading && _isEditing)
            IconButton(
              icon: const Icon(Icons.cancel),
              onPressed: () {
                setState(() {
                  _isEditing = false;
                  // Reset to original data
                  _fullNameController.text = _userData?['full_name'] ?? '';
                  _idNumberController.text = _userData?['id_number'] ?? '';
                  _departmentController.text = _userData?['department'] ?? '';
                });
              },
            ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _errorMessage != null && _userData == null
          ? Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.error_outline, size: 48, color: Colors.red),
            const SizedBox(height: 16),
            Text(
              'Error loading profile',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Text(_errorMessage ?? 'Unknown error'),
            const SizedBox(height: 24),
            ElevatedButton(
              onPressed: _fetchUserData,
              child: const Text('Retry'),
            ),
          ],
        ),
      )
          : SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Profile header with avatar
              Center(
                child: Column(
                  children: [
                    CircleAvatar(
                      radius: 50,
                      backgroundColor: AppColors.primary,
                      child: Text(
                        _userData?['full_name'] != null && (_userData?['full_name'] as String).isNotEmpty
                            ? (_userData?['full_name'] as String).substring(0, 1).toUpperCase()
                            : '?',
                        style: const TextStyle(
                          fontSize: 40,
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      _userData?['full_name'] ?? 'No Name',
                      style: const TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                        color: AppColors.textPrimary,
                      ),
                    ),
                    Text(
                      _emailController.text,
                      style: const TextStyle(
                        fontSize: 16,
                        color: AppColors.textSecondary,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Chip(
                          label: Text(
                            (_userData?['user_type'] ?? 'student').toUpperCase(),
                            style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          backgroundColor: AppColors.primary,
                        ),
                        const SizedBox(width: 8),
                        if (_isAnonymous)
                          Chip(
                            label: const Text(
                              'ANONYMOUS',
                              style: TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            backgroundColor: Colors.grey[700],
                          ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 32),

              // Anonymous mode toggle
              SwitchListTile(
                title: const Text(
                  'Anonymous Mode',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                  ),
                ),
                subtitle: const Text(
                  'Hide your identity when chatting with counselors',
                  style: TextStyle(
                    fontSize: 14,
                    color: AppColors.textSecondary,
                  ),
                ),
                value: _isAnonymous,
                onChanged: _isUpdating
                    ? null
                    : (bool value) {
                  _toggleAnonymousMode();
                },
                activeColor: AppColors.primary,
              ),
              const Divider(),
              const SizedBox(height: 16),

              // Profile information
              const Text(
                'Personal Information',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: AppColors.textPrimary,
                ),
              ),
              const SizedBox(height: 16),

              // Full Name
              TextFormField(
                controller: _fullNameController,
                decoration: InputDecoration(
                  labelText: 'Full Name',
                  prefixIcon: const Icon(Icons.person_outline),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: const BorderSide(color: AppColors.divider),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: const BorderSide(color: AppColors.primary, width: 2),
                  ),
                ),
                enabled: _isEditing,
                validator: (value) {
                  if (value == null || value.isEmpty) {
                    return 'Please enter your full name';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 16),

              // Email
              TextFormField(
                controller: _emailController,
                decoration: InputDecoration(
                  labelText: 'Email',
                  prefixIcon: const Icon(Icons.email_outlined),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: const BorderSide(color: AppColors.divider),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: const BorderSide(color: AppColors.primary, width: 2),
                  ),
                ),
                enabled: false, // Email cannot be edited
              ),
              const SizedBox(height: 16),

              // ID Number
              TextFormField(
                controller: _idNumberController,
                decoration: InputDecoration(
                  labelText: 'ID Number',
                  prefixIcon: const Icon(Icons.badge_outlined),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: const BorderSide(color: AppColors.divider),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: const BorderSide(color: AppColors.primary, width: 2),
                  ),
                ),
                enabled: _isEditing,
              ),
              const SizedBox(height: 16),

              // Department
              TextFormField(
                controller: _departmentController,
                decoration: InputDecoration(
                  labelText: 'Department',
                  prefixIcon: const Icon(Icons.business_outlined),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: const BorderSide(color: AppColors.divider),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: const BorderSide(color: AppColors.primary, width: 2),
                  ),
                ),
                enabled: _isEditing,
              ),
              const SizedBox(height: 24),

              // Update button
              if (_isEditing)
                SizedBox(
                  width: double.infinity,
                  height: 56,
                  child: ElevatedButton(
                    onPressed: _isUpdating ? null : _updateProfile,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.primary,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      elevation: 0,
                    ),
                    child: _isUpdating
                        ? const CircularProgressIndicator(color: Colors.white)
                        : const Text(
                      'Update Profile',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ),

              const SizedBox(height: 16),

              // Sign out button
              SizedBox(
                width: double.infinity,
                height: 56,
                child: OutlinedButton(
                  onPressed: _signOut,
                  style: OutlinedButton.styleFrom(
                    side: BorderSide(color: Colors.red[700]!),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: Text(
                    'Sign Out',
                    style: TextStyle(
                      fontSize: 16,
                      color: Colors.red[700],
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}