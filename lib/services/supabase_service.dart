import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter/material.dart';
import '../models/user_model.dart';

class SupabaseService {
  final SupabaseClient _supabase = Supabase.instance.client;

  // User profiles
  Future<Map<String, dynamic>?> getUserProfile(String userId) async {
    try {
      final response = await _supabase
          .from('user_profiles')
          .select()
          .eq('user_id', userId)
          .single();

      return response;
    } catch (e) {
      debugPrint('Error getting user profile: $e');
      return null;
    }
  }

  Future<bool> createUserProfile({
    required String userId,
    required String email,
    required String fullName,
    required String userType,
    String? idNumber,
    String? department,
  }) async {
    try {
      await _supabase.from('user_profiles').insert({
        'user_id': userId,
        'email': email,
        'full_name': fullName,
        'user_type': userType.toLowerCase(),
        'id_number': idNumber,
        'department': department,
        'is_anonymous': false, // Default value
        'is_online': true, // Set as online when creating
        'last_active_at': DateTime.now().toIso8601String(),
        'created_at': DateTime.now().toIso8601String(),
      });

      return true;
    } catch (e) {
      debugPrint('Error creating user profile: $e');
      return false;
    }
  }

  Future<bool> updateUserProfile({
    required String userId,
    String? fullName,
    String? idNumber,
    String? department,
    String? photoUrl,
  }) async {
    try {
      final Map<String, dynamic> updates = {};

      if (fullName != null) updates['full_name'] = fullName;
      if (idNumber != null) updates['id_number'] = idNumber;
      if (department != null) updates['department'] = department;
      if (photoUrl != null) updates['photo_url'] = photoUrl;

      updates['updated_at'] = DateTime.now().toIso8601String();

      await _supabase
          .from('user_profiles')
          .update(updates)
          .eq('user_id', userId);

      return true;
    } catch (e) {
      debugPrint('Error updating user profile: $e');
      return false;
    }
  }

  // Update user online status
  Future<bool> updateUserOnlineStatus(
      String userId,
      bool isOnline,
      DateTime lastActiveAt,
      ) async {
    try {
      await _supabase
          .from('user_profiles')
          .update({
        'is_online': isOnline,
        'last_active_at': lastActiveAt.toIso8601String(),
      })
          .eq('user_id', userId);

      return true;
    } catch (e) {
      debugPrint('Error updating online status: $e');
      return false;
    }
  }

  // Student specific methods
  Future<List<Map<String, dynamic>>> getStudentCourses(String userId) async {
    try {
      final response = await _supabase
          .from('student_courses')
          .select('*, courses(*)')
          .eq('student_id', userId);

      return List<Map<String, dynamic>>.from(response);
    } catch (e) {
      debugPrint('Error getting student courses: $e');
      return [];
    }
  }

  // Counselor specific methods
  Future<List<Map<String, dynamic>>> getCounselorAppointments(String userId) async {
    try {
      final response = await _supabase
          .from('appointments')
          .select('*, user_profiles(*)')
          .eq('counselor_id', userId);

      return List<Map<String, dynamic>>.from(response);
    } catch (e) {
      debugPrint('Error getting counselor appointments: $e');
      return [];
    }
  }

  // Admin specific methods
  Future<List<Map<String, dynamic>>> getAllUsers() async {
    try {
      final response = await _supabase
          .from('user_profiles')
          .select()
          .order('created_at', ascending: false);

      return List<Map<String, dynamic>>.from(response);
    } catch (e) {
      debugPrint('Error getting all users: $e');
      return [];
    }
  }

  // Get all counselors
  Future<List<Map<String, dynamic>>> getAllCounselors() async {
    try {
      final response = await _supabase
          .from('user_profiles')
          .select()
          .eq('user_type', 'counselor');

      return List<Map<String, dynamic>>.from(response);
    } catch (e) {
      debugPrint('Error getting counselors: $e');
      return [];
    }
  }

  // Get online counselors
  Future<List<Map<String, dynamic>>> getOnlineCounselors() async {
    try {
      final response = await _supabase
          .from('user_profiles')
          .select()
          .eq('user_type', 'counselor')
          .eq('is_online', true);

      return List<Map<String, dynamic>>.from(response);
    } catch (e) {
      debugPrint('Error getting online counselors: $e');
      return [];
    }
  }

  // General methods
  Future<bool> deleteRecord(String table, String field, String value) async {
    try {
      await _supabase
          .from(table)
          .delete()
          .eq(field, value);

      return true;
    } catch (e) {
      debugPrint('Error deleting record: $e');
      return false;
    }
  }
}