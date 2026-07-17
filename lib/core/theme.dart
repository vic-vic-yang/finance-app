import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'theme_service.dart';

/// ======================================================================
/// Aura Finance · "Quiet Luxury" 设计系统
/// ======================================================================
///
/// 来源：/ui/light/DESIGN.md + /ui/dark/DESIGN.md
///
/// 关键决策：
///   - **字体**：全局 Outfit（google_fonts 首次启动从 CDN 下载并缓存到本地）
///   - **配色**：深森林绿 / 奶白底（light）  ·  obsidian / sage 绿（dark）
///   - **形状**：大圆角软卡（16-20px），按钮 12px，pill chips
///   - **阴影**：极淡的环境阴影（30-50px blur，3-5% opacity），玻璃感
///   - **图标**：thin-line 200 weight 风格（Flutter 端用默认 Material outlined 近似）
///
/// 设计原则继承自原 minimalist 主题：
///   - 大面积都是 bg / surface / text，颜色克制
///   - primary 只用在重要操作（FAB、按钮、选中态边框/文字）
///   - primaryLight 仅作"轻提示"用，能不用尽量不用
///   - income / expense / warning 是语义色，跟主题无关
///
/// 尺度约定（新代码请遵守，避免各写各的）：
///   - 圆角层级：hero 大卡 18 · 标准卡 16 · 列表条/子卡 14 · chip/输入 10-12
///     · 进度条/分段 2-4 · 胶囊按钮 20+
///   - 严重度色：critical=income(哑红) · warning=warning(琥珀) · info=primary
///     （洞察卡/CFO 用左侧 3px 色条表达，不用整卡彩底）
///   - 空状态：统一用 widgets/glass.dart 的 EmptyState（圆底 emoji + 标题 + 引导）
///   - 次要操作按钮：ghost 胶囊（描边小 pill），主操作才用实心 primary
class AppColors {
  AppColors._();

  // ── 主题色（跟随用户选择 / Aura 主题用专用色板） ────────────
  /// 当前 primary
  ///   - Aura 主题（推荐默认）：light 用 Forest Green，dark 用 Sage
  ///   - 无色主题：用 text1（黑/白）
  ///   - 其他主题：用种子色
  static Color get primary {
    final pal = ThemeService.instance.palette;
    if (pal.isAura) {
      return _isDark ? _auraDarkPrimary : _auraLightPrimary;
    }
    return pal.isMono ? text1 : pal.seed;
  }

  /// primary 上的前景色（自动算对比度）
  static Color get onPrimary {
    final p = primary;
    return p.computeLuminance() > 0.55 ? const Color(0xFF143724) : Colors.white;
  }

  /// 淡化主色 → 用作"轻强调"的背景（chip 选中、列表 hover、AI 提示卡）
  static Color get primaryLight {
    final p = primary;
    return _isDark
        ? Color.alphaBlend(p.withValues(alpha: 0.16), const Color(0xFF1A1A1F))
        : Color.alphaBlend(p.withValues(alpha: 0.10), Colors.white);
  }

  /// Hero 卡片渐变
  ///   - Aura light: 深森林绿 → 苔色，像 dashboard 截图的 ADD FUNDS 卡
  ///   - Aura dark: obsidian → 略带 sage 的灰
  ///   - 无色 / 其他主题：沿用原有渐变逻辑
  static List<Color> get primaryGradient {
    final pal = ThemeService.instance.palette;
    if (pal.isAura) {
      return _isDark
          ? const [Color(0xFF1A2A20), Color(0xFF0E0E10)]
          : const [Color(0xFF1B3022), Color(0xFF36573C)];
    }
    if (pal.isMono) {
      return _isDark
          ? const [Color(0xFF2A2A30), Color(0xFF1F1F25)]
          : const [Color(0xFF101828), Color(0xFF1F2937)];
    }
    final p = primary;
    final lighter = Color.alphaBlend(Colors.white.withValues(alpha: 0.28), p);
    return [p, lighter];
  }

