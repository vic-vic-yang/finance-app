import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../widgets/feature_discovery_card.dart';
import 'auth_service.dart';

/// ======================================================================
/// 时机式功能发现（Feature Discovery）
/// ======================================================================
///
/// 背景：功能越来越多（CFO / 预测 / 对账 / 周期识别……），入口堆在
/// 「智能管家」里用户不知道何时该用哪个。本服务让每个功能在用户
/// **恰好需要它的瞬间**以一次性轻量卡片出现一次：
///
///   - 每个发现场景一个唯一 key（见下方常量）；
///   - 展示状态持久化到 SharedPreferences，**按账号（userId）隔离**
///     （与 LlmConfigService 同一套 `前缀@userId` 约定），换账号互不影响；
///   - 每个 key 一生只展示一次：无论用户点「去看看」还是「知道了」，
///     展示过的 key 永不再出；
///   - 触发判断由调用方在相关页面数据加载完成后做（不阻塞首屏），
///     本服务只负责「一生一次」的裁决与展示。
///
/// 调试：`reset(key)` / `resetAll()` 可清除当前账号的已展示标记。
class FeatureDiscoveryService {
  FeatureDiscoveryService._();
  static final FeatureDiscoveryService instance = FeatureDiscoveryService._();

  // ── 场景 key ──────────────────────────────────────────────
  /// 首次 AI 导入成功 → 推荐对账中心（余额 / 重复 / 缺腿体检）
  static const kAiImportReconcile = 'ai_import_reconcile';

  /// 连续记账 7 天 → 推荐现金流预测
  static const kStreakForecast = 'streak_forecast';

  /// 近 30 天同一商户 ≥3 笔 → 推荐周期账单识别
  static const kMerchantRecurring = 'merchant_recurring';

  /// 首次创建预算成功 → 告知预算预警会出现在通知中心 / CFO
  static const kFirstBudgetAlert = 'first_budget_alert';

  /// 存储键前缀：`$_kPrefix<userId>@<场景key>`
  static const _kPrefix = 'feature_discovery_shown@';

  Future<String> _storageKey(String key) async {
    final user = await AuthService.getUser();
    final uid = (user?['id'] as String?)?.trim();
    return '$_kPrefix${uid == null || uid.isEmpty ? 'anon' : uid}@$key';
  }

  Future<String> _userPrefix() async {
    final user = await AuthService.getUser();
    final uid = (user?['id'] as String?)?.trim();
    return '$_kPrefix${uid == null || uid.isEmpty ? 'anon' : uid}@';
  }

  /// 该场景是否已经展示过
  Future<bool> isShown(String key) async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(await _storageKey(key)) ?? false;
  }

  /// 标记为已展示（一生一次）
  Future<void> markShown(String key) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(await _storageKey(key), true);
  }

  /// 核心 API：该 key 未展示过才展示，展示后立即标记。
  /// 返回是否真的展示了（未展示 = 已展示过 / context 已卸载）。
  ///
  /// [onGo] 为「去看看」回调，由调用方负责跳对应页面——service 不
  /// 反向依赖任何 screen，保持接入点一行可挂。
  Future<bool> maybeShow(
    BuildContext context,
    String key,
    FeatureDiscoveryCardData data, {
    VoidCallback? onGo,
  }) async {
    if (await isShown(key)) return false;
    if (!context.mounted) return false;
    final messenger = ScaffoldMessenger.of(context);
    // 一生一次：决定展示即标记，之后无论用户点什么都永不再出
    await markShown(key);
    messenger.hideCurrentSnackBar();
    messenger.showSnackBar(
      SnackBar(
        duration: const Duration(seconds: 15),
        behavior: SnackBarBehavior.floating,
        backgroundColor: Colors.transparent,
        elevation: 0,
        padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
        content: FeatureDiscoveryCard(
          data: data,
          onGo: onGo == null
              ? null
              : () {
                  messenger.hideCurrentSnackBar();
                  onGo();
                },
          onDismiss: messenger.hideCurrentSnackBar,
        ),
      ),
    );
    return true;
  }

  /// 调试：重置当前账号某个场景的已展示标记
  Future<void> reset(String key) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(await _storageKey(key));
  }

  /// 调试：重置当前账号全部场景的已展示标记
  Future<void> resetAll() async {
    final prefs = await SharedPreferences.getInstance();
    final prefix = await _userPrefix();
    for (final k in prefs.getKeys().where((k) => k.startsWith(prefix))) {
      await prefs.remove(k);
    }
  }
}
