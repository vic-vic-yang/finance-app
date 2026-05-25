import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'theme_service.dart';

/// AppColors 全部动态：根据当前主题色 + 亮/暗模式返回
///
/// 设计原则（受 minimalist 风格启发）：
/// - 大面积都是 bg / surface / text，颜色克制
/// - primary 只用在重要操作（FAB、按钮、选中态边框/文字）
/// - primaryLight 仅作"轻提示"用，能不用尽量不用
/// - income / expense / warning 是语义色，跟主题无关
class AppColors {
  AppColors._();

  // ── 主题色（跟随用户选择） ────────────────────────────────
  /// 当前 primary：普通主题用 seed；无色主题用 text1（跟随亮/暗模式自动黑/白）
  static Color get primary {
    final pal = ThemeService.instance.palette;
    return pal.isMono ? text1 : pal.seed;
  }

  /// primary 上的前景色（自动算对比 —— 浅色主题用黑，深色主题用白）
  static Color get onPrimary {
    final p = primary;
    return p.computeLuminance() > 0.55 ? const Color(0xFF101828) : Colors.white;
  }

  /// 淡化主色，用作"轻强调"的背景（如选中卡片）。深色模式自动调暗
  static Color get primaryLight {
    final p = primary;
    return _isDark
        ? Color.alphaBlend(p.withOpacity(0.16), const Color(0xFF1A1A1F))
        : Color.alphaBlend(p.withOpacity(0.10), Colors.white);
  }

  /// 主色渐变（深色起、浅色止）—— 给 hero 卡片用
  /// 无色主题：暗模式用稍亮的灰渐变；亮模式用深色 shadcn 风格渐变
  static List<Color> get primaryGradient {
    if (ThemeService.instance.palette.isMono) {
      return _isDark
          ? const [Color(0xFF2A2A30), Color(0xFF1F1F25)]
          : const [Color(0xFF101828), Color(0xFF1F2937)];
    }
    final p = primary;
    final lighter = Color.alphaBlend(Colors.white.withOpacity(0.28), p);
    return [p, lighter];
  }

  /// 渐变卡片上的前景色（按渐变起始色的亮度自动选）
  /// —— 跟 onPrimary 不同：onPrimary 算的是 primary（按钮色），
  /// 渐变可能跟按钮色不一样（如无色主题）
  static Color get onPrimaryGradient {
    final start = primaryGradient.first;
    return start.computeLuminance() > 0.55
        ? const Color(0xFF101828)
        : Colors.white;
  }

  // ── 语义色（不跟主题变） ──────────────────────────────────
  static const Color income       = Color(0xFF00BA88);
  static const Color incomeLight  = Color(0xFFDFF7F0);
  static const Color expense      = Color(0xFFF04438);
  static const Color expenseLight = Color(0xFFFEE4E2);
  static const Color warning      = Color(0xFFF79009);
  static const Color warningLight = Color(0xFFFEF0C7);

  // ── 中性色（亮 / 暗双模） ────────────────────────────────
  static Color get bg          => _isDark ? const Color(0xFF0E0E10) : const Color(0xFFF7F8FA);
  static Color get surface     => _isDark ? const Color(0xFF18181C) : Colors.white;
  /// 比 surface 稍微"再高一层"的卡片，比如嵌套卡片
  static Color get surfaceAlt  => _isDark ? const Color(0xFF222227) : const Color(0xFFF1F3F5);
  static Color get text1       => _isDark ? const Color(0xFFF3F4F6) : const Color(0xFF101828);
  static Color get text2       => _isDark ? const Color(0xFF9AA0A6) : const Color(0xFF667085);
  static Color get text3       => _isDark ? const Color(0xFF5F6368) : const Color(0xFF98A2B3);
  static Color get border      => _isDark ? const Color(0xFF26262C) : const Color(0xFFE9ECEF);

  static bool get _isDark => ThemeService.instance.isDark;
}

class AppTheme {
  AppTheme._();

  static ThemeData build() {
    final isDark = ThemeService.instance.isDark;
    final seed   = ThemeService.instance.palette.seed;

    final scheme = ColorScheme.fromSeed(
      seedColor: seed,
      brightness: isDark ? Brightness.dark : Brightness.light,
      primary: seed,
      onPrimary: AppColors.onPrimary,
      surface: AppColors.surface,
    );

    return ThemeData(
      useMaterial3: true,
      brightness: isDark ? Brightness.dark : Brightness.light,
      colorScheme: scheme,
      scaffoldBackgroundColor: AppColors.bg,
      appBarTheme: AppBarTheme(
        backgroundColor: AppColors.bg,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        systemOverlayStyle: isDark ? SystemUiOverlayStyle.light : SystemUiOverlayStyle.dark,
        centerTitle: true,
        titleTextStyle: TextStyle(
          color: AppColors.text1,
          fontSize: 17,
          fontWeight: FontWeight.w600,
          letterSpacing: -0.2,
        ),
        iconTheme: IconThemeData(color: AppColors.text1, size: 22),
      ),
      cardTheme: CardThemeData(
        color: AppColors.surface,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(color: AppColors.border),
        ),
        margin: EdgeInsets.zero,
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: AppColors.surface,
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: AppColors.border),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: AppColors.border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: AppColors.primary, width: 1.5),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: AppColors.expense),
        ),
        hintStyle: TextStyle(color: AppColors.text2, fontSize: 14),
        labelStyle: TextStyle(color: AppColors.text2, fontSize: 14),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.primary,
          foregroundColor: AppColors.onPrimary,
          minimumSize: const Size(double.infinity, 52),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          elevation: 0,
          textStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(foregroundColor: AppColors.primary),
      ),
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        backgroundColor: AppColors.primary,
        foregroundColor: AppColors.onPrimary,
        elevation: 6,
        shape: const CircleBorder(),
      ),
      dividerTheme: DividerThemeData(color: AppColors.border, thickness: 1, space: 1),
      chipTheme: ChipThemeData(
        backgroundColor: AppColors.surface,
        selectedColor: AppColors.primaryLight,
        labelStyle: TextStyle(fontSize: 13, color: AppColors.text1),
        side: BorderSide(color: AppColors.border),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        showCheckmark: false,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: AppColors.surface,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
      ),
      popupMenuTheme: PopupMenuThemeData(
        color: AppColors.surface,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: BorderSide(color: AppColors.border),
        ),
        textStyle: TextStyle(color: AppColors.text1, fontSize: 14),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: AppColors.surface,
        surfaceTintColor: Colors.transparent,
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: AppColors.text1,
        contentTextStyle: TextStyle(color: AppColors.surface),
      ),
    );
  }
}
