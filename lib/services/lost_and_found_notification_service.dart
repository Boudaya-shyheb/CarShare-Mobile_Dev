import '../models/lost_and_found_notification.dart';
import 'api_client.dart';

/// The caller's Lost & Found notifications, read through the shared [ApiClient].
class LostAndFoundNotificationService {
  LostAndFoundNotificationService._();
  static final instance = LostAndFoundNotificationService._();

  final ApiClient _api = ApiClient.instance;

  Future<List<LostAndFoundNotification>> list() async =>
      (await _api.getList('/lost-and-found/notifications'))
          .map(LostAndFoundNotification.fromJson)
          .toList(growable: false);

  Future<int> unreadCount() async {
    final row = await _api.get('/lost-and-found/notifications/unread-count');
    return (row['count'] as num?)?.toInt() ?? 0;
  }

  Future<void> markRead(String id) async {
    await _api.post('/lost-and-found/notifications/$id/read', const {});
  }

  Future<void> markAllRead() async {
    await _api.post('/lost-and-found/notifications/read-all', const {});
  }
}
