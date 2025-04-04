import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:fluttertoast/fluttertoast.dart';
import 'package:firebase_auth/firebase_auth.dart' as firebase;
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../utils/app_colors.dart';
import 'sign_up_screen.dart';
import 'forgot_password_screen.dart';

class SignInScreen extends StatefulWidget {
  const SignInScreen({Key? key}) : super(key: key);

  @override
  State<SignInScreen> createState() => _SignInScreenState();
}

class _SignInScreenState extends State<SignInScreen> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();

  String _selectedUserType = 'Student';
  bool _isPasswordVisible = false;
  bool _rememberMe = false;
  bool _isLoading = false;
  String? _errorMessage;

  final firebase.FirebaseAuth _firebaseAuth = firebase.FirebaseAuth.instance;
  final SupabaseClient _supabase = Supabase.instance.client;

  @override
  void initState() {
    super.initState();
    _loadSavedCredentials();
  }

  Future<void> _loadSavedCredentials() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final savedEmail = prefs.getString('saved_email');
      final rememberMe = prefs.getBool('remember_me') ?? false;

      if (savedEmail != null && rememberMe) {
        setState(() {
          _emailController.text = savedEmail;
          _rememberMe = true;
        });
      }
    } catch (e) {
      print('Error loading saved credentials: $e');
    }
  }

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _signIn() async {
    if (_formKey.currentState!.validate()) {
      // Save or clear credentials based on "Remember Me" checkbox
      try {
        final prefs = await SharedPreferences.getInstance();
        if (_rememberMe) {
          await prefs.setString('saved_email', _emailController.text.trim());
          await prefs.setBool('remember_me', true);
        } else {
          await prefs.remove('saved_email');
          await prefs.setBool('remember_me', false);
        }
      } catch (e) {
        print('Error managing saved credentials: $e');
      }
      setState(() {
        _isLoading = true;
        _errorMessage = null;
      });

      try {
        // Sign in with Firebase
        final userCredential = await _firebaseAuth.signInWithEmailAndPassword(
          email: _emailController.text.trim(),
          password: _passwordController.text,
        );

        if (userCredential.user != null) {
          final userId = userCredential.user!.uid;

          // Fetch user profile from Supabase
          try {
            // Try multiple approaches to fetch user profile
            Map<String, dynamic>? userProfile;
            String? userType;

            // Approach 1: Try RPC function
            try {
              final rpcData = await _supabase.rpc(
                'get_user_profile',
                params: {'user_id_param': userId},
              );

              if (rpcData != null && rpcData.isNotEmpty) {
                userProfile = rpcData[0];
                userType = userProfile?['user_type']?.toString().toLowerCase();
              }
            } catch (rpcError) {
              print('RPC error: $rpcError');
              // Continue to next approach
            }

            // Approach 2: Try direct query
            if (userType == null) {
              final data = await _supabase
                  .from('user_profiles')
                  .select('user_type, full_name')
                  .eq('user_id', userId)
                  .limit(1)
                  .maybeSingle();

              if (data != null) {
                userProfile = data;
                userType = userProfile?['user_type']?.toString().toLowerCase();
              }
            }

            // Approach 3: Try raw SQL query through RPC
            if (userType == null) {
              try {
                final rawData = await _supabase.rpc(
                  'get_user_type_by_id',
                  params: {'uid': userId},
                );

                if (rawData != null) {
                  userType = rawData.toString().toLowerCase();
                }
              } catch (rawError) {
                print('Raw query error: $rawError');
              }
            }

            // Save credentials if "Remember Me" is checked
            if (_rememberMe) {
              try {
                final prefs = await SharedPreferences.getInstance();
                await prefs.setString('saved_email', _emailController.text.trim());
                await prefs.setBool('remember_me', true);
              } catch (e) {
                print('Error saving credentials: $e');
              }
            } else {
              // Clear saved credentials if "Remember Me" is unchecked
              try {
                final prefs = await SharedPreferences.getInstance();
                await prefs.remove('saved_email');
                await prefs.setBool('remember_me', false);
              } catch (e) {
                print('Error clearing credentials: $e');
              }
            }

            // Navigate based on user type
            if (mounted) {
              if (userType == 'student') {
                print('Navigating to student home screen');
                Navigator.pushReplacementNamed(context, '/student_home');
              } else if (userType == 'counselor') {
                print('Navigating to counselor home screen');
                Navigator.pushReplacementNamed(context, '/counselor_home');
              } else if (userType == 'admin') {
                print('Navigating to admin home screen');
                Navigator.pushReplacementNamed(context, '/admin_home');
              } else {
                // Unknown or null user type, use selected user type as fallback
                print('Using selected user type as fallback: $_selectedUserType');

                if (_selectedUserType.toLowerCase() == 'student') {
                  Navigator.pushReplacementNamed(context, '/student_home');
                } else if (_selectedUserType.toLowerCase() == 'counselor') {
                  Navigator.pushReplacementNamed(context, '/counselor_home');
                } else if (_selectedUserType.toLowerCase() == 'admin') {
                  Navigator.pushReplacementNamed(context, '/admin_home');
                } else {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('Interface for $_selectedUserType not implemented yet'),
                      backgroundColor: Colors.orange,
                    ),
                  );
                }
              }
            }
          } catch (e) {
            print('Error fetching user profile: $e');
            if (mounted) {
              // Even if we can't fetch the profile, navigate based on the selected user type
              if (_selectedUserType.toLowerCase() == 'student') {
                Navigator.pushReplacementNamed(context, '/student_home');
              } else if (_selectedUserType.toLowerCase() == 'counselor') {
                Navigator.pushReplacementNamed(context, '/counselor_home');
              } else if (_selectedUserType.toLowerCase() == 'admin') {
                Navigator.pushReplacementNamed(context, '/admin_home');
              } else {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text('Error: $e'),
                    backgroundColor: Colors.red,
                  ),
                );
              }
            }
          }
        } else if (mounted) {
          setState(() {
            _errorMessage = 'Failed to sign in';
          });

          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(_errorMessage!),
              backgroundColor: Colors.red,
            ),
          );
        }
      } catch (e) {
        print('Sign in error: $e');
        if (mounted) {
          setState(() {
            _errorMessage = e.toString();
          });

          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(_errorMessage!),
              backgroundColor: Colors.red,
            ),
          );
        }
      } finally {
        if (mounted) {
          setState(() {
            _isLoading = false;
          });
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: const SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: Brightness.dark,
        systemNavigationBarColor: AppColors.primaryDark,
        systemNavigationBarIconBrightness: Brightness.light,
      ),
      child: Scaffold(
        body: SafeArea(
          child: SingleChildScrollView(
            child: Padding(
              padding: const EdgeInsets.all(24.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const SizedBox(height: 40),
                  // Logo and welcome text
                  Center(
                    child: Column(
                      children: [
                        Container(
                          width: 80,
                          height: 80,
                          decoration: BoxDecoration(
                            color: Colors.white,
                            shape: BoxShape.circle,
                            boxShadow: [
                              BoxShadow(
                                color: AppColors.primary.withOpacity(0.2),
                                blurRadius: 10,
                                offset: const Offset(0, 4),
                              ),
                            ],
                          ),
                          child: const Center(
                            child: Text(
                              "ST",
                              style: TextStyle(
                                color: AppColors.primary,
                                fontSize: 32,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 24),
                        const Text(
                          "Welcome Back",
                          style: TextStyle(
                            fontSize: 28,
                            fontWeight: FontWeight.bold,
                            color: AppColors.textPrimary,
                          ),
                        ),
                        const SizedBox(height: 8),
                        const Text(
                          "Sign in to continue",
                          style: TextStyle(
                            fontSize: 16,
                            color: AppColors.textSecondary,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 40),

                  // User type selection
                  const Text(
                    "I am a:",
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w500,
                      color: AppColors.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      _buildUserTypeButton('Student', AppColors.studentColor),
                      const SizedBox(width: 12),
                      _buildUserTypeButton('Counselor', AppColors.counselorColor),
                      const SizedBox(width: 12),
                      _buildUserTypeButton('Admin', AppColors.adminColor),
                    ],
                  ),
                  const SizedBox(height: 32),

                  // Login form
                  Form(
                    key: _formKey,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Email field
                        TextFormField(
                          controller: _emailController,
                          keyboardType: TextInputType.emailAddress,
                          decoration: InputDecoration(
                            labelText: 'Email',
                            hintText: 'Enter your email',
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
                          validator: (value) {
                            if (value == null || value.isEmpty) {
                              return 'Please enter your email';
                            }
                            if (!RegExp(r'^[\w-\.]+@([\w-]+\.)+[\w-]{2,4}$').hasMatch(value)) {
                              return 'Please enter a valid email';
                            }
                            return null;
                          },
                        ),
                        const SizedBox(height: 20),

                        // Password field
                        TextFormField(
                          controller: _passwordController,
                          obscureText: !_isPasswordVisible,
                          decoration: InputDecoration(
                            labelText: 'Password',
                            hintText: 'Enter your password',
                            prefixIcon: const Icon(Icons.lock_outline),
                            suffixIcon: IconButton(
                              icon: Icon(
                                _isPasswordVisible ? Icons.visibility_off : Icons.visibility,
                              ),
                              onPressed: () {
                                setState(() {
                                  _isPasswordVisible = !_isPasswordVisible;
                                });
                              },
                            ),
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
                          validator: (value) {
                            if (value == null || value.isEmpty) {
                              return 'Please enter your password';
                            }
                            if (value.length < 6) {
                              return 'Password must be at least 6 characters';
                            }
                            return null;
                          },
                        ),
                        const SizedBox(height: 16),

                        // Remember me and forgot password
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Row(
                              children: [
                                Checkbox(
                                  value: _rememberMe,
                                  activeColor: AppColors.primary,
                                  onChanged: (value) {
                                    setState(() {
                                      _rememberMe = value ?? false;
                                    });
                                  },
                                ),
                                const Text(
                                  'Remember me',
                                  style: TextStyle(
                                    color: AppColors.textSecondary,
                                  ),
                                ),
                              ],
                            ),
                            TextButton(
                              onPressed: () {
                                Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (context) => const ForgotPasswordScreen(),
                                  ),
                                );
                              },
                              child: const Text(
                                'Forgot Password?',
                                style: TextStyle(
                                  color: AppColors.primary,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 24),

                        // Sign in button
                        SizedBox(
                          width: double.infinity,
                          height: 56,
                          child: ElevatedButton(
                            onPressed: _isLoading ? null : _signIn,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: AppColors.primary,
                              foregroundColor: Colors.white,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                              elevation: 0,
                            ),
                            child: _isLoading
                                ? const CircularProgressIndicator(color: Colors.white)
                                : const Text(
                              'Sign In',
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 24),

                  // Sign up link
                  Center(
                    child: RichText(
                      text: TextSpan(
                        text: "Don't have an account? ",
                        style: const TextStyle(
                          color: AppColors.textSecondary,
                          fontSize: 16,
                        ),
                        children: [
                          TextSpan(
                            text: 'Sign Up',
                            style: const TextStyle(
                              color: AppColors.primary,
                              fontWeight: FontWeight.bold,
                              fontSize: 16,
                            ),
                            recognizer: TapGestureRecognizer()
                              ..onTap = () {
                                Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (context) => SignUpScreen(initialUserType: _selectedUserType),
                                  ),
                                );
                              },
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildUserTypeButton(String userType, Color color) {
    final isSelected = _selectedUserType == userType;

    return Expanded(
      child: GestureDetector(
        onTap: () {
          setState(() {
            _selectedUserType = userType;
          });
        },
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 12),
          decoration: BoxDecoration(
            color: isSelected ? color : Colors.transparent,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: isSelected ? color : AppColors.divider,
              width: isSelected ? 2 : 1,
            ),
          ),
          child: Center(
            child: Text(
              userType,
              style: TextStyle(
                color: isSelected ? Colors.white : AppColors.textPrimary,
                fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

