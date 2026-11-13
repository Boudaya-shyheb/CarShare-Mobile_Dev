/// One in-app Lost & Found notification (`GET /lost-and-found/notifications`).
///
/// [reportId] is the notified person's own report, so tapping the notification can open it.
class LostAndFoundNotification {
  const LostAndFoundNotification({
    required this.id,
    required this.type,
    required this.title,
    required this.body,
    required this.read,
    required this.createdAt,
    this.reportId,
    this.handoverId,
  });

  final String id;

  /// MATCH_FOUND, MATCH_CONFIRMED, MEETING_ARRANGED, ITEM_RETURNED or NOT_MY_ITEM.
  final String type;
  final String title;
  final String body;
  final bool read;
  final DateTime createdAt;
  final String? reportId;
  final String? handoverId;

  factory LostAndFoundNotification.fromJson(Map<String, dynamic> json) =>
      LostAndFoundNotification(
        id: json['id'] as String,
        type: json['type'] as String,
        title: json['title'] as String? ?? '',
        body: json['body'] as String? ?? '',
        read: json['read'] as bool? ?? false,
        createdAt: DateTime.parse(json['createdAt'] as String),
        reportId: json['reportId'] as String?,
        handoverId: json['handoverId'] as String?,
      );

  Map<String, dynamic> toJson() => {
    'id': id,
    'type': type,
    'title': title,
    'body': body,
    'read': read,
    'createdAt': createdAt.toUtc().toIso8601String(),
    'reportId': reportId,
    'handoverId': handoverId,
  };
}
