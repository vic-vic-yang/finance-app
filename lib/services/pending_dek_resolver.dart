import 'dart:async';

import '../crypto/key_chain.dart';
import 'api_service.dart';

/// 端到端加密的"机会式"DEK 协助器。
///
/// 两个方向：
///   1. resolveAll / resolveOne：当前用户给"其他还在 pending 的成员"包装 DEK
///   2. rehydrate：当前用户自己还没拿到某账本的 DEK，看看是不是已经被别人 wrap 好了
///
/// 全部 fire-and-forget，任何环节失败都静默忽略 —— 下次再试。
class PendingDekResolver {
  PendingDekResolver._();

  // 防止短时间被多个时机重复 fire（如 App 启动同时进账本页）
  static DateTime? _lastResolveAt;
  static DateTime? _lastRehydrateAt;
  static const _coolDown = Duration(seconds: 5);

  /// 扫所有自己持有 DEK 的账本，把里面 pending 的新成员 wrap 一遍
  /// 返回成功 wrap 的人数（debug 用）
  static Future<int> resolveAll() async {
    // 冷却：5 秒内只跑一次
    final now = DateTime.now();
    if (_lastResolveAt != null &&
        now.difference(_lastResolveAt!) < _coolDown) {
      return 0;
    }
    _lastResolveAt = now;

    if (!KeyChain.instance.hasKey) return 0;
    try {
      final res = await ApiService.getLedgers();
      final ledgers = (res['ledgers'] as List?) ?? [];
      var wrapped = 0;
      for (final l in ledgers) {
        final lid = l['id'] as String?;
        if (lid == null) continue;
        if (!KeyChain.instance.hasDek(lid)) continue; // 自己都没拿到，跳过
        try {
          wrapped += await resolveOne(lid);
        } catch (_) {
          // 单账本失败不阻塞其他
        }
      }
      return wrapped;
    } catch (_) {
      return 0;
    }
  }

  /// 给某一个账本的 pending 成员补 DEK
  static Future<int> resolveOne(String ledgerId) async {
    if (!KeyChain.instance.hasKey) return 0;
    if (!KeyChain.instance.hasDek(ledgerId)) return 0;
    try {
      final r = await ApiService.getPendingMembers(ledgerId);
      final pending = (r['pending'] as List?) ?? [];
      if (pending.isEmpty) return 0;
      final dek = KeyChain.instance.dekOf(ledgerId)!;
      // myDekVersion 由服务端返回（避免新旧版本错位）
      final ver = (r['myDekVersion'] as num?)?.toInt() ??
          KeyChain.instance.dekVersionOf(ledgerId) ??
          1;
      var done = 0;
      for (final m in pending) {
        final userId = m['userId'] as String?;
        final pubKey = m['sm2PubKey'] as String?;
        if (userId == null || pubKey == null || pubKey.isEmpty) continue;
        try {
          final wrappedB64 = KeyChain.instance.wrapDekFor(dek, pubKey);
          await ApiService.attachDek(
            ledgerId,
            userId,
            dekWrapped: wrappedB64,
            dekVersion: ver,
          );
          done++;
        } catch (_) {
          // 单个成员失败：跳过下一个
        }
      }
      return done;
    } catch (_) {
      return 0;
    }
  }

  /// "我"自己还在 pending — 拉一次 keys/mine，看看是不是别人已经帮我 wrap 好了
  /// 调用场景：进账本页发现 hasDek=false，下拉刷新等
  /// [requireLedgerId] 不为空时，只在那个账本"现在还没 DEK"才会去拉
  static Future<bool> rehydrate({String? requireLedgerId}) async {
    if (!KeyChain.instance.hasKey) return false;
    if (requireLedgerId != null &&
        KeyChain.instance.hasDek(requireLedgerId)) {
      return true; // 已经有了，不浪费请求
    }
    // 冷却：5 秒内只拉一次
    final now = DateTime.now();
    if (_lastRehydrateAt != null &&
        now.difference(_lastRehydrateAt!) < _coolDown) {
      return KeyChain.instance.hasDek(requireLedgerId ?? '');
    }
    _lastRehydrateAt = now;

    try {
      final res = await ApiService.getMyDeks();
      final list = (res['deks'] as List?) ?? [];
      for (final d in list) {
        final lid = d['ledgerId'] as String?;
        final wrapped = d['dekWrapped'] as String?;
        final ver = (d['dekVersion'] as num?)?.toInt() ?? 1;
        if (lid == null || wrapped == null) continue;
        if (KeyChain.instance.hasDek(lid)) continue; // 已经有了，跳过
        try {
          KeyChain.instance.loadDek(
            ledgerId: lid,
            dekWrappedBase64: wrapped,
            dekVersion: ver,
          );
        } catch (_) {
          // 解不开：私钥不匹配？跳过
        }
      }
      return requireLedgerId == null
          ? true
          : KeyChain.instance.hasDek(requireLedgerId);
    } catch (_) {
      return false;
    }
  }

  /// 清掉冷却（登出 / 切账号时调）
  static void resetCooldown() {
    _lastResolveAt = null;
    _lastRehydrateAt = null;
  }
}
