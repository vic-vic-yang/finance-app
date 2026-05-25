import 'package:shared_preferences/shared_preferences.dart';

/// 记账分类的"最近使用"本地缓存。
///
/// - 按 type（income / expense）分两条 list 存
/// - 每条 list 保留最多 [_maxLen] 个分类 id，最新的在前
/// - 仅本地，不上传后端
class RecentsService {
  static const int _maxLen = 9;
  static String _key(String type) => 'recent_categories_$type';

  static Future<List<String>> get(String type) async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getStringList(_key(type)) ?? const [];
  }

  /// 记一笔成功后调用。把 [categoryId] 提到最前；已存在则去重再提。
  static Future<void> add(String type, String categoryId) async {
    if (categoryId.isEmpty) return;
    final prefs = await SharedPreferences.getInstance();
    final cur = prefs.getStringList(_key(type)) ?? const [];
    final next = <String>[
      categoryId,
      ...cur.where((id) => id != categoryId),
    ];
    if (next.length > _maxLen) next.removeRange(_maxLen, next.length);
    await prefs.setStringList(_key(type), next);
  }

  /// 清理（用户删了某分类，或换账本时可调用）
  static Future<void> remove(String type, String categoryId) async {
    final prefs = await SharedPreferences.getInstance();
    final cur = prefs.getStringList(_key(type)) ?? const [];
    if (!cur.contains(categoryId)) return;
    await prefs.setStringList(
      _key(type),
      cur.where((id) => id != categoryId).toList(),
    );
  }
}
