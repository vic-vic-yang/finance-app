import 'package:flutter_test/flutter_test.dart';
import 'package:finance_app/services/bills_filter_query.dart';

/// 账单列表「筛选条件 → 后端查询参数」的纯函数测试。
/// 覆盖日期范围（含闰年月末边界）与 isTransfer/source 组装。
void main() {
  group('billsDateRange', () {
    test('全部时间：start / end 都为 null（不传参）', () {
      final r = billsDateRange(mode: BillsDateMode.all);
      expect(r.start, isNull);
      expect(r.end, isNull);
    });

    test('月模式：普通月份取当月 1 号到月末', () {
      final r = billsDateRange(
          mode: BillsDateMode.month, anchor: DateTime(2025, 1, 15));
      expect(r.start, '2025-01-01');
      expect(r.end, '2025-01-31');
    });

    test('月模式：闰年 2 月月末是 29 号', () {
      final r = billsDateRange(
          mode: BillsDateMode.month, anchor: DateTime(2024, 2, 10));
      expect(r.start, '2024-02-01');
      expect(r.end, '2024-02-29');
    });

    test('月模式：平年 2 月月末是 28 号', () {
      final r = billsDateRange(
          mode: BillsDateMode.month, anchor: DateTime(2025, 2, 10));
      expect(r.start, '2025-02-01');
      expect(r.end, '2025-02-28');
    });

    test('月模式：小月 30 天（4 月）', () {
      final r = billsDateRange(
          mode: BillsDateMode.month, anchor: DateTime(2025, 4, 1));
      expect(r.end, '2025-04-30');
    });

    test('月模式：12 月跨年不溢出', () {
      final r = billsDateRange(
          mode: BillsDateMode.month, anchor: DateTime(2025, 12, 20));
      expect(r.start, '2025-12-01');
      expect(r.end, '2025-12-31');
    });

    test('年模式：整年 01-01 到 12-31', () {
      final r = billsDateRange(
          mode: BillsDateMode.year, anchor: DateTime(2024, 7, 1));
      expect(r.start, '2024-01-01');
      expect(r.end, '2024-12-31');
    });

    test('范围模式：两端都选时格式化 yyyy-MM-dd', () {
      final r = billsDateRange(
        mode: BillsDateMode.range,
        rangeStart: DateTime(2025, 3, 5),
        rangeEnd: DateTime(2025, 3, 18),
      );
      expect(r.start, '2025-03-05');
      expect(r.end, '2025-03-18');
    });

    test('范围模式：只选起点时 end 为 null（只传一端）', () {
      final r = billsDateRange(
        mode: BillsDateMode.range,
        rangeStart: DateTime(2025, 3, 5),
      );
      expect(r.start, '2025-03-05');
      expect(r.end, isNull);
    });

    test('范围模式：只选终点时 start 为 null', () {
      final r = billsDateRange(
        mode: BillsDateMode.range,
        rangeEnd: DateTime(2025, 3, 18),
      );
      expect(r.start, isNull);
      expect(r.end, '2025-03-18');
    });

    test('范围模式：都没选时两端 null（退化为全部时间）', () {
      final r = billsDateRange(mode: BillsDateMode.range);
      expect(r.start, isNull);
      expect(r.end, isNull);
    });
  });

  group('billsIsTransferFilter', () {
    test('只看转账：恒 true', () {
      expect(billsIsTransferFilter(transfersOnly: true), 'true');
    });

    test('按来源筛选（股票盈亏）：排除转账 false', () {
      expect(
          billsIsTransferFilter(transfersOnly: false, source: 'stock'),
          'false');
    });

    test('不筛选：null（不传参）', () {
      expect(billsIsTransferFilter(transfersOnly: false), isNull);
    });

    test('只看转账与来源同时存在时转账优先', () {
      expect(billsIsTransferFilter(transfersOnly: true, source: 'stock'),
          'true');
    });
  });
}
