import 'dart:async';
import 'dart:convert';
import 'dart:io' show HttpClient;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:http/http.dart' as http;
import 'package:http/io_client.dart';

import 'api_service.dart' show ApiException;
import 'auth_service.dart';

/// 对账中心 API（独立 service，模式复刻 api_service.dart：
/// 长连接 client 复用 TLS、token 鉴权头、统一超时与非 2xx 抛 [ApiException]）。
class ReconcileService {
  // 公网：手机 -> finance.equitick.top (CF 边缘) -> Tunnel -> 本机 :3000
  static const String _publicHost = 'https://finance.equitick.top/api';

  static const String _baseUrl =
      kIsWeb ? 'http://localhost:3000/api' : _publicHost;

  /// 单例长连接 Client（与 ApiService 同一套保活参数）
  static final http.Client _client = () {
    if (kIsWeb) return http.Client();
    final inner = HttpClient()
      ..connectionTimeout = const Duration(seconds: 8)
      ..idleTimeout = const Duration(seconds: 60)
      ..maxConnectionsPerHost = 6;
    return IOClient(inner);
  }();

  static const _kRequestTimeout = Duration(seconds: 20);

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

  static Future<Map<String, String>> _headers() async {
    final token = await AuthService.getToken();
    return {
      'Content-Type': 'application/json',
      if (token != null) 'Authorization': 'Bearer $token',
    };
  }

  /// GET /api/reconcile/report?month=YYYY-MM
  /// 返回 { month, generatedAt, sections: [{key,title,severity,count,items}] }
  static Future<Map<String, dynamic>> getReport(String month) async {
    final uri = Uri.parse('$_baseUrl/reconcile/report')
        .replace(queryParameters: {'month': month});
    final res = await _client
        .get(uri, headers: await _headers())
        .timeout(_kRequestTimeout);
    final body = _decode(res);
    return (body is Map) ? body.cast<String, dynamic>() : <String, dynamic>{};
  }
}
