class UserModel {
  final String id;
  final String email;
  final String fullName;
  final String userType;
  final String? department;
  final String? idNumber;
  final String? photoUrl;
  final DateTime createdAt;
  final bool isOnline;
  final DateTime lastActiveAt;
  final bool isAnonymous;

  UserModel({
    required this.id,
    required this.email,
    required this.fullName,
    required this.userType,
    this.department,
    this.idNumber,
    this.photoUrl,
    required this.createdAt,
    this.isOnline = false,
    required this.lastActiveAt,
    this.isAnonymous = false,
  });

  // Create a copy of the user model with updated fields
  UserModel copyWith({
    String? id,
    String? email,
    String? fullName,
    String? userType,
    String? department,
    String? idNumber,
    String? photoUrl,
    DateTime? createdAt,
    bool? isOnline,
    DateTime? lastActiveAt,
    bool? isAnonymous,
  }) {
    return UserModel(
      id: id ?? this.id,
      email: email ?? this.email,
      fullName: fullName ?? this.fullName,
      userType: userType ?? this.userType,
      department: department ?? this.department,
      idNumber: idNumber ?? this.idNumber,
      photoUrl: photoUrl ?? this.photoUrl,
      createdAt: createdAt ?? this.createdAt,
      isOnline: isOnline ?? this.isOnline,
      lastActiveAt: lastActiveAt ?? this.lastActiveAt,
      isAnonymous: isAnonymous ?? this.isAnonymous,
    );
  }

  // Convert UserModel to JSON
  Map<String, dynamic> toJson() {
    return {
      'user_id': id,
      'email': email,
      'full_name': fullName,
      'user_type': userType,
      'department': department,
      'id_number': idNumber,
      'photo_url': photoUrl,
      'created_at': createdAt.toIso8601String(),
      'is_online': isOnline,
      'last_active_at': lastActiveAt.toIso8601String(),
      'is_anonymous': isAnonymous,
    };
  }

  // Create UserModel from JSON
  factory UserModel.fromJson(Map<String, dynamic> json) {
    return UserModel(
      id: json['user_id'],
      email: json['email'],
      fullName: json['full_name'],
      userType: json['user_type'],
      department: json['department'],
      idNumber: json['id_number'],
      photoUrl: json['photo_url'],
      createdAt: json['created_at'] != null
          ? DateTime.parse(json['created_at'])
          : DateTime.now(),
      isOnline: json['is_online'] ?? false,
      lastActiveAt: json['last_active_at'] != null
          ? DateTime.parse(json['last_active_at'])
          : DateTime.now(),
      isAnonymous: json['is_anonymous'] ?? false,
    );
  }
}