  /// 渐变卡片上的前景色
  static Color get onPrimaryGradient {
    final start = primaryGradient.first;
    return start.computeLuminance() > 0.55
        ? const Color(0xFF101828)
        : Colors.white;
  }

  // ── 语义色（Aura 风：低饱和、内敛）─────────────────────────
  // 约定：收入 = 红、支出 = 绿（中国习惯：红涨/进、绿跌/出）。
  // 全局金额颜色都引用 income/expense，改这里即全局生效。
  /// 收入 — Muted Terracotta（红）
  static const Color income       = Color(0xFFC68B77);
  static Color get incomeLight => _isDark
      ? const Color(0xFF2E1C16)
      : const Color(0xFFF5E6E0);
  /// 支出 — Soft Sage（绿）
  static const Color expense      = Color(0xFF7CA188);
  static Color get expenseLight => _isDark
      ? const Color(0xFF1F2C24)
      : const Color(0xFFE9F0E8);
  /// 提示 — 沙色
  static const Color warning      = Color(0xFFE0A86A);
  /// 破坏性操作（删除/清空）的警示红 —— 与收支语义色解耦，别用 expense/income
  static const Color danger       = Color(0xFFC65B4E);
  static Color get warningLight => _isDark
      ? const Color(0xFF2B2118)
      : const Color(0xFFF7ECD9);

  // ── 中性色（Aura 配色表，亮 / 暗双模） ─────────────────────
  /// 页面背景
  static Color get bg => _isDark
      ? const Color(0xFF131313) // surface (dark)
      : const Color(0xFFFAF9F6); // surface (light)
  /// 卡片底色
  static Color get surface => _isDark
      ? const Color(0xFF1C1B1B) // surface-container-low (dark)
      : const Color(0xFFFFFFFF); // surface-container-lowest (light)
  /// 嵌套卡 / chip 底
  static Color get surfaceAlt => _isDark
      ? const Color(0xFF2A2A2A) // surface-container-high
      : const Color(0xFFF4F3F0); // surface-container-low
  static Color get text1 => _isDark
      ? const Color(0xFFE5E2E1) // on-surface (dark)
      : const Color(0xFF1A1C1A); // on-surface (light)
  static Color get text2 => _isDark
      ? const Color(0xFFC1C8C1) // on-surface-variant (dark)
      : const Color(0xFF434843); // on-surface-variant (light)
  static Color get text3 => _isDark
      ? const Color(0xFF8B928C) // outline (dark)
      : const Color(0xFF737973); // outline (light)
  /// 极淡边线（Aura 是"幽灵描边"哲学：能不用就不用）
  static Color get border => _isDark
      ? const Color(0xFF424843) // outline-variant
      : const Color(0xFFE3E2E0); // surface-container-highest

  static bool get _isDark => ThemeService.instance.isDark;

  // ── Aura 专用 ───────────────────────────────────────────────
  /// Aura light primary：Forest Green
  static const Color _auraLightPrimary = Color(0xFF1B3022);
  /// Aura dark primary：Refined Sage
  static const Color _auraDarkPrimary = Color(0xFFA9D0B5);
}

class AppTheme {
  AppTheme._();

  /// 装饰用的 BoxShadow：Aura 风极淡环境阴影（深色模式自动隐藏）
  static List<BoxShadow> ambientShadow({
    double opacity = 0.04,
    double blur = 24,
    Offset offset = const Offset(0, 4),
  }) {
    if (ThemeService.instance.isDark) return const [];
    return [
      BoxShadow(
        color: const Color(0xFF1B3022).withValues(alpha: opacity),
        blurRadius: blur,
        offset: offset,
      ),
    ];
  }

