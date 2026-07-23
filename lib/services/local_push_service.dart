import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import '../models/app_notification.dart';
import 'auth_service.dart';
import 'notification_center_logic.dart';
import 'notification_service.dart';

/// ======================================================================
/// 本地推送桥接（LocalPushService）
/// ======================================================================
///
/// ⚠️ 诚实边界：这**不是**真正的离线 / 远程推送。
/// 它只在「App 启动」和「App 从后台回到前台（resumed）」时主动拉一次
/// 服务端未读通知，对**新出现**的未读发一条系统本地通知。
/// App 被彻底杀掉后不会收到任何提醒 —— 那需要 FCM / 厂商推送通道
/// （服务端每日 08:17 的 ProactiveScanService 只写通知中心，不推设备），
/// 本期明确不做。
///
/// 去重：已发过（或首次播种时已在）的通知 id 存 SharedPreferences
/// （[SeenIdsStore]），每次检查与当前未读做差集，只推差集。
/// 权限：Android 13+ 运行时请求 POST_NOTIFICATIONS；用户拒绝则
/// 静默跳过本地推送（通知中心页照常可用）。Web 端整体跳过。
class LocalPushService {
  LocalPushService._();
  static final LocalPushService instance = LocalPushService._();

  static const _kChannelId = 'finance_reminders';
  static const _kChannelName = '财务提醒';
  static const _kChannelDesc = 'CFO 预警等通知中心新消息的本地提醒';
  static const _kNotificationId = 9001;

  final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();
  final SeenIdsStore _store = SeenIdsStore();

  bool _initialized = false;
  bool _permissionGranted = true;

  /// 初始化插件 + 请求通知权限（Android 13+）。
  /// [onOpenNotificationCenter]：用户点击系统通知时的回调（打开通知中心）。
  /// 幂等；Web 端直接跳过。
  Future<void> init({void Function()? onOpenNotificationCenter}) async {
    if (kIsWeb || _initialized) return;
    try {
      const settings = InitializationSettings(
        android: AndroidInitializationSettings('@mipmap/ic_launcher'),
        iOS: DarwinInitializationSettings(),
      );
      await _plugin.initialize(
        settings,
        onDidReceiveNotificationResponse: (_) =>
            onOpenNotificationCenter?.call(),
      );
      // Android 13+ 运行时权限；返回 null 说明无需请求（低版本直接可用）
      final granted = await _plugin
          .resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin>()
          ?.requestNotificationsPermission();
      _permissionGranted = granted ?? true;
      _initialized = true;
    } catch (_) {
      // 插件不可用的平台 / 通道异常：静默降级，通知中心照常可用
    }
  }

  /// 拉一次未读通知，对「新的」未读发系统本地通知。返回新通知条数。
  ///
  /// 静默跳过场景：未初始化 / Web / 未登录 / 权限被拒 / 网络失败。
  /// 首次运行只播种已见 id，不发推送（避免存量未读轰炸）。
  Future<int> checkAndNotify() async {
    if (kIsWeb || !_initialized || !_permissionGranted) return 0;
    try {
      final token = await AuthService.getToken();
      if (token == null) return 0;

      final res = await NotificationService.list(page: 1, pageSize: 20);
      final unread = (res['items'] as List? ?? [])
          .map((e) => AppNotification.fromJson(e as Map<String, dynamic>))
          .where((n) => n.isUnread)
          .toList();

      final seen = await _store.load();
      if (seen == null) {
        // 首次运行：只播种，不推送
        await _store.save(mergeSeenIds({}, unread.map((n) => n.id)));
        return 0;
      }

      final fresh = unseenUnread(unread, seen);
      await _store.save(mergeSeenIds(seen, unread.map((n) => n.id)));
      if (fresh.isEmpty) return 0;

      await _show(fresh);
      return fresh.length;
    } catch (_) {
      return 0; // 网络 / 解析失败：下次 resume 再试，不打扰
    }
  }

  Future<void> _show(List<AppNotification> fresh) async {
    const details = NotificationDetails(
      android: AndroidNotificationDetails(
        _kChannelId,
        _kChannelName,
        channelDescription: _kChannelDesc,
        importance: Importance.high,
        priority: Priority.high,
      ),
      iOS: DarwinNotificationDetails(),
    );
    final String title;
    final String body;
    if (fresh.length == 1) {
      title = fresh.first.title.isEmpty ? '司库提醒' : fresh.first.title;
      body = fresh.first.body;
    } else {
      title = '你有 ${fresh.length} 条新的财务提醒';
      body = fresh.first.title;
    }
    await _plugin.show(
      _kNotificationId,
      title,
      body.isEmpty ? null : body,
      details,
      payload: 'open_notifications',
    );
  }
}
