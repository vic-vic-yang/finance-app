import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

import '../core/theme.dart';
import '../core/theme_service.dart';

/// ======================================================================
/// ChartKit · 司库图表设计规范与基础组件（Aura · Quiet Luxury）
/// ======================================================================
///
/// 本文件是所有图表（fl_chart 与自绘）的样式唯一来源。新增图表时按以下
/// 规范取样式，不要在业务页里各写各的颜色 / 网格 / tooltip。
///
/// ## 1. 色板取色顺序（[ChartPalette]）
///
/// 饼图切片、多序列柱 / 线、图例圆点、占比进度条一律按
/// `ChartPalette.colorAt(index)` 取色（取模循环，超量自动复用）：
///
/// ```
///  0 sage 绿      支出族主色        1 terracotta 陶红  收入族主色
///  2 forest 深绿  主色族            3 sand 沙金        warning 族
///  4 深 sage      sage 降明度       5 灰绿            中性（其他/杂项感）
///  6 浅陶         terracotta 升明度  7 深沙金          sand 降明度
/// ```
///
/// 冷暖交替排列，保证饼图相邻切片对比；前 4 色即设计系统四大语义色族，
/// 后 4 色为同族明度派生。同一图表实体的色点 / 进度条 / 切片必须用
/// 同一个 index 取色，严禁各自再派生一套。
///
/// ## 2. 幽灵网格哲学（[auraGrid]）
///
/// 网格是参照物、不是主角：0.5px 发丝线 + `AppColors.border` 40%
/// 透明度，只留横线（数值参照），去掉竖线（维度由 axis label 承担）。
/// 看得见、感不到；数据必须永远比网格抢眼。
///
/// ## 3. Tooltip 约定（[auraTooltipStyle]）
///
/// - 背景：light = `AppColors.text1`（墨黑浮层）；dark = `AppColors.surfaceAlt`
///   （浅于卡片底的高对比浮层）+ 一道发丝描边与卡片分离。
/// - 文字：反色保证可读——light 深底浅字（`AppColors.bg`），dark 浅底
///   亮字（`AppColors.text1`）。12px / w600。
/// - 圆角 12，padding 横 10 纵 8。
/// - 内容约定：第一行维度（日期 / 分类），第二行数值（金额走 fmtMoney）。
/// - 接入：LineChart 用 [auraLineTooltipData]、BarChart 用
///   [auraBarTooltipData]，tooltip 内 TextStyle 取
///   `auraTooltipStyle().textStyle`。
///
/// ## 4. 迷你趋势（[Sparkline]）
///
/// 卡片内嵌趋势一律用 [Sparkline]（CustomPainter 自绘，不给迷你图背
/// fl_chart 重库）：无坐标轴 / 网格 / 标签，只传达"走向"。
///
/// 落地示例（首页 hero 卡净资产趋势，见 home_screen.dart `_heroSparkline`）：
/// ```dart
/// // 数据取自已有的 getStats 响应 assetTrend（当月日终总资产），无新增请求
/// Sparkline(values: _assetTrend, height: 44, width: w, color: fg)
/// ```

// ─────────────────────────────────────────────────────────────────────
// ChartPalette · 分类色板
// ─────────────────────────────────────────────────────────────────────

/// 分类色板：饼图 / 柱状图 / 多序列图表的统一取色序列。
///
/// 深浅双模：dark 下每色叠加 12% 白整体提亮，保证切片在 obsidian
/// 卡片上仍有足够明度差（见 [colorAt]）。
class ChartPalette {
  ChartPalette._();

  // ── 锚点色（派生色板豁免：以下 hex 是设计系统语义色的"原料"，非新色）──
  // 派生逻辑：
  //   _sage / _terracotta / _sand 直接复刻 AppColors.expense / income /
  //   warning 的语义色值；_forest 复刻 Aura light primary；_grayGreen
  //   复刻 dark 档 text3（outline 灰绿）。后续槽位只在 HSL 明度上平移
  //   （±0.08~0.14），不动色相与饱和度，保持低饱和 Aura 调性。
  static const Color _sage = Color(0xFF7CA188); // design:ok 色板锚点 = AppColors.expense
  static const Color _terracotta = Color(0xFFC68B77); // design:ok 色板锚点 = AppColors.income
  static const Color _sand = Color(0xFFE0A86A); // design:ok 色板锚点 = AppColors.warning
  static const Color _forest = Color(0xFF1B3022); // design:ok 色板锚点 = Aura light primary
  static const Color _grayGreen = Color(0xFF8B928C); // design:ok 色板锚点 = dark outline 灰绿

