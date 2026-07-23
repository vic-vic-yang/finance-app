import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:finance_app/screens/forecast_screen.dart';
import 'package:finance_app/services/forecast_service.dart';

/// 现金流预测页测试：
/// - 展示层状态机（加载 / 错误→空态 / 正常渲染），通过注入 fetcher 隔离网络
/// - 展示口径边界（monthly 月度模式 vs daily 兜底、无预算、无扣款、无目标、
///   扣款到期标签、目标 ETA 三种形态）
/// - 响应模型 fromJson 的缺省容错
void main() {
  // ── 测试数据构造 ──────────────────────────────────────────────
  MonthEndNetWorth monthEnd({
    bool monthly = true,
    double current = 10000,
    double projected = 12000,
  }) =>
      MonthEndNetWorth(
        current: current,
        projected: projected,
        method: monthly ? 'monthly' : 'daily',
        monthsSampled: monthly ? 3 : 0,
        avgDailyNetInflow: 50,
        remainingDays: 10,
        daysInMonth: 30,
        remainingRecurringNet: -800,
        mtdIncome: 9000,
        mtdExpense: 5000,
        avgMonthlyIncome: 9000,
        avgMonthlyExpense: 5200,
        remainingIncome: monthly ? 3000 : null,
        remainingExpense: monthly ? 1000 : null,
      );

  ExpensePaceInfo pace({
    double? budget = 2000,
    bool overspend = false,
    double mtd = 800,
    double projected = 1500,
  }) =>
      ExpensePaceInfo(
        monthToDateExpense: mtd,
        lastMonthSamePeriodExpense: 700,
        daysElapsed: 15,
        daysInMonth: 30,
        monthlyBudget: budget,
        projectedMonthExpense: projected,
        overspendRisk: overspend,
      );

  UpcomingPayment payment(String id, DateTime nextDate,
          {String type = 'expense', double amount = 99}) =>
      UpcomingPayment(
        id: id,
        categoryId: 'c-x',
        accountId: 'a-x',
        type: type,
        amount: amount,
        nextDate: nextDate,
        cycleType: 'monthly',
        cycleDay: nextDate.day,
      );

  GoalForecastItem goal(String id,
          {double progress = 0.5, DateTime? eta, double rate = 500}) =>
      GoalForecastItem(
        id: id,
        nameCipher: '',
        nameDekVer: 1,
        targetAmount: 10000,
        currentSaved: 10000 * progress,
        progress: progress,
        monthlyRate: rate,
        etaDate: eta,
      );

  CashflowForecast forecast({
    MonthEndNetWorth? m,
    List<UpcomingPayment>? upcoming,
    ExpensePaceInfo? p,
    List<GoalForecastItem>? goals,
  }) =>
      CashflowForecast(
        generatedAt: DateTime(2025, 6, 15),
        monthEnd: m ?? monthEnd(),
        upcoming30: upcoming ?? const [],
        pace: p ?? pace(),
        goals: goals ?? const [],
      );

  Widget wrap({
    Future<CashflowForecast> Function()? forecastFetcher,
  }) =>
      MaterialApp(
        home: ForecastScreen(
          forecastFetcher: forecastFetcher ?? () async => forecast(),
          categoriesFetcher: () async => {'categories': const []},
          accountsFetcher: () async => {'accounts': const []},
          userFetcher: () async => null,
        ),
      );

  Future<void> pumpN(WidgetTester tester, [int n = 5]) async {
    for (var i = 0; i < n; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
  }

  /// 拉高测试视口：页面是懒构建的 ListView，目标 / 扣款区块在默认
  /// 800×600 表面下可能在屏外不会被构建，导致 find 失败。
  void bigSurface(WidgetTester tester) {
    tester.view.physicalSize = const Size(1080, 4200);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
  }

  // ── 状态机 ────────────────────────────────────────────────────
  testWidgets('加载态：数据未返回时显示加载指示器', (tester) async {
    final completer = Completer<CashflowForecast>();
    bigSurface(tester);
    await tester.pumpWidget(wrap(forecastFetcher: () => completer.future));
    await tester.pump();

    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(find.text('月末净资产预测'), findsNothing);

    // 收尾，避免悬挂 future
    completer.complete(forecast());
    await pumpN(tester);
  });

  testWidgets('错误态：拉取失败 → 空态兜底 + 失败提示', (tester) async {
    bigSurface(tester);
    await tester.pumpWidget(wrap(
      forecastFetcher: () async => throw Exception('网络错误'),
    ));
    await pumpN(tester);

    expect(find.text('暂时没有预测数据'), findsOneWidget);
    expect(find.textContaining('加载失败'), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsNothing);

    // 让 SnackBar 自然消失，避免测试结束时悬挂 Timer
    await tester.pump(const Duration(seconds: 5));
    await tester.pump();
  });

  // ── 展示口径：monthly vs daily ────────────────────────────────
  testWidgets('月度模式：固定收入口径的明细行与口径说明', (tester) async {
    bigSurface(tester);
    await tester.pumpWidget(wrap(
      forecastFetcher: () async => forecast(m: monthEnd(monthly: true)),
    ));
    await pumpN(tester);

    expect(find.text('月末净资产预测'), findsOneWidget);
    expect(find.text('当前净资产'), findsOneWidget);
    expect(find.text('预计剩余收入（固定收入未到账部分）'), findsOneWidget);
    expect(find.textContaining('预计剩余支出（剩余'), findsOneWidget);
    // 口径说明提到固定收入识别
    expect(find.textContaining('固定收入项'), findsOneWidget);
    // daily 兜底专属行不出现
    expect(find.textContaining('日均净流入'), findsNothing);
  });

  testWidgets('daily 兜底（无完整月历史）：日均口径 + 提示语', (tester) async {
    bigSurface(tester);
    await tester.pumpWidget(wrap(
      forecastFetcher: () async => forecast(m: monthEnd(monthly: false)),
    ));
    await pumpN(tester);

    expect(find.textContaining('日均净流入 × 剩余'), findsOneWidget);
    expect(find.text('本月剩余周期账单净额'), findsOneWidget);
    expect(find.textContaining('暂无完整月历史'), findsOneWidget);
    expect(find.text('预计剩余收入（固定收入未到账部分）'), findsNothing);
  });

  // ── 支出速率：预算 / 超支 / 无预算 ────────────────────────────
  testWidgets('有预算且超支：显示预算行、已用百分比与超支预警', (tester) async {
    bigSurface(tester);
    await tester.pumpWidget(wrap(
      forecastFetcher: () async => forecast(
          p: pace(budget: 2000, mtd: 800, projected: 2500, overspend: true)),
    ));
    await pumpN(tester);

    expect(find.text('当月总预算'), findsOneWidget);
    expect(find.text('已用 40%'), findsOneWidget);
    expect(find.textContaining('本月支出预计超出预算'), findsOneWidget);
  });

  testWidgets('有预算未超支：不显示超支预警', (tester) async {
    bigSurface(tester);
    await tester.pumpWidget(wrap(
      forecastFetcher: () async =>
          forecast(p: pace(budget: 2000, overspend: false)),
    ));
    await pumpN(tester);

    expect(find.text('当月总预算'), findsOneWidget);
    expect(find.textContaining('本月支出预计超出预算'), findsNothing);
  });

  testWidgets('无预算：不显示预算行与已用百分比', (tester) async {
    bigSurface(tester);
    await tester.pumpWidget(wrap(
      forecastFetcher: () async => forecast(p: pace(budget: null)),
    ));
    await pumpN(tester);

    expect(find.text('本月至今支出'), findsOneWidget);
    expect(find.text('当月总预算'), findsNothing);
    expect(find.textContaining('已用'), findsNothing);
    expect(find.textContaining('本月支出预计超出预算'), findsNothing);
  });

  // ── 未来 30 天扣款：空态与到期标签 ────────────────────────────
  testWidgets('无周期扣款：显示引导空态', (tester) async {
    bigSurface(tester);
    await tester.pumpWidget(wrap());
    await pumpN(tester);

    expect(find.text('未来 30 天没有周期扣款'), findsOneWidget);
  });

  testWidgets('扣款到期标签：逾期 / 今天 / 未来 N 天', (tester) async {
    final now = DateTime.now();
    bigSurface(tester);
    await tester.pumpWidget(wrap(
      forecastFetcher: () async => forecast(upcoming: [
        payment('p-overdue', now.subtract(const Duration(days: 3))),
        payment('p-today', now),
        payment('p-future', now.add(const Duration(days: 10))),
        payment('p-income', now.add(const Duration(days: 2)),
            type: 'income', amount: 5000),
      ]),
    ));
    await pumpN(tester);

    expect(find.text('已逾期 3 天'), findsOneWidget);
    expect(find.text('今天到期'), findsOneWidget);
    expect(find.text('10 天后'), findsOneWidget);
    expect(find.text('2 天后'), findsOneWidget);
    // 无备注密文且无分类数据时标题兜底为「未分类」
    expect(find.text('未分类'), findsNWidgets(4));
  });

  // ── 目标达成预测：空态与三种 ETA 形态 ─────────────────────────
  testWidgets('无进行中目标：显示引导空态', (tester) async {
    bigSurface(tester);
    await tester.pumpWidget(wrap());
    await pumpN(tester);

    expect(find.text('没有进行中的储蓄目标'), findsOneWidget);
  });

  testWidgets('目标 ETA：已达成 / 无法估算 / 预计某月达成', (tester) async {
    bigSurface(tester);
    await tester.pumpWidget(wrap(
      forecastFetcher: () async => forecast(goals: [
        goal('g-done', progress: 1.0),
        goal('g-stuck', progress: 0.5, eta: null),
        goal('g-eta', progress: 0.3, eta: DateTime(2026, 3, 1)),
      ]),
    ));
    await pumpN(tester);

    expect(find.textContaining('已达成 🎉'), findsOneWidget);
    expect(find.textContaining('近 90 天净存入不足，暂无法估算'), findsOneWidget);
    expect(find.textContaining('预计 2026年3月 达成'), findsOneWidget);
  });

  // ── 模型 fromJson 容错 ────────────────────────────────────────
  group('CashflowForecast.fromJson', () {
    test('最小 JSON：缺省字段全部有兜底（daily 模式 / 空列表 / null）', () {
      final f = CashflowForecast.fromJson({
        'generatedAt': '2025-06-01T08:00:00.000Z',
        'monthEndNetWorth': {
          'current': 100,
          'projected': 120,
          'avgDailyNetInflow': 1.5,
          'remainingDays': 10,
          'daysInMonth': 30,
          'remainingRecurringNet': -50,
        },
        'expensePace': {
          'monthToDateExpense': 10,
          'lastMonthSamePeriodExpense': 9,
          'daysElapsed': 5,
          'daysInMonth': 30,
          'projectedMonthExpense': 60,
        },
      });

      expect(f.monthEnd.method, 'daily');
      expect(f.monthEnd.isMonthly, isFalse);
      expect(f.monthEnd.monthsSampled, 0);
      expect(f.monthEnd.remainingIncome, isNull);
      expect(f.monthEnd.remainingExpense, isNull);
      expect(f.upcoming30, isEmpty);
      expect(f.goals, isEmpty);
      expect(f.pace.monthlyBudget, isNull);
      expect(f.pace.overspendRisk, isFalse);
    });

    test('完整 JSON：monthly 模式 + 扣款 + 目标（含 ETA）全部解析', () {
      final f = CashflowForecast.fromJson({
        'generatedAt': '2025-06-01T08:00:00.000Z',
        'monthEndNetWorth': {
          'current': 100,
          'projected': 120,
          'method': 'monthly',
          'monthsSampled': 3,
          'avgDailyNetInflow': 1.5,
          'remainingDays': 10,
          'daysInMonth': 30,
          'remainingRecurringNet': -50,
          'remainingIncome': 3000,
          'remainingExpense': 1200,
        },
        'upcoming30': [
          {
            'id': 'p1',
            'categoryId': 'c1',
            'accountId': 'a1',
            'type': 'income',
            'amount': 5000,
            'nextDate': '2025-06-20T00:00:00.000Z',
          },
        ],
        'expensePace': {
          'monthToDateExpense': 10,
          'lastMonthSamePeriodExpense': 9,
          'daysElapsed': 5,
          'daysInMonth': 30,
          'monthlyBudget': 1000,
          'projectedMonthExpense': 1500,
          'overspendRisk': true,
        },
        'goalForecast': [
          {
            'id': 'g1',
            'nameCipher': 'abc',
            'nameDekVer': 2,
            'targetAmount': 10000,
            'currentSaved': 3000,
            'progress': 0.3,
            'monthlyRate': 800,
            'etaDate': '2026-03-01T00:00:00.000Z',
          },
        ],
      });

      expect(f.monthEnd.isMonthly, isTrue);
      expect(f.monthEnd.remainingIncome, 3000);
      expect(f.upcoming30.single.isIncome, isTrue);
      expect(f.upcoming30.single.type, 'income');
      expect(f.pace.monthlyBudget, 1000);
      expect(f.pace.overspendRisk, isTrue);
      expect(f.goals.single.etaDate, isNotNull);
      expect(f.goals.single.progress, 0.3);
    });
  });
}
