import 'dart:async';

import 'package:flutter/material.dart';

import '../core/motion.dart';
import '../core/theme.dart';

/// ======================================================================
/// SuccessCheck · 操作成功的对勾反馈徽标
/// ======================================================================
///
/// 视觉：圆形 [AppColors.primary] 底 + [AppColors.onPrimary] 白色对勾，
/// 极淡主色投影（Aura 语言：克制、不喧宾）。
///
/// 典型用法（记账保存成功后）：
/// ```dart
/// HapticFeedback.lightImpact();
/// await SuccessCheckOverlay.show(context);
/// if (mounted) Navigator.pop(context, true);
/// ```
///
/// 时序：fade in + scale 0.6→1.0（250ms，[Motion.spring] 轻回弹）
///   → 停留 [SuccessCheckOverlay.holdMs]（500ms）→ fade out（150ms）。
///   全程约 900ms，Future 在动画完全结束后完成。
///
/// 系统「减弱动效」开启时整体跳过（装饰动画直接到终态，见 [Motion.reduced]）。
class SuccessCheck extends StatelessWidget {
  const SuccessCheck({super.key, this.size = 84});

  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: AppColors.primary,
        shape: BoxShape.circle,
        boxShadow: [
          BoxShadow(
            color: AppColors.primary.withValues(alpha: 0.32),
            blurRadius: 28,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child:
          Icon(Icons.check_rounded, color: AppColors.onPrimary, size: size * 0.52),
    );
  }
}

/// 屏幕中央浮出 [SuccessCheck] 的一次性 Overlay。
class SuccessCheckOverlay {
  SuccessCheckOverlay._();

  /// 对勾停留时长（fade in 之后、fade out 之前）
  static const holdMs = 500;

  /// 在 [context] 最近的 Overlay 中央弹出成功对勾；动画（含停留）结束后返回。
  ///
  /// - 弹出期间吸收全部触摸，避免动画未结束用户又触发一次保存。
  /// - 系统「减弱动效」开启或无可用 Overlay 时：不播动画，Future 立即完成，
  ///   调用方随即执行原有关闭逻辑（即「直接到终态」）。
  static Future<void> show(BuildContext context) {
    if (Motion.reduced(context)) return Future.value();
    final overlay = Overlay.maybeOf(context);
    if (overlay == null) return Future.value();

    final completer = Completer<void>();
    late final OverlayEntry entry;
    entry = OverlayEntry(
      builder: (_) => Positioned.fill(
        child: AbsorbPointer(
          child: Center(
            child: _Pulse(onComplete: () {
              entry.remove();
              if (!completer.isCompleted) completer.complete();
            }),
          ),
        ),
      ),
    );
    overlay.insert(entry);
    return completer.future;
  }
}

/// 对勾的入场 → 停留 → 退场脉冲动画（完全自驱动，播完回调 [onComplete]）。
class _Pulse extends StatefulWidget {
  const _Pulse({required this.onComplete});

  final VoidCallback onComplete;

  @override
  State<_Pulse> createState() => _PulseState();
}

class _PulseState extends State<_Pulse> with SingleTickerProviderStateMixin {
  static const _inMs = 250; // Motion.base
  static const _outMs = 150; // Motion.fast
  static const _totalMs = _inMs + SuccessCheckOverlay.holdMs + _outMs;

  late final AnimationController _ctrl = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: _totalMs),
  );

  /// fade：入场淡入 → 停留 → 退场淡出
  late final Animation<double> _opacity = TweenSequence<double>([
    TweenSequenceItem(
      tween:
          Tween(begin: 0.0, end: 1.0).chain(CurveTween(curve: Motion.standard)),
      weight: _inMs.toDouble(),
    ),
    TweenSequenceItem(
      tween: ConstantTween(1.0),
      weight: SuccessCheckOverlay.holdMs.toDouble(),
    ),
    TweenSequenceItem(
      tween:
          Tween(begin: 1.0, end: 0.0).chain(CurveTween(curve: Motion.standard)),
      weight: _outMs.toDouble(),
    ),
  ]).animate(_ctrl);

  /// scale：0.6 → 1.0，easeOutBack 轻回弹（只作用于入场段，之后保持 1.0）
  late final Animation<double> _scale = Tween(begin: 0.6, end: 1.0).animate(
    CurvedAnimation(
      parent: _ctrl,
      curve: const Interval(0, _inMs / _totalMs, curve: Curves.easeOutBack),
    ),
  );

  @override
  void initState() {
    super.initState();
    _ctrl.forward().whenComplete(widget.onComplete);
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _ctrl,
      builder: (context, child) => Opacity(
        opacity: _opacity.value,
        child: Transform.scale(scale: _scale.value, child: child),
      ),
      child: const SuccessCheck(),
    );
  }
}