  /// HSL 明度平移（色相 / 饱和度不动）：同族派生，保持色板克制和谐。
  static Color _shift(Color c, double dLight) {
    final hsl = HSLColor.fromColor(c);
    final l = (hsl.lightness + dLight).clamp(0.12, 0.86);
    return hsl.withLightness(l).toColor();
  }

  /// 基准序列（8 色，冷暖交替）。dark 的提亮在 [colorAt] 统一处理。
  static List<Color> get _base => [
        _sage, //                     0 sage 绿（支出族）
        _terracotta, //              1 terracotta 陶红（收入族）
        _forest, //                  2 forest 深绿（主色族）
        _sand, //                    3 sand 沙金（warning 族）
        _shift(_sage, -0.14), //     4 深 sage
        _grayGreen, //               5 中性灰绿
        _shift(_terracotta, 0.08), // 6 浅陶
        _shift(_sand, -0.12), //     7 深沙金
      ];

  /// 序列长度（取模基数）。
  static int get length => _base.length;

  /// 按序取色，取模循环。dark 模式整体 `alphaBlend` 12% 白提亮。
  static Color colorAt(int index) {
    final c = _base[index % _base.length];
    if (!ThemeService.instance.isDark) return c;
    return Color.alphaBlend(
        Colors.white.withValues(alpha: 0.12), c); // design:ok dark 模式整体叠白提亮（色板派生规则）
  }
}

// ─────────────────────────────────────────────────────────────────────
// auraGrid · 幽灵网格
// ─────────────────────────────────────────────────────────────────────

/// 幽灵网格工厂：0.5px 发丝横线、`AppColors.border` 40% 透明度、
/// 只留横线去竖线。各参数可按图表需要覆盖（如 [horizontalInterval]）。
FlGridData auraGrid({
  double? horizontalInterval,
  Color? color,
  double strokeWidth = 0.5,
  double opacity = 0.4,
  bool drawHorizontalLine = true,
}) {
  final lineColor = (color ?? AppColors.border).withValues(alpha: opacity);
  return FlGridData(
    show: true,
    drawVerticalLine: false,
    drawHorizontalLine: drawHorizontalLine,
    horizontalInterval: horizontalInterval,
    getDrawingHorizontalLine: (_) =>
        FlLine(color: lineColor, strokeWidth: strokeWidth),
  );
}

// ─────────────────────────────────────────────────────────────────────
// auraTooltipStyle · 统一 tooltip
// ─────────────────────────────────────────────────────────────────────

/// 统一 tooltip 样式值（light / dark 自适应，随主题切换即时生效）。
///
/// 背景与文字永远"反色配对"：
///   - light：墨黑底（text1）× 奶白字（bg）
///   - dark ：高对比浮层底（surfaceAlt）× 亮字（text1）+ 发丝描边
class AuraTooltipStyle {
  const AuraTooltipStyle();

  /// 浮层背景。
  Color get bg =>
      ThemeService.instance.isDark ? AppColors.surfaceAlt : AppColors.text1;

  /// 文字颜色（与 [bg] 反色，保证可读）。
  Color get fg =>
      ThemeService.instance.isDark ? AppColors.text1 : AppColors.bg;

  /// 统一字样：12px / w600，行高 1.3（两行内容不挤）。
  TextStyle get textStyle => TextStyle(
        color: fg,
        fontSize: 12,
        fontWeight: FontWeight.w600,
        height: 1.3,
      );

  /// dark 下给浮层一道发丝边与卡片底分离；light 墨黑底不需要。
  BorderSide get border => ThemeService.instance.isDark
      ? BorderSide(color: AppColors.border, width: 0.6)
      : BorderSide.none;

