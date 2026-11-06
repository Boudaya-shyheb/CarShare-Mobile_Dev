class UserSanction {
  const UserSanction({
    required this.id,
    required this.points,
    required this.reason,
    required this.issuedAt,
    required this.expiresAt,
    required this.active,
  });

  final String id;
  final int points;
  final String reason;
  final DateTime issuedAt;
  final DateTime expiresAt;
  final bool active;

  factory UserSanction.fromJson(Map<String, dynamic> json) => UserSanction(
    id: json['id'] as String,
    points: json['points'] as int,
    reason: json['reason'] as String,
    issuedAt: DateTime.parse(json['issuedAt'] as String),
    expiresAt: DateTime.parse(json['expiresAt'] as String),
    active: json['active'] as bool,
  );
}
