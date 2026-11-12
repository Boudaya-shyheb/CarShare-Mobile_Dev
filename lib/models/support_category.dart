class SupportCategory {
  const SupportCategory({
    required this.id,
    required this.name,
    required this.severity,
    required this.priority,
    required this.responseDelayHours,
    required this.verificationType,
  });

  final String id;
  final String name;
  final int severity;
  final String priority;
  final int responseDelayHours;
  final String verificationType;

  factory SupportCategory.fromJson(Map<String, dynamic> json) =>
      SupportCategory(
        id: json['id'] as String? ?? '',
        name: json['name'] as String? ?? 'Support request',
        severity: json['severity'] as int? ?? 1,
        priority: json['priority'] as String? ?? 'NORMAL',
        responseDelayHours: json['responseDelayHours'] as int? ?? 72,
        verificationType: json['verificationType'] as String? ?? 'MANUAL',
      );
}
