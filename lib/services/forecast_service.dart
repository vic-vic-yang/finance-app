import 'dart:convert';
import 'dart:io' show HttpClient;
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:http/http.dart' as http;
import 'package:http/io_client.dart';
import 'api_service.dart' show ApiException;
import 'auth_service.dart';

/// 现金流预测（GET /api/forecast）
///
/// 独立 service 文件：复刻 api_service 的长连接 client、token 鉴权头、
/// baseURL 模式（api_service.dart 是共享文件不在本任务改动范围内，
/// 新端点各自建文件；错误类型直接复用 [ApiException]）。
class ForecastService {
  // 与 api_service 保持一致：公网走 Cloudflare Tunnel，Web 调试走 localhost
  static const String _publicHost = 'https://finance.equitick.top/api';

  static const String baseUrl =
      kIsWeb ? 'http://localhost:3000/api' : _publicHost;

  /// 长存 Client：连接保活 + TLS 复用（同 api_service）
  static final http.Client _client = () {
    if (kIsWeb) return http.Client();
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

  /// 拉取当前账本的现金流预测
  static Future<CashflowForecast> getForecast() async {
    final uri = Uri.parse('$baseUrl/forecast');
    final res = await _client
        .get(uri, headers: await _headers())
        .timeout(_kRequestTimeout);
    dynamic body;
    try {
      body = res.body.isEmpty ? null : jsonDecode(res.body);
    } catch (_) {
      body = null;
    }
    if (res.statusCode >= 200 && res.statusCode < 300 && body is Map) {
      return CashflowForecast.fromJson(body.cast<String, dynamic>());
    }
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
}

// ═══════════════════════════════════════════════════════════════
// 响应模型
// ═══════════════════════════════════════════════════════════════

class CashflowForecast {
  final DateTime generatedAt;
  final MonthEndNetWorth monthEnd;
  final List<UpcomingPayment> upcoming30;
  final ExpensePaceInfo pace;
  final List<GoalForecastItem> goals;

  CashflowForecast({
    required this.generatedAt,
    required this.monthEnd,
    required this.upcoming30,
    required this.pace,
    required this.goals,
  });

  factory CashflowForecast.fromJson(Map<String, dynamic> j) =>
      CashflowForecast(
        generatedAt: DateTime.parse(j['generatedAt'] as String),
        monthEnd: MonthEndNetWorth.fromJson(
            (j['monthEndNetWorth'] as Map).cast<String, dynamic>()),
        upcoming30: ((j['upcoming30'] as List?) ?? [])
            .map((e) =>
                UpcomingPayment.fromJson((e as Map).cast<String, dynamic>()))
            .toList(),
        pace: ExpensePaceInfo.fromJson(
            (j['expensePace'] as Map).cast<String, dynamic>()),
        goals: ((j['goalForecast'] as List?) ?? [])
            .map((e) =>
                GoalForecastItem.fromJson((e as Map).cast<String, dynamic>()))
            .toList(),
      );
}

/// 月末净资产预测
class MonthEndNetWorth {
  /// 当前账户合计（可见账户）
  final double current;

  /// 月末预测值
  final double projected;

  /// 近 30 日日均净流入
  final double avgDailyNetInflow;

  /// 本月剩余天数（不含今天）
  final int remainingDays;
  final int daysInMonth;

  /// 本月剩余周期账单净额（支出减 / 收入加）
  final double remainingRecurringNet;

  MonthEndNetWorth({
    required this.current,
    required this.projected,
    required this.avgDailyNetInflow,
    required this.remainingDays,
    required this.daysInMonth,
    required this.remainingRecurringNet,
  });

  factory MonthEndNetWorth.fromJson(Map<String, dynamic> j) =>
      MonthEndNetWorth(
        current: (j['current'] as num).toDouble(),
        projected: (j['projected'] as num).toDouble(),
        avgDailyNetInflow: (j['avgDailyNetInflow'] as num).toDouble(),
        remainingDays: (j['remainingDays'] as num).toInt(),
        daysInMonth: (j['daysInMonth'] as num).toInt(),
        remainingRecurringNet:
            (j['remainingRecurringNet'] as num).toDouble(),
      );
}

/// 未来 30 天周期扣款条目（名称需客户端用账本 DEK 解 noteCipher）
class UpcomingPayment {
  final String id;
  final String categoryId;
  final String accountId;
  final String type; // income / expense
  final double amount;
  final DateTime nextDate;
  final String? noteCipher;
  final int? noteDekVer;
  final String cycleType;
  final int cycleDay;

  UpcomingPayment({
    required this.id,
    required this.categoryId,
    required this.accountId,
    required this.type,
    required this.amount,
    required this.nextDate,
    this.noteCipher,
    this.noteDekVer,
    required this.cycleType,
    required this.cycleDay,
  });

  bool get isIncome => type == 'income';

  factory UpcomingPayment.fromJson(Map<String, dynamic> j) => UpcomingPayment(
        id: j['id'] as String,
        categoryId: j['categoryId'] as String,
        accountId: j['accountId'] as String,
        type: (j['type'] as String?) ?? 'expense',
        amount: (j['amount'] as num).toDouble(),
        nextDate: DateTime.parse(j['nextDate'] as String),
        noteCipher: j['noteCipher'] as String?,
        noteDekVer: (j['noteDekVer'] as num?)?.toInt(),
        cycleType: (j['cycleType'] as String?) ?? 'monthly',
        cycleDay: (j['cycleDay'] as num?)?.toInt() ?? 1,
      );
}

/// 支出速率与超支预警
class ExpensePaceInfo {
  /// 本月至今支出
  final double monthToDateExpense;

  /// 上月同期支出
  final double lastMonthSamePeriodExpense;

  /// 本月已过天数（含今天）
  final int daysElapsed;
  final int daysInMonth;

  /// 当月总预算（可空）
  final double? monthlyBudget;

  /// 按当前速率外推的当月总支出
  final double projectedMonthExpense;

  /// 有预算且外推支出 > 预算
  final bool overspendRisk;

  ExpensePaceInfo({
    required this.monthToDateExpense,
    required this.lastMonthSamePeriodExpense,
    required this.daysElapsed,
    required this.daysInMonth,
    this.monthlyBudget,
    required this.projectedMonthExpense,
    required this.overspendRisk,
  });

  factory ExpensePaceInfo.fromJson(Map<String, dynamic> j) => ExpensePaceInfo(
        monthToDateExpense: (j['monthToDateExpense'] as num).toDouble(),
        lastMonthSamePeriodExpense:
            (j['lastMonthSamePeriodExpense'] as num).toDouble(),
        daysElapsed: (j['daysElapsed'] as num).toInt(),
        daysInMonth: (j['daysInMonth'] as num).toInt(),
        monthlyBudget: (j['monthlyBudget'] as num?)?.toDouble(),
        projectedMonthExpense:
            (j['projectedMonthExpense'] as num).toDouble(),
        overspendRisk: j['overspendRisk'] as bool? ?? false,
      );
}

/// 目标达成预测（名称需客户端用账本 DEK 解 nameCipher）
class GoalForecastItem {
  final String id;
  final String nameCipher;
  final int nameDekVer;
  final String? icon;
  final String? color;
  final double targetAmount;
  final double currentSaved;
  final double progress;

  /// 近 90 天月均净存入（全账本口径）
  final double monthlyRate;

  /// 预计达成日期（null = 存不下钱，无法估算）
  final DateTime? etaDate;

  GoalForecastItem({
    required this.id,
    required this.nameCipher,
    required this.nameDekVer,
    this.icon,
    this.color,
    required this.targetAmount,
    required this.currentSaved,
    required this.progress,
    required this.monthlyRate,
    this.etaDate,
  });

  factory GoalForecastItem.fromJson(Map<String, dynamic> j) =>
      GoalForecastItem(
        id: j['id'] as String,
        nameCipher: (j['nameCipher'] as String?) ?? '',
        nameDekVer: (j['nameDekVer'] as num?)?.toInt() ?? 1,
        icon: j['icon'] as String?,
        color: j['color'] as String?,
        targetAmount: (j['targetAmount'] as num).toDouble(),
        currentSaved: (j['currentSaved'] as num).toDouble(),
        progress: (j['progress'] as num?)?.toDouble() ?? 0,
        monthlyRate: (j['monthlyRate'] as num?)?.toDouble() ?? 0,
        etaDate: j['etaDate'] != null
            ? DateTime.parse(j['etaDate'] as String)
            : null,
      );
}
