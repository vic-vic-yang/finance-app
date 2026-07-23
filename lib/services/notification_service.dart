import 'api_service.dart';

/// 通知中心 API（/api/notifications/*）。
///
/// 现为 [ApiService] 的薄封装：真正的请求实现在 `ApiService.getNotifications`
/// 等方法里（统一长连接 Client / 超时 / 错误处理），这里保留稳定的方法名，
/// 供通知中心页、首页角标、本地推送桥接等调用方使用。
class NotificationService {
  /// 通知列表：分页，未读在前。返回 { items, total, page, pageSize, hasMore }
  static Future<Map<String, dynamic>> list({
    int page = 1,
    int pageSize = 20,
  }) =>
      ApiService.getNotifications(page: page, pageSize: pageSize);

  /// 未读数。返回 { count }
  static Future<Map<String, dynamic>> unreadCount() =>
      ApiService.getNotificationUnreadCount();

  /// 标记单条已读（幂等）
  static Future<void> markRead(String id) =>
      ApiService.markNotificationRead(id);

  /// 全部标记已读
  static Future<void> markAllRead() => ApiService.markAllNotificationsRead();
}
