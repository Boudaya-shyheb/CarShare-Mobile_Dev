class SupportReportTarget {
  const SupportReportTarget({
    required this.userId,
    required this.fullName,
    required this.reservationId,
    required this.role,
  });

  final String userId;
  final String fullName;
  final String reservationId;
  final String role;

  factory SupportReportTarget.fromJson(Map<String, dynamic> json) =>
      SupportReportTarget(
        userId: json['userId'] as String? ?? '',
        fullName: json['fullName'] as String? ?? 'Trip participant',
        reservationId: json['reservationId'] as String? ?? '',
        role: json['role'] as String? ?? 'PASSENGER',
      );
}