  static ThemeData build() {
    final isDark = ThemeService.instance.isDark;
    final seed = AppColors.primary;

    final scheme = ColorScheme.fromSeed(
      seedColor: seed,
      brightness: isDark ? Brightness.dark : Brightness.light,
      primary: seed,
      onPrimary: AppColors.onPrimary,
      surface: AppColors.surface,
    );

    // Outfit 全套字号 —— 从 DESIGN.md 抄过来的等比缩放
    final textTheme = GoogleFonts.outfitTextTheme(
      ThemeData(brightness: isDark ? Brightness.dark : Brightness.light)
          .textTheme,
    ).apply(
      bodyColor: AppColors.text1,
      displayColor: AppColors.text1,
    ).copyWith(
      displayLarge: GoogleFonts.outfit(
        fontSize: 48, fontWeight: FontWeight.w600, letterSpacing: -0.96,
        height: 56 / 48, color: AppColors.text1,
      ),
      displayMedium: GoogleFonts.outfit(
        fontSize: 36, fontWeight: FontWeight.w600, letterSpacing: -0.36,
        height: 44 / 36, color: AppColors.text1,
      ),
      headlineLarge: GoogleFonts.outfit(
        fontSize: 28, fontWeight: FontWeight.w600,
        height: 36 / 28, color: AppColors.text1,
      ),
      headlineMedium: GoogleFonts.outfit(
        fontSize: 20, fontWeight: FontWeight.w600,
        height: 28 / 20, color: AppColors.text1,
      ),
      titleLarge: GoogleFonts.outfit(
        fontSize: 18, fontWeight: FontWeight.w600,
        color: AppColors.text1,
      ),
      titleMedium: GoogleFonts.outfit(
        fontSize: 16, fontWeight: FontWeight.w600,
        color: AppColors.text1,
      ),
      bodyLarge: GoogleFonts.outfit(
        fontSize: 16, fontWeight: FontWeight.w400,
        height: 24 / 16, color: AppColors.text1,
      ),
      bodyMedium: GoogleFonts.outfit(
        fontSize: 14, fontWeight: FontWeight.w400,
        height: 20 / 14, color: AppColors.text1,
      ),
      bodySmall: GoogleFonts.outfit(
        fontSize: 12, fontWeight: FontWeight.w400,
        height: 16 / 12, color: AppColors.text2,
      ),
      labelLarge: GoogleFonts.outfit(
        fontSize: 14, fontWeight: FontWeight.w600, letterSpacing: 0.7,
        color: AppColors.text1,
      ),
      labelMedium: GoogleFonts.outfit(
        fontSize: 12, fontWeight: FontWeight.w600, letterSpacing: 0.6,
        color: AppColors.text2,
      ),
      labelSmall: GoogleFonts.outfit(
        fontSize: 11, fontWeight: FontWeight.w500, letterSpacing: 0.4,
        color: AppColors.text3,
      ),
    );

    return ThemeData(
      useMaterial3: true,
      brightness: isDark ? Brightness.dark : Brightness.light,
      colorScheme: scheme,
      scaffoldBackgroundColor: AppColors.bg,
      // 全局 Outfit
      textTheme: textTheme,
      primaryTextTheme: textTheme,
      // 滚动时不染色（Aura 风：surface 不要被 tint）
      appBarTheme: AppBarTheme(
        backgroundColor: AppColors.bg,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        systemOverlayStyle:
            isDark ? SystemUiOverlayStyle.light : SystemUiOverlayStyle.dark,
        centerTitle: false,
        titleSpacing: 20,
        titleTextStyle: GoogleFonts.outfit(
          color: AppColors.primary,
          fontSize: 21,
          fontWeight: FontWeight.w700,
          letterSpacing: -0.4,
        ),
        iconTheme: IconThemeData(color: AppColors.primary, size: 22),
      ),
      // 卡片：大圆角 + 极淡描边，无固定阴影（用 ambientShadow 自己加）
      cardTheme: CardThemeData(
        color: AppColors.surface,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: BorderSide(color: AppColors.border, width: 0.6),
        ),
        margin: EdgeInsets.zero,
      ),
      // 输入框：填充式 + 圆角 + 聚焦时深色描边
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: AppColors.surfaceAlt,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide.none,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: AppColors.primary, width: 1.4),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: AppColors.expense, width: 1.2),
        ),
        hintStyle:
            GoogleFonts.outfit(color: AppColors.text3, fontSize: 14),
        labelStyle:
            GoogleFonts.outfit(color: AppColors.text2, fontSize: 14),
      ),
      // 主按钮：森林绿 / sage，pill 形状（高度 52）
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.primary,
          foregroundColor: AppColors.onPrimary,
          minimumSize: const Size(double.infinity, 52),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          elevation: 0,
          textStyle: GoogleFonts.outfit(
            fontSize: 15,
            fontWeight: FontWeight.w600,
            letterSpacing: 0.2,
          ),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: AppColors.primary,
          foregroundColor: AppColors.onPrimary,
          minimumSize: const Size(0, 48),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          textStyle: GoogleFonts.outfit(
            fontSize: 14, fontWeight: FontWeight.w600, letterSpacing: 0.2,
          ),
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: AppColors.text1,
          side: BorderSide(color: AppColors.border, width: 1),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          minimumSize: const Size(0, 48),
          padding: const EdgeInsets.symmetric(horizontal: 20),
          textStyle: GoogleFonts.outfit(fontSize: 14, fontWeight: FontWeight.w500),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: AppColors.primary,
          textStyle: GoogleFonts.outfit(fontSize: 14, fontWeight: FontWeight.w500),
        ),
      ),
      // FAB：用主色，提升至 8px 阴影做"漂浮感"
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        backgroundColor: AppColors.primary,
        foregroundColor: AppColors.onPrimary,
        elevation: 8,
        shape: const CircleBorder(),
      ),
      dividerTheme:
          DividerThemeData(color: AppColors.border, thickness: 0.6, space: 0.6),
      // chips：pill 形状，未选 surfaceAlt 底，选中 primaryLight 底
      chipTheme: ChipThemeData(
        backgroundColor: AppColors.surfaceAlt,
        selectedColor: isDark
            ? AppColors.primary.withValues(alpha: 0.20)
            : AppColors.primaryLight,
        labelStyle: GoogleFonts.outfit(
          fontSize: 13, fontWeight: FontWeight.w500, color: AppColors.text1,
        ),
        secondaryLabelStyle: GoogleFonts.outfit(
          fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.primary,
        ),
        side: BorderSide.none,
        shape: const StadiumBorder(),
        showCheckmark: false,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: AppColors.surface,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
        ),
      ),
      popupMenuTheme: PopupMenuThemeData(
        color: AppColors.surface,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(color: AppColors.border, width: 0.6),
        ),
        textStyle: GoogleFonts.outfit(color: AppColors.text1, fontSize: 14),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: AppColors.surface,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        titleTextStyle: GoogleFonts.outfit(
          fontSize: 18, fontWeight: FontWeight.w600, color: AppColors.text1,
        ),
        contentTextStyle: GoogleFonts.outfit(
          fontSize: 14, height: 1.5, color: AppColors.text2,
        ),
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: AppColors.text1,
        contentTextStyle: GoogleFonts.outfit(
          color: AppColors.bg, fontSize: 14, fontWeight: FontWeight.w500,
        ),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
      // 进度条：sage 主色 + 极淡轨道
      progressIndicatorTheme: ProgressIndicatorThemeData(
        color: AppColors.primary,
        linearTrackColor: AppColors.surfaceAlt,
        linearMinHeight: 6,
      ),
      // Tab：与 NavigationBar 用同一调性
      tabBarTheme: TabBarThemeData(
        labelColor: AppColors.primary,
        unselectedLabelColor: AppColors.text3,
        labelStyle: GoogleFonts.outfit(
          fontSize: 14, fontWeight: FontWeight.w600,
        ),
        unselectedLabelStyle: GoogleFonts.outfit(
          fontSize: 14, fontWeight: FontWeight.w500,
        ),
        indicator: UnderlineTabIndicator(
          borderSide: BorderSide(color: AppColors.primary, width: 2.5),
          insets: const EdgeInsets.symmetric(horizontal: 24),
        ),
        dividerColor: Colors.transparent,
      ),
    );
  }
}
