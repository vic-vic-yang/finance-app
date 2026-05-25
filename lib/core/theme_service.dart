import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 主题色配置 —— 每套主题用一个种子色生成 ColorScheme
class ThemePalette {
  final String name;
  final String emoji;
  final Color seed;
  /// 单色模式：primary 不固定，跟随亮/暗模式取 text1（shadcn 风格）
  final bool isMono;
  const ThemePalette(this.name, this.emoji, this.seed, {this.isMono = false});
}

class ThemeService {
  ThemeService._();
  static final ThemeService instance = ThemeService._();

  /// 8 套主题（默认第 0 个：无色 shadcn 风格）
  /// 索引存 SharedPreferences，**改顺序会让老用户主题错位**，慎重
  static const List<ThemePalette> palettes = [
    ThemePalette('无色', '⚫', Color(0xFF101828), isMono: true),
    ThemePalette('星耀紫', '💜', Color(0xFF635BFF)),
    ThemePalette('莱姆绿', '🟢', Color(0xFF6ECC54)),
    ThemePalette('提香红', '🍅', Color(0xFFD34947)),
    ThemePalette('勃艮蒂红', '🍷', Color(0xFF470125)),
    ThemePalette('马尔斯绿', '🌲', Color(0xFF018B8D)),
    ThemePalette('克莱因蓝', '🌊', Color(0xFF002F7A)),
    ThemePalette('蒂芙尼蓝', '💎', Color(0xFF71E2D1)),
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
