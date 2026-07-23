import 'package:intl/intl.dart';

/// 账单列表的日期筛选模式。
/// （原 bills_screen 的私有 _DateMode 提取为公共枚举，便于纯函数单测；
///   bills_screen 内以 `typedef _DateMode = BillsDateMode` 保持原有用法不变）
enum BillsDateMode { all, month, year, range }

/// 日期筛选 → 后端 startDate / endDate（yyyy-MM-dd）的纯计算。
///
/// - all：两端都 null（不传参 = 全部时间）
/// - range：起点 / 终点各自独立可空（只选一端就只传一端）
/// - year：anchor 年的 01-01 ~ 12-31
/// - month：anchor 月的 01 ~ 月末（月末用下月第 0 天求，天然处理闰年）
({String? start, String? end}) billsDateRange({
  required BillsDateMode mode,
  DateTime? anchor,
  DateTime? rangeStart,
  DateTime? rangeEnd,
}) {
  switch (mode) {
    case BillsDateMode.all:
      return (start: null, end: null);
    case BillsDateMode.range:
      return (
        start: rangeStart == null
            ? null
            : DateFormat('yyyy-MM-dd').format(rangeStart),
        end: rangeEnd == null
            ? null
            : DateFormat('yyyy-MM-dd').format(rangeEnd),
      );
    case BillsDateMode.year:
      final a = anchor ?? DateTime.now();
      return (start: '${a.year}-01-01', end: '${a.year}-12-31');
    case BillsDateMode.month:
      final a = anchor ?? DateTime.now();
      final last = DateTime(a.year, a.month + 1, 0).day;
      final m = a.month.toString().padLeft(2, '0');
      return (
        start: '${a.year}-$m-01',
        end: '${a.year}-$m-${last.toString().padLeft(2, '0')}',
      );
  }
}

/// 「只看转账 / 来源筛选」→ 后端 isTransfer 查询参数。
///
/// - 只看转账：恒 'true'
/// - 按来源筛选（如 source='stock' 看股票盈亏）：'false'（排除转账/借贷流水）
/// - 都不限：null（不传参）
String? billsIsTransferFilter({required bool transfersOnly, String? source}) {
  if (transfersOnly) return 'true';
  if (source != null) return 'false';
  return null;
}