  /// 圆角 12。
  double get radius => 12;

  /// padding 横 10 纵 8。
  EdgeInsets get padding =>
      const EdgeInsets.symmetric(horizontal: 10, vertical: 8);
}

/// 取统一 tooltip 样式（fl_chart 的 Line / Bar tooltip 共用此约定）。
AuraTooltipStyle auraTooltipStyle() => const AuraTooltipStyle();

/// LineChart 统一 tooltip 配置：样式全部来自 [auraTooltipStyle]，
/// 业务侧只负责组装内容（[getTooltipItems]，文字用
/// `auraTooltipStyle().textStyle`）。
LineTouchTooltipData auraLineTooltipData({
  required GetLineTooltipItems getTooltipItems,
  double maxContentWidth = 160,
}) {
  final tip = auraTooltipStyle();
  return LineTouchTooltipData(
    getTooltipColor: (_) => tip.bg,
    tooltipRoundedRadius: tip.radius,
    tooltipPadding: tip.padding,
    tooltipBorder: tip.border,
    maxContentWidth: maxContentWidth,
    fitInsideHorizontally: true,
    fitInsideVertically: true,
    getTooltipItems: getTooltipItems,
  );
}

/// BarChart 统一 tooltip 配置：同 [auraLineTooltipData]，用于 BarTouchData。
BarTouchTooltipData auraBarTooltipData({
  required GetBarTooltipItem getTooltipItem,
  double maxContentWidth = 160,
}) {
  final tip = auraTooltipStyle();
  return BarTouchTooltipData(
    getTooltipColor: (_) => tip.bg,
    tooltipRoundedRadius: tip.radius,
    tooltipPadding: tip.padding,
    tooltipBorder: tip.border,
    maxContentWidth: maxContentWidth,
    fitInsideHorizontally: true,
    fitInsideVertically: true,
    getTooltipItem: getTooltipItem,
  );
}

// ─────────────────────────────────────────────────────────────────────
// Sparkline · 迷你趋势线
// ─────────────────────────────────────────────────────────────────────

/// 迷你趋势线（sparkline）——卡片内嵌趋势展示专用。
///
/// CustomPainter 自绘，不依赖 fl_chart：无坐标轴 / 网格 / 标签，
/// 只传达"走向"。值域自动归一化到组件高度；空列表 / 单值安全降级为
/// 居中平线。深色 / 浅色模式由传入 [color] 决定（默认 `AppColors.primary`）。
///
/// [progress]（0~1）支持「首次入场描绘」动画：小于 1 时按宽度比例
/// 从左到右裁剪线条与面积，调用方用 TweenAnimationBuilder 驱动即可；
/// 默认 1 = 完整呈现，既有调用方零感知。
///
/// 用法（首页 hero 卡净资产趋势即按此接入）：
/// ```dart
/// Sparkline(values: assetTrendBalances, height: 44, width: w, color: fg)
/// ```
///
/// 注意：宽度无界的布局环境（如 Row 直接子级）必须传 [width]；
/// 有界环境（Expanded / 固定宽容器 / LayoutBuilder）可省略，自动占满。
class Sparkline extends StatelessWidget {
  const Sparkline({
    super.key,
    required this.values,
    this.color,
    this.strokeWidth = 1.5,
    this.height = 32,
    this.width,
    this.fill = true,
    this.fillOpacity = 0.08,
    this.progress = 1.0,
  });

  /// 序列值（按时间升序）。空列表 / 单值降级为平线。
  final List<double> values;

  /// 线条颜色，默认 `AppColors.primary`。
  final Color? color;

  /// 线宽，默认 1.5。
  final double strokeWidth;

  /// 组件高度，默认 32。
  final double height;

  /// 组件宽度；null 时尽量占满父约束（无界约束下回退 64px）。
  final double? width;

  /// 是否在线条下方铺 color → 0 的纵向渐变面积，默认 true。
  final bool fill;

