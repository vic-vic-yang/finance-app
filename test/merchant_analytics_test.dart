import 'package:flutter_test/flutter_test.dart';
import 'package:finance_app/services/merchant_analytics.dart';

void main() {
  group('extractMerchant', () {
    test('「商户:商品」取第一段（半角冒号）', () {
      expect(extractMerchant('星巴克:大杯拿铁'), '星巴克');
      expect(extractMerchant('京东:iPhone 15 手机壳'), '京东');
    });

    test('「商户：商品」取第一段（全角冒号）', () {
      expect(extractMerchant('麦当劳：巨无霸套餐'), '麦当劳');
    });

    test('无冒号时整段为商户', () {
      expect(extractMerchant('永辉超市'), '永辉超市');
    });

    test('冒号在首位 / 前段为空时整段为商户', () {
      expect(extractMerchant(':无前缀'), ':无前缀');
      expect(extractMerchant('：无前缀'), '：无前缀');
    });

    test('取第一个出现的冒号（半角优先看位置）', () {
      expect(extractMerchant('瑞幸:美式：加冰'), '瑞幸');
      expect(extractMerchant('瑞幸：美式:加冰'), '瑞幸');
    });

    test('空 / 纯空白返回空串', () {
      expect(extractMerchant(''), '');
      expect(extractMerchant('   '), '');
      expect(extractMerchant(null), '');
    });

    test('前后空白会被 trim', () {
      expect(extractMerchant('  海底捞 : 火锅  '), '海底捞');
    });
  });

  group('buildMerchantInsights', () {
    // 以 2025-06-15 为"本月"，窗口 = 2025-04 / 05 / 06
    final now = DateTime(2025, 6, 15);

    MerchantBillInput b(String merchant, double amount, DateTime date,
            {String? categoryId}) =>
        MerchantBillInput(
            merchant: merchant,
            amount: amount,
            date: date,
            categoryId: categoryId);

    test('本月 TOP 榜按金额降序，含笔数', () {
      final r = buildMerchantInsights([
        b('A', 100, DateTime(2025, 6, 1)),
        b('A', 50, DateTime(2025, 6, 5)),
        b('B', 300, DateTime(2025, 6, 2)),
        b('C', 10, DateTime(2025, 6, 3)),
      ], now: now);
      expect(r.topMerchants.map((s) => s.merchant), ['B', 'A', 'C']);
      expect(r.topMerchants[0].monthAmount, 300);
      expect(r.topMerchants[1].monthAmount, 150);
      expect(r.topMerchants[1].monthCount, 2);
      expect(r.currentMonthExpense, 460);
      expect(r.expenseBillCount, 4);
    });

    test('常客 = 近 3 个自然月每月都出现', () {
      final r = buildMerchantInsights([
        b('常客', 10, DateTime(2025, 4, 1)),
        b('常客', 20, DateTime(2025, 5, 1)),
        b('常客', 30, DateTime(2025, 6, 1)),
        b('非常客', 99, DateTime(2025, 5, 1)),
        b('非常客', 99, DateTime(2025, 6, 1)),
      ], now: now);
      expect(r.regulars.map((s) => s.merchant), ['常客']);
      expect(r.regulars.first.totalAmount, 60);
      expect(r.regulars.first.count, 3);
    });

    test('新面孔 = 本月首次出现（前两个月无记录）', () {
      final r = buildMerchantInsights([
        b('老店', 10, DateTime(2025, 4, 20)),
        b('老店', 10, DateTime(2025, 6, 1)),
        b('新店', 88, DateTime(2025, 6, 2)),
      ], now: now);
      expect(r.newcomers.map((s) => s.merchant), ['新店']);
    });

    test('依赖预警：占分类本月支出 > 40% 且金额 > 200', () {
      final r = buildMerchantInsights([
        b('巨头', 500, DateTime(2025, 6, 1), categoryId: 'c1'),
        b('小店', 200, DateTime(2025, 6, 2), categoryId: 'c1'),
        // 占比高但金额 ≤ 200 不预警
        b('微店', 150, DateTime(2025, 6, 3), categoryId: 'c2'),
        b('另一店', 50, DateTime(2025, 6, 3), categoryId: 'c2'),
      ], now: now, categoryNames: {'c1': '餐饮', 'c2': '交通'});
      expect(r.alerts.length, 1);
      final a = r.alerts.first;
      expect(a.merchant, '巨头');
      expect(a.categoryName, '餐饮');
      expect(a.merchantAmount, 500);
      expect(a.categoryAmount, 700);
      expect(a.ratio, closeTo(500 / 700, 1e-9));
    });

    test('占比恰好 40% 不预警（需 > 40%）', () {
      final r = buildMerchantInsights([
        b('甲', 400, DateTime(2025, 6, 1), categoryId: 'c1'),
        b('乙', 600, DateTime(2025, 6, 1), categoryId: 'c1'),
      ], now: now);
      // 甲 400/1000 = 40% 不预警；乙 60% 正常预警
      expect(r.alerts.map((a) => a.merchant), ['乙']);
    });

    test('空备注归入「未备注」分组', () {
      final r = buildMerchantInsights([
        b('', 100, DateTime(2025, 6, 1)),
        b('   ', 50, DateTime(2025, 6, 2)),
      ], now: now);
      expect(r.topMerchants.single.merchant, kUnnotedMerchant);
      expect(r.topMerchants.single.monthAmount, 150);
    });

    test('窗口外数据不参与统计', () {
      final r = buildMerchantInsights([
        b('老店', 999, DateTime(2025, 3, 31)), // 3 月：窗口外
        b('老店', 10, DateTime(2025, 6, 1)),
      ], now: now);
      expect(r.expenseBillCount, 1);
      expect(r.topMerchants.single.monthAmount, 10);
      expect(r.topMerchants.single.totalAmount, 10);
      // 3 月不算"前两个月有记录"，但 4/5 月也没有 → 仍是新面孔
      expect(r.newcomers.map((s) => s.merchant), ['老店']);
    });

    test('无账单时 isEmpty', () {
      final r = buildMerchantInsights(const [], now: now);
      expect(r.isEmpty, isTrue);
      expect(r.topMerchants, isEmpty);
      expect(r.regulars, isEmpty);
      expect(r.newcomers, isEmpty);
      expect(r.alerts, isEmpty);
    });

    test('TOP 榜最多取 topN 条', () {
      final r = buildMerchantInsights([
        for (var i = 0; i < 15; i++)
          b('商户$i', (100 - i).toDouble(), DateTime(2025, 6, 1)),
      ], now: now);
      expect(r.topMerchants.length, 10);
      expect(r.topMerchants.first.merchant, '商户0');
    });

    test('无分类（categoryId 为 null）不参与依赖预警', () {
      final r = buildMerchantInsights([
        b('独大', 1000, DateTime(2025, 6, 1)),
      ], now: now);
      expect(r.alerts, isEmpty);
    });
  });
}
