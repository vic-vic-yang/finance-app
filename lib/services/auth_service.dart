import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import 'llm_config_service.dart';

class AuthService {
  static const String _tokenKey = 'auth_token';
  static const String _userKey = 'auth_user';

  static Future<void> saveAuth(String token, Map<String, dynamic> user) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_tokenKey, token);
    await prefs.setString(_userKey, jsonEncode(user));
    // 加载该账号名下的 AI 模型配置（按账号隔离存储）
    await LlmConfigService.instance.load(user['id'] as String?);
  }

  static Future<String?> getToken() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_tokenKey);
  }

  static Future<Map<String, dynamic>?> getUser() async {
    final prefs = await SharedPreferences.getInstance();
    final userStr = prefs.getString(_userKey);
    if (userStr == null) return null;
    return jsonDecode(userStr) as Map<String, dynamic>;
  }

  static Future<void> saveUser(Map<String, dynamic> user) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_userKey, jsonEncode(user));
  }

  static Future<void> logout() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_tokenKey);
    await prefs.remove(_userKey);
    // 只清内存态：AI 模型 Key 按账号留在本机安全存储，
    // 同账号重新登录自动恢复，也不会泄露给同设备的其他账号
    await LlmConfigService.instance.unload();
  }

  static Future<bool> isLoggedIn() async {
    final token = await getToken();
    return token != null;
  }

  /// 当前活动账本 id（加密 / 解密用）
  static Future<String?> getCurrentLedgerId() async {
    final user = await getUser();
    return user?['currentLedgerId'] as String?;
  }
}