  /// 面积渐变起始透明度（终点恒为 0），默认 0.08；
  /// 渐变 hero 卡上可适当加大（如 0.10）保证可见。
  final double fillOpacity;

  /// 线条描绘进度 0~1：< 1 时按宽度从左到右裁剪呈现（用于一次性
  /// 入场描绘动画），默认 1 = 完整线条。
  final double progress;

  @override
  Widget build(BuildContext context) {
    final c = color ?? AppColors.primary;
    return SizedBox(
      height: height,
      width: width,
      child: CustomPaint(
        // 无界约束下的回退尺寸（宽度取传入值或 64）
        size: Size(width ?? 64, height),
        painter: _SparklinePainter(
          values: values,
          color: c,
          strokeWidth: strokeWidth,
          fill: fill,
          fillOpacity: fillOpacity,
          progress: progress,
        ),
      ),
    );
  }
}

class _SparklinePainter extends CustomPainter {
  _SparklinePainter({
    required this.values,
    required this.color,
    required this.strokeWidth,
    required this.fill,
    required this.fillOpacity,
    required this.progress,
  });

  final List<double> values;
  final Color color;
  final double strokeWidth;
  final bool fill;
  final double fillOpacity;
  final double progress;

  @override
  void paint(Canvas canvas, Size size) {
    // 描绘进度 < 1：按宽度比例裁剪画布，线条从左到右「长出来」
    final p = progress.clamp(0.0, 1.0);
    if (p < 1.0) {
      canvas.save();
      canvas.clipRect(Rect.fromLTWH(0, 0, size.width * p, size.height));
    }

    // 内缩：描边不出界 + 发丝留白
    final inset = strokeWidth / 2 + 0.5;
    final w = size.width - inset * 2;
    final h = size.height - inset * 2;
    if (w <= 0 || h <= 0) {
      if (p < 1.0) canvas.restore();
      return;
    }

    // 值域归一化
    double minV = double.infinity;
    double maxV = double.negativeInfinity;
    for (final v in values) {
      if (v < minV) minV = v;
      if (v > maxV) maxV = v;
    }
    final n = values.length;
    final span = n >= 2 ? maxV - minV : 0.0;

    Offset pointAt(int i) {
      final x = inset + w * i / (n - 1);
      final t = span > 0 ? (values[i] - minV) / span : 0.5;
      return Offset(x, inset + h * (1 - t));
    }

    final line = Path();
    if (n >= 2 && span > 0) {
      final pts = [for (var i = 0; i < n; i++) pointAt(i)];
      line.moveTo(pts.first.dx, pts.first.dy);
      // 水平控制点三次贝塞尔：平滑且 y 恒在两端点之间（不越界过冲）
      for (var i = 1; i < pts.length; i++) {
        final p0 = pts[i - 1];
        final p1 = pts[i];
        final mx = (p0.dx + p1.dx) / 2;
        line.cubicTo(mx, p0.dy, mx, p1.dy, p1.dx, p1.dy);
      }
    } else {
      // 降级：空列表 / 单值 / 全部同值 → 垂直居中平线
      final y = inset + h / 2;
      line.moveTo(inset, y);
      line.lineTo(inset + w, y);
    }

    if (fill) {
      final fillPath = Path.from(line)
        ..lineTo(inset + w, inset + h)
        ..lineTo(inset, inset + h)
        ..close();
      final fillPaint = Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            color.withValues(alpha: fillOpacity),
            color.withValues(alpha: 0.0),
          ],
        ).createShader(Rect.fromLTWH(0, 0, size.width, size.height));
      canvas.drawPath(fillPath, fillPaint);
    }

    final strokePaint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..isAntiAlias = true;
    canvas.drawPath(line, strokePaint);

    if (p < 1.0) canvas.restore();
  }

  @override
  bool shouldRepaint(_SparklinePainter old) =>
      old.color != color ||
      old.strokeWidth != strokeWidth ||
      old.fill != fill ||
      old.fillOpacity != fillOpacity ||
      old.progress != progress ||
      !_sameValues(old.values, values);

  static bool _sameValues(List<double> a, List<double> b) {
    if (identical(a, b)) return true;
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }
}
