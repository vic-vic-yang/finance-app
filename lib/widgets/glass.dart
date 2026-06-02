import 'dart:ui';
import 'package:flutter/material.dart';
import '../core/theme.dart';
import '../core/theme_service.dart';
import '../core/refresh_bus.dart';
import '../services/auth_service.dart';

/// ======================================================================
/// Aura Finance · 玻璃拟态组件库
/// ======================================================================
///
/// 来源：/ui/light/DESIGN.md「Elevation & Depth」+ /ui/dark/DESIGN.md
///
///   - 卡片必须有 backdrop blur + 极淡环境阴影，没有硬边框（用幽灵描边）
///   - 半透明白 rgba(255,255,255,0.6) + blur(20px)，让背景光影透上来
///   - 沉浸式光影背景（AuraBackground）让元素像「漂浮」在画布上
///
/// 用法：把页面 Scaffold 包到 [AuraBackground] 里（或直接当 body 背景），
/// 卡片/面板用 [GlassCard]，底部导航用 [GlassNavBar]。

bool get _isDark => ThemeService.instance.isDark;

/// 沉浸式光影背景：底色 + 若干柔和的彩色光斑（径向渐变），
/// 模拟「自然光打在 UI 上」的质感。放在 Scaffold 最底层。
class AuraBackground extends StatelessWidget {
  const AuraBackground({super.key, required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final dark = _isDark;
    final primary = AppColors.primary;
    return DecoratedBox(
      decoration: BoxDecoration(color: AppColors.bg),
      child: Stack(
        children: [
          // 左上：主色光晕
          Positioned(
            top: -140,
            left: -120,
            child: _Blob(
              size: 360,
              color: primary.withOpacity(dark ? 0.18 : 0.10),
            ),
          ),
          // 右上：苔绿/sage 光晕
          Positioned(
            top: -60,
            right: -110,
            child: _Blob(
              size: 300,
              color: AppColors.income.withOpacity(dark ? 0.16 : 0.12),
            ),
          ),
          // 右下：暖色微光
          Positioned(
            bottom: -160,
            right: -80,
            child: _Blob(
              size: 340,
              color: AppColors.warning.withOpacity(dark ? 0.10 : 0.08),
            ),
          ),
          child,
        ],
      ),
    );
  }
}

/// 单个柔和光斑
class _Blob extends StatelessWidget {
  const _Blob({required this.size, required this.color});
  final double size;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: RadialGradient(
          colors: [color, color.withOpacity(0)],
        ),
      ),
    );
  }
}

/// 玻璃卡片：BackdropFilter 模糊 + 半透明填充 + 幽灵描边 + 环境阴影。
///
/// 注意：BackdropFilter 模糊的是「卡片背后」的内容，所以只有放在
/// [AuraBackground]（或别的有内容/光影的层）之上时玻璃感最明显。
class GlassCard extends StatelessWidget {
  const GlassCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(20),
    this.radius = 20,
    this.blur = 18,
    this.onTap,
    this.margin,
    this.opacity,
    this.tint,
    this.showShadow = true,
    this.border = true,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final double radius;
  final double blur;
  final VoidCallback? onTap;
  final EdgeInsetsGeometry? margin;

  /// 玻璃填充不透明度（默认 light 0.62 / dark 0.42）
  final double? opacity;

  /// 玻璃叠色（默认白 / 深灰）
  final Color? tint;
  final bool showShadow;
  final bool border;

  @override
  Widget build(BuildContext context) {
    final dark = _isDark;
    final fillBase = tint ?? (dark ? const Color(0xFF22211F) : Colors.white);
    final fillOpacity = opacity ?? (dark ? 0.42 : 0.62);
    final br = BorderRadius.circular(radius);

    Widget content = ClipRRect(
      borderRadius: br,
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: blur, sigmaY: blur),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: fillBase.withOpacity(fillOpacity),
            borderRadius: br,
            border: border
                ? Border.all(
                    color: dark
                        ? Colors.white.withOpacity(0.08)
                        : Colors.white.withOpacity(0.55),
                    width: 1,
                  )
                : null,
          ),
          child: Padding(padding: padding, child: child),
        ),
      ),
    );

    if (onTap != null) {
      content = Material(
        color: Colors.transparent,
        borderRadius: br,
        child: InkWell(
          onTap: onTap,
          borderRadius: br,
          child: content,
        ),
      );
    }

    return Container(
      margin: margin,
      decoration: BoxDecoration(
        borderRadius: br,
        boxShadow: showShadow
            ? AppTheme.ambientShadow(
                opacity: dark ? 0.0 : 0.05,
                blur: 36,
                offset: const Offset(0, 12),
              )
            : null,
      ),
      child: content,
    );
  }
}

