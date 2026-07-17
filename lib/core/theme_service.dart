import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 主题色配置 —— 每套主题用一个种子色生成 ColorScheme
class ThemePalette {
  final String name;
  final String emoji;
  final Color seed;
  /// 单色模式：primary 不固定，跟随亮/暗模式取 text1（shadcn 风格）
  final bool isMono;
  /// Aura Finance 模式：light 用 Forest Green，dark 用 Sage，自带"Quiet Luxury"配色
  final bool isAura;
  const ThemePalette(this.name, this.emoji, this.seed,
      {this.isMono = false, this.isAura = false});
}

class ThemeService {
  ThemeService._();
  static final ThemeService instance = ThemeService._();

  /// 10 套主题（默认第 0 个：Aura Finance "Quiet Luxury"）
  /// 索引存 SharedPreferences，**改顺序会让老用户主题错位**，慎重
  /// —— Aura 加在索引 0，把原有 8 套整体后移一位。已有用户的索引会跟着错位一次，
  ///    但因为整体观感升级了，这是有意为之；老用户首次启动只会看到"主题更新"
  ///    （除非他们改回偏好）。
  static const List<ThemePalette> palettes = [
    ThemePalette('Aura · 雅致', '🌿', Color(0xFF1B3022), isAura: true),
    // 原「无色」槽位换成蔷薇粉（占同一索引，老用户不错位；选过无色的会看到粉）
    ThemePalette('蔷薇粉', '🌸', Color(0xFFD9698E)),
    ThemePalette('星耀紫', '💜', Color(0xFF635BFF)),
    ThemePalette('莱姆绿', '🟢', Color(0xFF6ECC54)),
    ThemePalette('提香红', '🍅', Color(0xFFD34947)),
    ThemePalette('勃艮蒂红', '🍷', Color(0xFF470125)),
    ThemePalette('马尔斯绿', '🌲', Color(0xFF018B8D)),
    ThemePalette('克莱因蓝', '🌊', Color(0xFF002F7A)),
    ThemePalette('蒂芙尼蓝', '💎', Color(0xFF71E2D1)),
    ThemePalette('暖阳橙', '🧡', Color(0xFFE07B39)),
  ];

  static const _kPaletteIndex = 'theme_palette_index';
  static const _kIsDark = 'theme_is_dark';

  /// 监听这个：值变化时整个 app 自动重建
  final ValueNotifier<int> revision = ValueNotifier<int>(0);

  int _paletteIndex = 0;
  bool _isDark = false;

  int get paletteIndex => _paletteIndex;
  bool get isDark => _isDark;
  ThemePalette get palette => palettes[_paletteIndex];
  Brightness get brightness => _isDark ? Brightness.dark : Brightness.light;

  /// 启动时调用一次，从本地读取上次的设置
  Future<void> load() async {
    final sp = await SharedPreferences.getInstance();
    _paletteIndex = sp.getInt(_kPaletteIndex) ?? 0;
    _isDark = sp.getBool(_kIsDark) ?? false;
    revision.value++;
  }

  Future<void> setPalette(int index) async {
    if (index < 0 || index >= palettes.length) return;
    _paletteIndex = index;
    revision.value++;
    final sp = await SharedPreferences.getInstance();
    await sp.setInt(_kPaletteIndex, index);
  }

  Future<void> setDark(bool dark) async {
    _isDark = dark;
    revision.value++;
    final sp = await SharedPreferences.getInstance();
    await sp.setBool(_kIsDark, dark);
  }
}
