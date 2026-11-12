class SupportNotificationItem {
  const SupportNotificationItem({
    required this.id,
    required this.ticketId,
    required this.ticketReference,
    required this.type,
    required this.title,
    required this.message,
    required this.read,
    this.createdAt,
  });

  final String id;
  final String ticketId;
  final String ticketReference;
  final String type;
  final String title;
  final String message;
  final bool read;
  final DateTime? createdAt;

  factory SupportNotificationItem.fromJson(Map<String, dynamic> json) =>
      SupportNotificationItem(
        id: json['id'] as String? ?? '',
        ticketId: json['ticketId'] as String? ?? '',
        ticketReference: json['ticketReference'] as String? ?? '',
        type: json['type'] as String? ?? 'STATUS_CHANGED',
        title: json['title'] as String? ?? 'Support update',
        message: json['message'] as String? ?? '',
        read: json['read'] as bool? ?? false,
        createdAt: DateTime.tryParse('${json['createdAt']}')?.toLocal(),
      );
}
