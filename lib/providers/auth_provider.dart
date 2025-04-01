import 'package:firebase_auth/firebase_auth.dart' as firebase;
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

enum AuthStatus {
  initial,
  loading,
  authenticated,
  unauthenticated,
}

class AuthResult {
  final bool success;
  final String message;

  AuthResult({required this.success, required this.message});
}

class UserProfile {
  final String userId;
  final String fullName;
  final String userType;
  final String? idNumber;
  final String? department;
  final String? avatarUrl;

  UserProfile({
    required this.userId,
    required this.fullName,
    required this.userType,
    this.idNumber,
    this.department,
    this.avatarUrl,
  });

  factory UserProfile.fromJson(Map<String, dynamic> json) {
    return UserProfile(
      userId: json['user_id'] ?? '',
      fullName: json['full_name'] ?? '',
      userType: json['user_type'] ?? '',
      idNumber: json['id_number'],
      department: json['department'],
      avatarUrl: json['avatar_url'],
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'user_id': userId,
      'full_name': fullName,
      'user_type': userType,
      'id_number': idNumber,
      'department': department,
      'avatar_url': avatarUrl,
    };
  }
}

class UserAuthProvider with ChangeNotifier {
  final firebase.FirebaseAuth _firebaseAuth = firebase.FirebaseAuth.instance;
  final SupabaseClient _supabase = Supabase.instance.client;

  AuthStatus _status = AuthStatus.initial;
  UserProfile? _userProfile;
  String? _errorMessage;

  AuthStatus get status => _status;
  UserProfile? get userProfile => _userProfile;
  String? get errorMessage => _errorMessage;
  bool get isLoading => _status == AuthStatus.loading;

  UserAuthProvider() {
    // Initialize by checking if user is already logged in
    _firebaseAuth.authStateChanges().listen((firebase.User? user) async {
      if (user != null) {
        await fetchUserProfile();
        _status = AuthStatus.authenticated;
      } else {
        _status = AuthStatus.unauthenticated;
        _userProfile = null;
      }
      notifyListeners();
    });
  }

  Future<bool> signIn(String email, String password) async {
    try {
      _status = AuthStatus.loading;
      _errorMessage = null;
      notifyListeners();

      // Sign in with Firebase
      final userCredential = await _firebaseAuth.signInWithEmailAndPassword(
        email: email,
        password: password,
      );

      if (userCredential.user != null) {
        // Fetch user profile from Supabase
        await fetchUserProfile();

        // Check if user_type was retrieved
        if (_userProfile == null || _userProfile!.userType.isEmpty) {
          print('Warning: User profile or user_type is empty');
        }

        _status = AuthStatus.authenticated;
        notifyListeners();
        return true;
      } else {
        _status = AuthStatus.unauthenticated;
        _errorMessage = 'Failed to sign in';
        notifyListeners();
        return false;
      }
    } catch (e) {
      _status = AuthStatus.unauthenticated;
      _errorMessage = e.toString();
      notifyListeners();
      print('Sign in error: $e');
      return false;
    }
  }

  Future<bool> signUp({
    required String email,
    required String password,
    required String fullName,
    required String userType,
    String? idNumber,
    String? department,
  }) async {
    try {
      _status = AuthStatus.loading;
      _errorMessage = null;
      notifyListeners();

      // Create user in Firebase
      final userCredential = await _firebaseAuth.createUserWithEmailAndPassword(
        email: email,
        password: password,
      );

      if (userCredential.user != null) {
        // Create user profile in Supabase
        final userId = userCredential.user!.uid;

        await _supabase.from('user_profiles').insert({
          'user_id': userId,
          'full_name': fullName,
          'user_type': userType.toLowerCase(),
          'id_number': idNumber,
          'department': department,
          'created_at': DateTime.now().toIso8601String(),
        });

        // Fetch the newly created profile
        await fetchUserProfile();

        _status = AuthStatus.authenticated;
        notifyListeners();
        return true;
      } else {
        _status = AuthStatus.unauthenticated;
        _errorMessage = 'Failed to create account';
        notifyListeners();
        return false;
      }
    } catch (e) {
      _status = AuthStatus.unauthenticated;
      _errorMessage = e.toString();
      notifyListeners();
      print('Sign up error: $e');
      return false;
    }
  }

  Future<void> fetchUserProfile() async {
    try {
      final user = _firebaseAuth.currentUser;
      if (user != null) {
        // Get the user profile from Supabase
        final response = await _supabase
            .from('user_profiles')
            .select('*')
            .eq('user_id', user.uid)
            .single();

        if (response != null) {
          _userProfile = UserProfile.fromJson(response);

          // Debug print to verify the user_type is being retrieved
          print('Fetched user profile: ${_userProfile?.toJson()}');
          print('User type: ${_userProfile?.userType}');

          notifyListeners();
        } else {
          print('No user profile found for user ID: ${user.uid}');
          _errorMessage = 'User profile not found';
        }
      }
    } catch (e) {
      print('Error fetching user profile: $e');
      _errorMessage = 'Error fetching user profile: $e';
    }
  }

  Future<bool> signOut() async {
    try {
      await _firebaseAuth.signOut();
      _status = AuthStatus.unauthenticated;
      _userProfile = null;
      notifyListeners();
      return true;
    } catch (e) {
      _errorMessage = e.toString();
      notifyListeners();
      return false;
    }
  }

  Future<bool> resetPassword(String email) async {
    try {
      _status = AuthStatus.loading;
      _errorMessage = null;
      notifyListeners();

      await _firebaseAuth.sendPasswordResetEmail(email: email);

      _status = AuthStatus.unauthenticated;
      notifyListeners();
      return true;
    } catch (e) {
      _status = AuthStatus.unauthenticated;
      _errorMessage = e.toString();
      notifyListeners();
      return false;
    }
  }
}