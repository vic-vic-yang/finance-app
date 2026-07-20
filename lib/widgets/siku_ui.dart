/// ======================================================================
/// Siku UI Kit · 司库设计系统组件出口
/// ======================================================================
///
/// 新页面 / 新区块**必须**使用 kit 组件，不要在页面里自造同款。
/// 一个 import 拿全常用件：
///
/// ```dart
/// import '../widgets/siku_ui.dart';
/// ```
///
/// 组件清单：
///
/// | 组件                    | 来源文件              | 用途                         |
/// |-------------------------|-----------------------|------------------------------|
/// | AuraBackground          | widgets/glass.dart    | 页面沉浸式光影背景           |
/// | GlassCard               | widgets/glass.dart    | 玻璃卡片                     |
/// | AuraAppBar / Sliver 版  | widgets/glass.dart    | 统一顶栏                     |
/// | GlassNavBar             | widgets/glass.dart    | 底部导航胶囊                 |
/// | EmptyState              | widgets/glass.dart    | 空状态（emoji+标题+引导）    |
/// | AmountText / 相关工具   | widgets/amount_text.dart | 金额排版 / 格式化         |
/// | AuraSegmented           | 本文件                | 分段控件（solid / float）    |
/// | SectionHeader           | 本文件                | 区块标题（+右侧 ghost 操作） |
/// | HeaderAddButton         | 本文件                | header 右上统一「新建 +」入口 |
///
/// 同族配套（各自独立 import）：
///   - 图表规范：widgets/chart_kit.dart（ChartPalette / auraGrid / tooltip）
///   - 动效 tokens：core/motion.dart（Motion.fast/base/…）
///   - 入场动画：widgets/entrance.dart（Entrance，只播一次）
///   - 成功反馈：widgets/success_check.dart（SuccessCheckOverlay）
///
/// 使用约定：
///   1. 颜色一律走 AppColors / ChartPalette，禁止硬编码色值与 Material
///      命名色（tool/design_lint.dart 会拦截；确需豁免用行尾注释
///      `// design:ok 原因`）。
///   2. 圆角 / 字阶 / 间距以组件默认值为基准；确需微调走参数覆盖，
///      不要复制组件源码改一份新的。
library;

import 'package:flutter/material.dart';

import '../core/motion.dart';
import '../core/theme.dart';

export 'glass.dart';
export 'amount_text.dart';

/// 分段控件变体。
enum AuraSegmentedVariant {
  /// 选中 = 实心 primary + onPrimary 字（视觉基准：tools 的 ToolSegToggle）。
  solid,

  /// 选中 = surface 浮起 + 微阴影（视觉基准：首页账户 tab）。
  float,
}

/// 统一分段控件（收支切换 / 周期切换 / 类型切换等）。
///
/// 外观约定收敛于此，页面不再各写各的 AnimatedContainer：
///   - 外层：surfaceAlt 底 + padding 3；solid 加 0.6 发丝描边、圆角 14，
///     float 无描边、圆角 10
///   - 内块：solid 圆角 11 / float 圆角 8；选中态过渡走 [Motion.fast]
///
/// 用法：
/// ```dart
/// AuraSegmented<_Period>(
///   options: const [
///     (value: _Period.month, label: '月'),
///     (value: _Period.year, label: '年'),
///   ],
///   selected: _period,
///   onChanged: _switchPeriod,
/// )
/// ```
class AuraSegmented<T> extends StatelessWidget {
  const AuraSegmented({
    super.key,
    required this.options,
    required this.selected,
    required this.onChanged,
    this.variant = AuraSegmentedVariant.solid,
    this.expanded = true,
  });

  /// 选项（值 + 文案），顺序即展示顺序。
  final List<({T value, String label})> options;

  /// 当前选中值（与选项用 == 比对）。
  final T selected;

  /// 点按回调（重复点按当前项也会触发，业务侧自行短路）。
  final ValueChanged<T> onChanged;

  /// 视觉变体，默认 [AuraSegmentedVariant.solid]。
  final AuraSegmentedVariant variant;

  /// true（默认）= 选项等宽撑满整行；false = 紧凑模式（按内容宽度排列，
  /// 用于 AppBar actions 等宽度无界的场景）。
  final bool expanded;

