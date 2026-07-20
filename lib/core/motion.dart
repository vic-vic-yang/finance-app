import 'package:flutter/widgets.dart';

/// ======================================================================
/// Motion · 司库微动效 tokens（Aura · Quiet Luxury：克制、短暂、只播一次）
/// ======================================================================
///
/// 使用规范：
///   1. **只播一次**：装饰动画（入场 / 反馈 / 转场）只在「首次出现」时播放；
///      refreshBus 触发的重建、数据刷新不得重播。做法：父级 State 持有
///      played 标志，重建时让动画组件直接呈现终态（见 widgets/entrance.dart
///      的 `play` 参数与首页的用法）。
///   2. **尊重系统「减弱动效」**：任何装饰动画播放前必须经过
///      [Motion.reduced]（即 `MediaQuery.disableAnimations`）裁决；
///      为 true 时跳过动画、**直接呈现终态**，不得有任何中间帧。
///   3. **时长只用 token**，不要在业务代码里散落魔法数字：
///        [fast]     150ms  微反馈（fade out、轻量状态切换）
///        [base]     250ms  常规过渡（tab 转场、卡片入场、选中态）
///        [slow]     400ms  较大的布局 / 页面级过渡
///        [emphasis] 600ms  强调（hero 大数字 count-up）
///   4. **曲线只用 token**：
///        [standard]   easeOutCubic  常规过渡，快出缓收
///        [emphasized] easeOutExpo   强调收尾（大数字落定的「刹车感」）
///        [entrance]   easeOutQuart  入场（fade + slide）
///        [spring]     easeOutBack   轻微回弹（成功对勾等一次性反馈）
class Motion {
  Motion._();

  // ── 时长 ────────────────────────────────────────────────────
  static const fast = Duration(milliseconds: 150);
  static const base = Duration(milliseconds: 250);
  static const slow = Duration(milliseconds: 400);
  static const emphasis = Duration(milliseconds: 600);

  /// 入场 stagger 步长：同屏多张卡片延迟递增 40ms
  static const stagger = Duration(milliseconds: 40);

  // ── 曲线 ────────────────────────────────────────────────────
  static const standard = Curves.easeOutCubic;
  static const emphasized = Curves.easeOutExpo;
  static const entrance = Curves.easeOutQuart;
  static const spring = Curves.easeOutBack;

  /// 系统「减弱动效」是否开启。true 时一切装饰动画必须跳过、直接终态。
  static bool reduced(BuildContext context) =>
      MediaQuery.of(context).disableAnimations;
}