/// 浮动玻璃底部导航胶囊。FAB 居中嵌在缺口里。
class GlassNavBar extends StatelessWidget {
  const GlassNavBar({
    super.key,
    required this.index,
    required this.labels,
    required this.icons,
    required this.activeIcons,
    required this.onTap,
    this.fabGap = 64,
  });

  final int index;
  final List<String> labels;
  final List<IconData> icons;
  final List<IconData> activeIcons;
  final ValueChanged<int> onTap;
  final double fabGap;

  @override
  Widget build(BuildContext context) {
    final dark = _isDark;
    final br = BorderRadius.circular(30);
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(18, 0, 18, 14),
        child: Container(
          decoration: BoxDecoration(
            borderRadius: br,
            boxShadow: AppTheme.ambientShadow(
              opacity: dark ? 0.0 : 0.10,
              blur: 30,
              offset: const Offset(0, 12),
            ),
          ),
          child: ClipRRect(
            borderRadius: br,
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 22, sigmaY: 22),
              child: Container(
                height: 64,
                decoration: BoxDecoration(
                  color: (dark ? const Color(0xFF1A1A1A) : Colors.white)
                      .withOpacity(dark ? 0.55 : 0.70),
                  borderRadius: br,
                  border: Border.all(
                    color: dark
                        ? Colors.white.withOpacity(0.10)
                        : Colors.white.withOpacity(0.60),
                    width: 1,
                  ),
                ),
                child: Row(
                  children: [
                    _item(0),
                    _item(1),
                    SizedBox(width: fabGap),
                    _item(2),
                    _item(3),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _item(int i) {
    final selected = index == i;
    final color = selected ? AppColors.primary : AppColors.text3;
    return Expanded(
      child: InkWell(
        onTap: () => onTap(i),
        splashColor: Colors.transparent,
        highlightColor: Colors.transparent,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            AnimatedContainer(
              duration: const Duration(milliseconds: 220),
              curve: Curves.easeOut,
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
              decoration: BoxDecoration(
                color: selected
                    ? AppColors.primary.withOpacity(_isDark ? 0.18 : 0.10)
                    : Colors.transparent,
                borderRadius: BorderRadius.circular(14),
              ),
              child: Icon(
                selected ? activeIcons[i] : icons[i],
                size: 22,
                color: color,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              labels[i],
              style: TextStyle(
                fontSize: 10.5,
                fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
                color: color,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 圆形用户头像 —— 顶部 header 左上角入口，点击进「我的」。
/// 自己异步读取用户名/昵称首字母，并监听 refreshBus 自动刷新。
class ProfileAvatar extends StatefulWidget {
  const ProfileAvatar({super.key, required this.onTap, this.size = 38});
  final VoidCallback onTap;
  final double size;

  @override
  State<ProfileAvatar> createState() => _ProfileAvatarState();
}

class _ProfileAvatarState extends State<ProfileAvatar> {
  String _initial = '';

  @override
  void initState() {
    super.initState();
    refreshBus.addListener(_load);
    _load();
  }

  @override
  void dispose() {
    refreshBus.removeListener(_load);
    super.dispose();
  }

  Future<void> _load() async {
    final user = await AuthService.getUser();
    final nick = (user?['nickname'] as String?)?.trim() ?? '';
    final name = nick.isNotEmpty ? nick : (user?['username'] as String? ?? '');
    if (!mounted) return;
    setState(() =>
        _initial = name.isEmpty ? '' : name.substring(0, 1).toUpperCase());
  }

  @override
  Widget build(BuildContext context) {
    final fg = AppColors.onPrimaryGradient;
    return GestureDetector(
      onTap: widget.onTap,
      child: Container(
        width: widget.size,
        height: widget.size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: LinearGradient(
            colors: AppColors.primaryGradient,
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          border: Border.all(
            color: Colors.white.withOpacity(_isDark ? 0.14 : 0.65),
            width: 1.5,
          ),
          boxShadow: AppTheme.ambientShadow(
            opacity: 0.20,
            blur: 14,
            offset: const Offset(0, 5),
          ),
        ),
        alignment: Alignment.center,
        child: _initial.isEmpty
            ? Icon(Icons.person_rounded, size: widget.size * 0.52, color: fg)
            : Text(
                _initial,
                style: TextStyle(
                  color: fg,
                  fontSize: widget.size * 0.42,
                  fontWeight: FontWeight.w700,
                ),
              ),
      ),
    );
  }
}

/// 渐变圆形「AI」按钮 —— 替代旧的 🤖 emoji，统一的 AI 入口图标。
class AiButton extends StatelessWidget {
  const AiButton({
    super.key,
    required this.onTap,
    this.tooltip = 'AI 助手',
    this.size = 38,
  });
  final VoidCallback onTap;
  final String tooltip;
  final double size;

  @override
  Widget build(BuildContext context) {
    final br = BorderRadius.circular(size);
    return Tooltip(
      message: tooltip,
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          width: size,
          height: size,
          decoration: BoxDecoration(
            borderRadius: br,
            boxShadow: AppTheme.ambientShadow(
              opacity: 0.16,
              blur: 14,
              offset: const Offset(0, 5),
            ),
          ),
          child: ClipRRect(
            borderRadius: br,
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
              child: Container(
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: (_isDark ? Colors.white : Colors.white)
                      .withOpacity(_isDark ? 0.08 : 0.72),
                  border: Border.all(
                    color: Colors.white.withOpacity(_isDark ? 0.12 : 0.6),
                    width: 1,
                  ),
                ),
                alignment: Alignment.center,
                child: Icon(
                  Icons.auto_awesome_rounded,
                  size: size * 0.5,
                  color: AppColors.primary,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// 统一的玻璃风格 AppBar：透明底、可选左上角头像、primary 色标题。
/// 顶级 tab 页传 [avatarTap] 显示头像；二级页面留空 → 用默认返回箭头。
class AuraAppBar extends StatelessWidget implements PreferredSizeWidget {
  const AuraAppBar({
    super.key,
    this.title,
    this.titleWidget,
    this.avatarTap,
    this.actions,
    this.bottom,
    this.toolbarHeight = 64,
  });

  final String? title;
  final Widget? titleWidget;
  final VoidCallback? avatarTap;
  final List<Widget>? actions;
  final PreferredSizeWidget? bottom;
  final double toolbarHeight;

  @override
  Size get preferredSize =>
      Size.fromHeight(toolbarHeight + (bottom?.preferredSize.height ?? 0));

  @override
  Widget build(BuildContext context) {
    final hasAvatar = avatarTap != null;
    return AppBar(
      backgroundColor: Colors.transparent,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      scrolledUnderElevation: 0,
      toolbarHeight: toolbarHeight,
      titleSpacing: hasAvatar ? 12 : 20,
      leadingWidth: hasAvatar ? 64 : null,
      leading: hasAvatar
          ? Padding(
              padding: const EdgeInsets.only(left: 20),
              child: Center(child: ProfileAvatar(onTap: avatarTap!)),
            )
          : null,
      title: titleWidget ??
          (title != null
              ? Text(
                  title!,
                  style: TextStyle(
                    color: AppColors.primary,
                    fontSize: 22,
                    fontWeight: FontWeight.w700,
                    letterSpacing: -0.4,
                  ),
                )
              : null),
      actions: actions,
      bottom: bottom,
    );
  }
}

/// 磨砂玻璃 header 背景：滚动内容从下方经过时被模糊 + 半透明底色覆盖，
/// 避免 pinned header 透明导致「穿透看见下面内容」。
class _GlassHeaderBg extends StatelessWidget {
  const _GlassHeaderBg();
  @override
  Widget build(BuildContext context) {
    final dark = _isDark;
    return ClipRect(
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
        child: Container(
          color: AppColors.bg.withOpacity(dark ? 0.60 : 0.72),
        ),
      ),
    );
  }
}

/// [AuraAppBar] 的可滚动（SliverAppBar）版本，给首页这种 CustomScrollView
/// 用：pinned 钉顶 + 磨砂玻璃背景，滚动内容不会穿透到 header 上。
///
/// 视觉与 [AuraAppBar] 完全一致：左头像、primary 标题、64 高。
class AuraSliverAppBar extends StatelessWidget {
  const AuraSliverAppBar({
    super.key,
    this.title,
    this.titleWidget,
    this.avatarTap,
    this.actions,
    this.toolbarHeight = 64,
  });

  final String? title;
  final Widget? titleWidget;
  final VoidCallback? avatarTap;
  final List<Widget>? actions;
  final double toolbarHeight;

  @override
  Widget build(BuildContext context) {
    final hasAvatar = avatarTap != null;
    return SliverAppBar(
      pinned: true,
      backgroundColor: Colors.transparent,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      scrolledUnderElevation: 0,
      toolbarHeight: toolbarHeight,
      titleSpacing: hasAvatar ? 12 : 20,
      leadingWidth: hasAvatar ? 64 : null,
      leading: hasAvatar
          ? Padding(
              padding: const EdgeInsets.only(left: 20),
              child: Center(child: ProfileAvatar(onTap: avatarTap!)),
            )
          : null,
      title: titleWidget ??
          (title != null
              ? Text(
                  title!,
                  style: TextStyle(
                    color: AppColors.primary,
                    fontSize: 22,
                    fontWeight: FontWeight.w700,
                    letterSpacing: -0.4,
                  ),
                )
              : null),
      actions: actions,
      flexibleSpace: const _GlassHeaderBg(),
    );
  }
}
