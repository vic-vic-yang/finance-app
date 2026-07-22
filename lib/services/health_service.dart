import 'dart:async';
import 'dart:convert';
import 'dart:io' show HttpClient;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:http/http.dart' as http;
import 'package:http/io_client.dart';

import 'api_service.dart' show ApiException;
import 'auth_service.dart';

/// 财务健康评分 API（独立 service，模式复刻 reconcile_service.dart：
/// 长连接 client 复用 TLS、token 鉴权头、统一超时与非 2xx 抛 [ApiException]）。
class HealthService {
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

  /// GET /api/health/score
  /// 返回 { score, grade, dimensions: [{key,label,score,weight,headline,advice}], computedAt }
  static Future<HealthScore> getScore() async {
    final uri = Uri.parse('$_baseUrl/health/score');
    final res = await _client
        .get(uri, headers: await _headers())
        .timeout(_kRequestTimeout);
    final body = _decode(res);
    return HealthScore.fromJson(
      (body is Map) ? body.cast<String, dynamic>() : <String, dynamic>{},
    );
  }
}

/// 单个维度得分
class HealthDimension {
  HealthDimension({
    required this.key,
    required this.label,
    required this.score,
    required this.weight,
    required this.headline,
    required this.advice,
  });

  final String key;
  final String label;
  final int score;
  final int weight;
  final String headline;
  final String advice;

  factory HealthDimension.fromJson(Map<String, dynamic> j) => HealthDimension(
        key: j['key'] as String? ?? '',
        label: j['label'] as String? ?? '',
        score: (j['score'] as num? ?? 0).round(),
        weight: (j['weight'] as num? ?? 0).round(),
        headline: j['headline'] as String? ?? '',
        advice: j['advice'] as String? ?? '',
      );
}

/// 健康评分总结果
class HealthScore {
  HealthScore({
    required this.score,
    required this.grade,
    required this.dimensions,
    this.computedAt,
  });

  final int score;
  final String grade;
  final List<HealthDimension> dimensions;
  final DateTime? computedAt;

  factory HealthScore.fromJson(Map<String, dynamic> j) => HealthScore(
        score: (j['score'] as num? ?? 0).round(),
        grade: j['grade'] as String? ?? '-',
        dimensions: (j['dimensions'] as List? ?? [])
            .map((d) => HealthDimension.fromJson(d as Map<String, dynamic>))
            .toList(),
        computedAt: DateTime.tryParse(j['computedAt'] as String? ?? ''),
      );
}
