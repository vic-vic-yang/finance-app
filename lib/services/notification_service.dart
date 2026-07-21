import 'dart:async';
import 'dart:convert';
import 'dart:io' show HttpClient;
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:http/http.dart' as http;
import 'package:http/io_client.dart';
import 'api_service.dart';
import 'auth_service.dart';

/// 通知中心 API（/api/notifications/*）。
///
/// 复刻 api_service 的模式：长存长连接 Client（TLS 复用）、统一超时、
/// Bearer token 鉴权头；baseUrl 与 ApiException 直接复用 ApiService 的，
/// 避免两处维护。独立成文件是为了不动 api_service.dart。
class NotificationService {
  /// 单例 HTTP Client —— 与 ApiService 同款连接保活配置
  static final http.Client _client = () {
    if (kIsWeb) return http.Client(); // Web 平台没 dart:io
    final inner = HttpClient()
      ..connectionTimeout = const Duration(seconds: 8)
      ..idleTimeout = const Duration(seconds: 60)
      ..maxConnectionsPerHost = 6;
    return IOClient(inner);
  }();

  static const _kRequestTimeout = Duration(seconds: 20);

  static Future<Map<String, String>> _headers() async {
    final token = await AuthService.getToken();
    return {
      'Content-Type': 'application/json',
      if (token != null) 'Authorization': 'Bearer $token',
    };
  }

  /// 与 ApiService 一致：非 2xx 抛 [ApiException]
  static dynamic _decode(http.Response res) {
    dynamic body;
    try {
      body = res.body.isEmpty ? null : jsonDecode(res.body);
    } catch (_) {
      body = null;
    }
    if (res.statusCode >= 200 && res.statusCode < 300) return body;
    String msg = '请求失败 (${res.statusCode})';
    if (body is Map) {
      final m = body['message'];
      if (m is String && m.trim().isNotEmpty) {
        msg = m;
      } else if (m is List && m.isNotEmpty) {
        msg = m.join('，');
      }
    }
    throw ApiException(res.statusCode, msg);
  }

  /// 通知列表：分页，未读在前。返回 { items, total, page, pageSize, hasMore }
  static Future<Map<String, dynamic>> list({
    int page = 1,
    int pageSize = 20,
  }) async {
    final uri = Uri.parse('${ApiService.baseUrl}/notifications')
        .replace(queryParameters: {
      'page': '$page',
      'pageSize': '$pageSize',
    });
    final res = await _client
        .get(uri, headers: await _headers())
        .timeout(_kRequestTimeout);
    final body = _decode(res);
    return (body is Map) ? body.cast<String, dynamic>() : <String, dynamic>{};
  }

  /// 未读数。返回 { count }
  static Future<Map<String, dynamic>> unreadCount() async {
    final res = await _client
        .get(Uri.parse('${ApiService.baseUrl}/notifications/unread-count'),
            headers: await _headers())
        .timeout(_kRequestTimeout);
    final body = _decode(res);
    return (body is Map) ? body.cast<String, dynamic>() : <String, dynamic>{};
  }

  /// 标记单条已读（幂等）
  static Future<void> markRead(String id) async {
    final res = await _client
        .patch(
          Uri.parse('${ApiService.baseUrl}/notifications/$id/read'),
          headers: await _headers(),
          body: jsonEncode(const {}),
        )
        .timeout(_kRequestTimeout);
    _decode(res);
  }

  /// 全部标记已读
  static Future<void> markAllRead() async {
    final res = await _client
        .post(
          Uri.parse('${ApiService.baseUrl}/notifications/read-all'),
          headers: await _headers(),
          body: jsonEncode(const {}),
        )
        .timeout(_kRequestTimeout);
    _decode(res);
  }
}
