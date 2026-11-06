class UserProfile {
  const UserProfile({
    required this.id,
    required this.fullName,
    required this.phone,
    required this.email,
    required this.role,
    required this.createdAt,
    this.status = 'ACTIVE',
    this.statusUntil,
    this.hasProfilePhoto = false,
  });

  final String id;
  final String fullName;
  final String phone;
  final String email;
  final String role;
  final DateTime createdAt;
  final String status;
  final DateTime? statusUntil;
  final bool hasProfilePhoto;

  factory UserProfile.fromJson(Map<String, dynamic> json) => UserProfile(
    id: json['id'] as String,
    fullName: json['fullName'] as String,
    phone: json['phone'] as String,
    email: json['email'] as String,
    role: json['role'] as String,
    createdAt: DateTime.parse(json['createdAt'] as String),
    status: json['status'] as String? ?? 'ACTIVE',
    statusUntil: json['statusUntil'] == null
        ? null
        : DateTime.parse(json['statusUntil'] as String),
    hasProfilePhoto: json['hasProfilePhoto'] as bool? ?? false,
  );

  factory UserProfile.fromMap(Map<String, Object?> map) => UserProfile(
    id: map['id']! as String,
    fullName: map['full_name']! as String,
    phone: map['phone']! as String,
    email: map['email']! as String,
    role: map['role']! as String,
    createdAt: DateTime.parse(map['created_at']! as String),
    status: map['status'] as String? ?? 'ACTIVE',
    statusUntil: map['status_until'] == null
        ? null
        : DateTime.parse(map['status_until']! as String),
    hasProfilePhoto: (map['has_profile_photo'] as int? ?? 0) == 1,
  );

  Map<String, Object?> toMap() => {
    'id': id,
    'full_name': fullName,
    'phone': phone,
    'email': email,
    'role': role,
    'created_at': createdAt.toIso8601String(),
    'status': status,
    'status_until': statusUntil?.toIso8601String(),
    'has_profile_photo': hasProfilePhoto ? 1 : 0,
  };
}