  bool get _isSolid => variant == AuraSegmentedVariant.solid;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: AppColors.surfaceAlt,
        borderRadius: BorderRadius.circular(_isSolid ? 14 : 10),
        border:
            _isSolid ? Border.all(color: AppColors.border, width: 0.6) : null,
      ),
      child: Row(
        mainAxisSize: expanded ? MainAxisSize.max : MainAxisSize.min,
        children: [
          for (final opt in options)
            if (expanded) Expanded(child: _item(opt)) else _item(opt),
        ],
      ),
    );
  }

  Widget _item(({T value, String label}) opt) {
    final sel = opt.value == selected;
    final fg = _isSolid
        ? (sel ? AppColors.onPrimary : AppColors.text2)
        : (sel ? AppColors.text1 : AppColors.text2);
    return GestureDetector(
      onTap: () => onChanged(opt.value),
      behavior: HitTestBehavior.opaque,
      child: AnimatedContainer(
        duration: Motion.fast,
        curve: Curves.easeOut,
        padding: expanded
            ? EdgeInsets.symmetric(vertical: _isSolid ? 9 : 7)
            : EdgeInsets.symmetric(
                horizontal: _isSolid ? 14 : 12, vertical: _isSolid ? 6 : 5),
        decoration: BoxDecoration(
          color: sel
              ? (_isSolid ? AppColors.primary : AppColors.surface)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(_isSolid ? 11 : 8),
          boxShadow: !_isSolid && sel
              ? [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.06), // design:ok 浮起微阴影基准色（沿用首页 / 分类管理既有约定）
                    blurRadius: 4,
                    offset: const Offset(0, 1),
                  ),
                ]
              : null,
        ),
        child: Text(
          opt.label,
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: _isSolid ? 13.5 : 12,
            fontWeight: sel ? FontWeight.w600 : FontWeight.w500,
            color: fg,
          ),
        ),
      ),
    );
  }
}

/// 页面级「新建」唯一入口：header 右上角的 + 按钮。
///
/// 所有功能页的新建 / 新增 / 添加 / 上传入口统一收在这里，禁止再在页面内
/// 放 FAB、行内「+ 新增」按钮或虚线新建卡。视觉基准即 goals / recurring 页
/// 既有范式：primary 色 26 号圆角加号、38×38 紧凑点击区、右缘 16 padding。
///
/// 用法：
/// ```dart
/// AuraAppBar(
///   title: '预算管理',
///   actions: [HeaderAddButton(tooltip: '新增预算', onPressed: _openSheet)],
/// )
/// ```
class HeaderAddButton extends StatelessWidget {
  const HeaderAddButton({
    super.key,
    required this.tooltip,
    this.icon = Icons.add_rounded,
    required this.onPressed,
  });

  /// 无障碍 / 长按提示文案，如「新增预算」。
  final String tooltip;

  /// 图标，默认 [Icons.add_rounded]；上传类入口可传 upload_file_rounded。
  final IconData icon;

  /// 点按回调，通常打开现有新建弹层 / 流程。
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(right: 16),
      child: IconButton(
        tooltip: tooltip,
        padding: EdgeInsets.zero,
        constraints: const BoxConstraints.tightFor(width: 38, height: 38),
        icon: Icon(icon, color: AppColors.primary, size: 26),
        onPressed: onPressed,
      ),
    );
  }
}

/// 区块标题：左标题 + 可选右侧 ghost 文字操作 / 自定义 trailing。
///
/// 统一字阶（titleMedium / w600 / text1）与间距（默认上 24 下 12、
/// 左右 20，可用 top / bottom / horizontal 覆盖）。「标题 + 查看更多」
/// 一律用它，不要再各写各的 Row + Spacer。
///
/// 用法：
/// ```dart
/// SectionHeader(title: '我的账户', actionLabel: '管理', onTap: _openAccounts)
/// ```
class SectionHeader extends StatelessWidget {
  const SectionHeader({
    super.key,
    required this.title,
    this.actionLabel,
    this.onTap,
    this.trailing,
    this.top = 24,
    this.bottom = 12,
    this.horizontal = 20,
  });

  /// 标题文本（titleMedium / w600 / text1）。
  final String title;

  /// 右侧 ghost 操作文案；与 [onTap] 同时提供才显示（文字 + chevron）。
  final String? actionLabel;

  /// ghost 操作回调。
  final VoidCallback? onTap;

  /// 自定义右侧组件（与 actionLabel 并存时 trailing 在前）。
  final Widget? trailing;

  /// 上间距，默认 24。
  final double top;

  /// 下间距，默认 12。
  final double bottom;

  /// 左右间距，默认 20。
  final double horizontal;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(horizontal, top, horizontal, bottom),
      child: Row(children: [
        Text(title, style: Theme.of(context).textTheme.titleMedium),
        const Spacer(),
        if (trailing != null) trailing!,
        if (actionLabel != null && onTap != null)
          GestureDetector(
            onTap: onTap,
            behavior: HitTestBehavior.opaque,
            child: Row(children: [
              Text(actionLabel!,
                  style: TextStyle(fontSize: 13, color: AppColors.primary)),
              Icon(Icons.chevron_right_rounded,
                  size: 16, color: AppColors.primary),
            ]),
          ),
      ]),
    );
  }
}
