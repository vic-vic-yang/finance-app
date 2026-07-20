import 'dart:async';

import 'package:flutter/widgets.dart';

import '../core/motion.dart';

/// ======================================================================
/// Entrance · 卡片 / 区块入场动画
/// ======================================================================
///
/// 效果：fade 0→1 + translateY 12→0，单张 [Motion.base]（250ms），
/// 延迟 = [index] × [Motion.stagger]（40ms），曲线 [Motion.entrance]。
///
/// 「只播一次」语义：
///   - 本组件在**自身 State 生命周期内只播一次**（决断发生在
///     didChangeDependencies，之后的 rebuild 不会影响进行中的动画）。
///   - 但刷新场景下父级常会把内容子树整体卸载重建（如 loading 占位 ↔
///     内容切换），新 State 无法知道「已经播过」。此时由父级持有 played
///     标志并在重建时传 `play: false`，本组件即直接呈现终态。
///
/// 系统「减弱动效」开启时同样直接呈现终态（见 [Motion.reduced]）。
///
/// 用法：
/// ```dart
/// Entrance(index: 0, play: !_entrancePlayed, child: _summaryCard())
/// ```
class Entrance extends StatefulWidget {
  const Entrance({
    super.key,
    required this.index,
    required this.child,
    this.play = true,
    this.duration,
  });

  /// 入场序号：延迟 = index × [Motion.stagger]。同屏卡片按视觉顺序递增。
  final int index;

  final Widget child;

  /// 是否播放入场动画；false → 直接呈现终态（父级「只播一次」标志用）。
  final bool play;

  /// 单张时长，默认 [Motion.base]（250ms，规范区间 250~350ms）。
  final Duration? duration;

  @override
  State<Entrance> createState() => _EntranceState();
}

class _EntranceState extends State<Entrance>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl = AnimationController(
    vsync: this,
    duration: widget.duration ?? Motion.base,
  );
  late final CurvedAnimation _anim =
      CurvedAnimation(parent: _ctrl, curve: Motion.entrance);

  Timer? _delay;

  /// 是否已做过「播 or 直接终态」的决断（didChangeDependencies 可能多次调用）
  bool _resolved = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_resolved) return;
    _resolved = true;
    if (!widget.play || Motion.reduced(context)) {
      // 父级已播过 / 系统减弱动效 → 直接终态
      _ctrl.value = 1;
    } else if (widget.index <= 0) {
      _ctrl.forward();
    } else {
      _delay = Timer(Motion.stagger * widget.index, () {
        if (mounted) _ctrl.forward();
      });
    }
  }

  @override
  void dispose() {
    _delay?.cancel();
    _anim.dispose();
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _anim,
      builder: (context, child) {
        final t = _anim.value;
        return Opacity(
          opacity: t,
          child: Transform.translate(
            offset: Offset(0, 12 * (1 - t)),
            child: child,
          ),
        );
      },
      child: widget.child,
    );
  }
}
