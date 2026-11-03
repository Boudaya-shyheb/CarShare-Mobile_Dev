class UserProfile {
  const UserProfile({
    required this.id,
    required this.fullName,
    required this.phone,
    required this.email,
    required this.role,
    required this.createdAt,
  });

  final String id;
  final String fullName;
  final String phone;
  final String email;
  final String role;
  final DateTime createdAt;

  factory UserProfile.fromJson(Map<String, dynamic> json) => UserProfile(
    id: json['id'] as String,
    fullName: json['fullName'] as String,
    phone: json['phone'] as String,
    email: json['email'] as String,
    role: json['role'] as String,
    createdAt: DateTime.parse(json['createdAt'] as String),
  );

  factory UserProfile.fromMap(Map<String, Object?> map) => UserProfile(
    id: map['id']! as String,
    fullName: map['full_name']! as String,
    phone: map['phone']! as String,
    email: map['email']! as String,
    role: map['role']! as String,
    createdAt: DateTime.parse(map['created_at']! as String),
  );

  Map<String, Object?> toMap() => {
    'id': id,
    'full_name': fullName,
    'phone': phone,
    'email': email,
    'role': role,
    'created_at': createdAt.toIso8601String(),
  };
}
