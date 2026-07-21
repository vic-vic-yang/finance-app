import 'dart:async';
import 'dart:convert';
import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'auth_service.dart';
import 'notification_parser.dart';

/// ======================================================================
/// 端侧自动记账服务
/// ======================================================================
///
/// 链路：原生 NotificationListenerService → EventChannel → 本机解析
/// （[NotificationParser]，规则模板覆盖微信 / 支付宝 / 云闪付 / 主流银行）
/// → fingerprint 去重 → SharedPreferences 待确认队列（按 userId 隔离）。
/// 全程本地处理，通知原文不出设备；用户确认后才调 ApiService 入账。
///
/// 使用：
///   - App 启动 / 进入自动记账页时 `AutoBookkeepingService.instance.start()`
///   - UI 订阅 [draftsVersion] 感知队列变化后 `loadQueue()` 重取
class AutoBookkeepingService {
  AutoBookkeepingService._();
  static final AutoBookkeepingService instance = AutoBookkeepingService._();

  /// 与 MainActivity / AutoBookkeepingListenerService 保持一致
  static const _method = MethodChannel('siku/auto_bookkeeping');
  static const _events = EventChannel('siku/auto_bookkeeping/events');

  /// 待确认队列上限（防爆量）
  static const _maxQueue = 100;

  /// 已见指纹环形记录上限（防止同一笔通知反复入队）
  static const _maxSeen = 500;

  StreamSubscription<dynamic>? _sub;
  bool _listening = false;

  /// 队列变化计数器：UI 监听后重取队列（轻量，不携带数据）
  final ValueNotifier<int> draftsVersion = ValueNotifier(0);

  bool get _supported => !kIsWeb && Platform.isAndroid;

  // ── 权限 ───────────────────────────────────────────────────

  /// 系统「通知使用权」是否已授予本应用
  Future<bool> isListenerEnabled() async {
    if (!_supported) return false;
    try {
      return await _method.invokeMethod<bool>('isListenerEnabled') ?? false;
    } catch (_) {
      return false;
    }
  }

  /// 跳系统「通知使用权」设置页（用户手动授权，无法代码代开）
  Future<bool> openListenerSettings() async {
    if (!_supported) return false;
    try {
      return await _method.invokeMethod<bool>('openListenerSettings') ?? false;
    } catch (_) {
      return false;
    }
  }

  // ── 事件监听 ───────────────────────────────────────────────

  /// 开始接收原生通知事件（幂等，可重复调用）
  void start() {
    if (_listening || !_supported) return;
    _listening = true;
    _sub = _events.receiveBroadcastStream().listen(
      _onEvent,
      onError: (_) {/* 原生侧异常静默，不影响其他功能 */},
    );
  }

  Future<void> stop() async {
    await _sub?.cancel();
    _sub = null;
    _listening = false;
  }

  Future<void> _onEvent(dynamic event) async {
    if (event is! Map) return;
    final packageName = event['packageName'] as String? ?? '';
    final title = event['title'] as String? ?? '';
    final text = event['text'] as String? ?? '';
    final postTimeMs = (event['postTime'] as num?)?.toInt() ?? 0;
    final postTime = postTimeMs > 0
        ? DateTime.fromMillisecondsSinceEpoch(postTimeMs)
        : DateTime.now();

    final draft = NotificationParser.parse(
      packageName: packageName,
      title: title,
      text: text,
      postTime: postTime,
    );
    if (draft == null) return; // 解析不出 = 非账单通知，丢弃
    await _enqueue(draft);
  }

  // ── 待确认队列（SharedPreferences，json，key 带 userId 隔离）────────

  Future<String?> _uid() async {
    final user = await AuthService.getUser();
    return user?['id'] as String?;
  }

  static String _queueKey(String uid) => 'auto_bill_queue_$uid';
  static String _seenKey(String uid) => 'auto_bill_seen_$uid';

  /// 读取当前用户的待确认草稿队列（新的在前）
  Future<List<ParsedBillDraft>> loadQueue() async {
    final uid = await _uid();
    if (uid == null) return [];
    final prefs = await SharedPreferences.getInstance();
    return ParsedBillDraft.decodeList(prefs.getString(_queueKey(uid)));
  }

  Future<void> _enqueue(ParsedBillDraft draft) async {
    final uid = await _uid();
    if (uid == null) return; // 未登录不入队
    final prefs = await SharedPreferences.getInstance();

    final seen = prefs.getStringList(_seenKey(uid)) ?? [];
    final queue = await loadQueue();
    if (seen.contains(draft.fingerprint) ||
        queue.any((d) => d.fingerprint == draft.fingerprint)) {
      return; // 同一笔交易的重复推送 / 已处理过
    }

    queue.insert(0, draft);
    if (queue.length > _maxQueue) queue.removeRange(_maxQueue, queue.length);
    seen.add(draft.fingerprint);
    if (seen.length > _maxSeen) seen.removeRange(0, seen.length - _maxSeen);

    await prefs.setString(
        _queueKey(uid), jsonEncode(queue.map((e) => e.toJson()).toList()));
    await prefs.setStringList(_seenKey(uid), seen);
    draftsVersion.value++;
  }

  /// 把一条草稿移出队列（确认入账 / 忽略都走这里）。
  /// 指纹留在 seen 里，防止同笔通知再次入队。
  Future<void> removeDraft(String fingerprint) async {
    final uid = await _uid();
    if (uid == null) return;
    final prefs = await SharedPreferences.getInstance();
    final queue = await loadQueue();
    final next = queue.where((d) => d.fingerprint != fingerprint).toList();
    if (next.length == queue.length) return;
    await prefs.setString(
        _queueKey(uid), jsonEncode(next.map((e) => e.toJson()).toList()));
    draftsVersion.value++;
  }

  /// 清空当前用户的待确认队列（seen 保留，防回放）
  Future<void> clearQueue() async {
    final uid = await _uid();
    if (uid == null) return;
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_queueKey(uid));
    draftsVersion.value++;
  }
}
