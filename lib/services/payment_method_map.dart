import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';

/// 每账本一份「归一化付款方式 → accountId」的记忆。
class PaymentMethodMap {
  static String _key(String ledgerId) => 'pm_map_$ledgerId';

  static Future<Map<String, String>> load(String ledgerId) async {
    final sp = await SharedPreferences.getInstance();
    final raw = sp.getString(_key(ledgerId));
    if (raw == null || raw.isEmpty) return {};
    try {
      final m = jsonDecode(raw) as Map<String, dynamic>;
      return m.map((k, v) => MapEntry(k, v as String));
    } catch (_) {
      return {};
    }
  }

  static Future<void> putAll(
    String ledgerId,
    Map<String, String> entries,
  ) async {
    if (entries.isEmpty) return;
    final sp = await SharedPreferences.getInstance();
    final cur = await load(ledgerId);
    cur.addAll(entries);
    await sp.setString(_key(ledgerId), jsonEncode(cur));
  }
}
