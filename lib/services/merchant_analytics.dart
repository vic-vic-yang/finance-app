/// ======================================================================
/// 商户画像 · 纯计算层
/// ======================================================================
///
/// 端侧隐私 AI 的核心卖点：所有统计在本机完成，备注明文不出设备。
/// 本文件只做纯函数计算（无 Flutter / 网络 / 加解密依赖），便于单测；
/// 网络拉取与 DEK 解密在 merchant_insight_service.dart 中完成。
///
/// 口径：
///   - 只统计支出账单（type=expense、isTransfer=false、source != 'stock'
///     的过滤由调用方在构造 [MerchantBillInput] 前完成，此处再按时间窗过滤）。
///   - 时间窗 = 含当月在内的近 3 个自然月。
library;

/// 空备注统一归入的分组名。
const String kUnnotedMerchant = '未备注';

/// 依赖预警阈值：商户占其分类本月支出比例超过该值。
const double kDependencyAlertRatio = 0.4;

/// 依赖预警阈值：商户本月金额需超过该值（元）。
const double kDependencyAlertMinAmount = 200;

/// 从备注中提取商户名。
///
/// 规则：备注形如「商户:商品」或「商户：商品」时取第一个冒号前的
/// 非空前段为商户；否则整段（trim 后）为商户；空备注返回 ''（调用方
/// 归入 [kUnnotedMerchant] 分组）。
String extractMerchant(String? note) {
  final n = (note ?? '').trim();
  if (n.isEmpty) return '';
  final iAscii = n.indexOf(':');
  final iFull = n.indexOf('：');
  final int idx;
  if (iAscii >= 0 && iFull >= 0) {
    idx = iAscii < iFull ? iAscii : iFull;
  } else {
    idx = iAscii >= 0 ? iAscii : iFull;
  }
  if (idx > 0) {
    final prefix = n.substring(0, idx).trim();
    if (prefix.isNotEmpty) return prefix;
  }
  return n;
}

/// 一笔支出账单的计算输入（备注已解密并提取出商户）。
class MerchantBillInput {
  const MerchantBillInput({
    required this.merchant,
    required this.amount,
    required this.date,
    this.categoryId,
  });

  /// 商户名（已按 [extractMerchant] 提取；空串视为未备注）。
  final String merchant;
  final double amount;
  final DateTime date;

  /// 分类 id（明文字段）；null 视为未分类。
  final String? categoryId;
}

/// 商户聚合结果（不可变）。
class MerchantStat {
  MerchantStat({
    required this.merchant,
    required this.totalAmount,
    required this.count,
    required this.monthAmount,
    required this.monthCount,
    required Set<String> months,
  }) : months = Set.unmodifiable(months);

  final String merchant;

  /// 近 3 个月窗口内合计。
  final double totalAmount;
  final int count;

  /// 本月合计。
  final double monthAmount;
  final int monthCount;

  /// 出现过的自然月（'yyyy-MM'）。
  final Set<String> months;

  /// 是否近 3 个自然月每月都出现（常客）。
  bool isRegular(Set<String> windowKeys) => months.containsAll(windowKeys);
}

/// 依赖预警：某商户占其所属分类本月支出比例过高。
class DependencyAlert {
  const DependencyAlert({
    required this.merchant,
    required this.categoryId,
    required this.categoryName,
    required this.merchantAmount,
    required this.categoryAmount,
  });

  final String merchant;
  final String categoryId;

  /// 分类显示名（明文字段，调用方映射好）。
  final String categoryName;
  final double merchantAmount;
  final double categoryAmount;

  double get ratio =>
      categoryAmount > 0 ? merchantAmount / categoryAmount : 0;
}

/// 商户画像完整结果（不可变，供页面渲染）。
class MerchantInsightsReport {
  MerchantInsightsReport({
    required this.generatedAt,
    required this.windowStart,
    required this.currentMonth,
    required List<MerchantStat> topMerchants,
    required List<MerchantStat> regulars,
    required List<MerchantStat> newcomers,
    required List<DependencyAlert> alerts,
    required this.expenseBillCount,
    required this.currentMonthExpense,
  })  : topMerchants = List.unmodifiable(topMerchants),
        regulars = List.unmodifiable(regulars),
        newcomers = List.unmodifiable(newcomers),
        alerts = List.unmodifiable(alerts);

  final DateTime generatedAt;

  /// 窗口首日（含当月共 3 个自然月的 1 号）。
  final DateTime windowStart;

  /// 当月 'yyyy-MM'。
  final String currentMonth;

  /// 本月商户 TOP 榜（金额降序）。
  final List<MerchantStat> topMerchants;

  /// 常客商户：近 3 个自然月每月都出现（窗口总金额降序）。
  final List<MerchantStat> regulars;

  /// 新面孔：本月首次出现（窗口内前两个月没有记录）。
  final List<MerchantStat> newcomers;

  /// 依赖预警（商户本月金额降序）。
  final List<DependencyAlert> alerts;

  /// 窗口内参与统计的支出笔数。
  final int expenseBillCount;

  /// 本月支出总额。
  final double currentMonthExpense;

  bool get isEmpty => expenseBillCount == 0;
}

class _Agg {
  double total = 0;
  int count = 0;
  double monthAmount = 0;
  int monthCount = 0;
  final Set<String> months = {};
  final Map<String, double> monthCatAmount = {};
}

String _monthKey(DateTime d) =>
    '${d.year}-${d.month.toString().padLeft(2, '0')}';

/// 从支出账单构建商户画像（纯函数）。
///
/// [bills] 为已解密 / 已提取商户的支出输入；[categoryNames] 为
/// 分类 id → 显示名映射（依赖预警展示用）；[topN] 为 TOP 榜条数。
MerchantInsightsReport buildMerchantInsights(
  List<MerchantBillInput> bills, {
  required DateTime now,
  Map<String, String> categoryNames = const {},
  int topN = 10,
  double alertRatio = kDependencyAlertRatio,
  double alertMinAmount = kDependencyAlertMinAmount,
}) {
  final curKey = _monthKey(now);
  final windowKeys = {
    curKey,
    _monthKey(DateTime(now.year, now.month - 1)),
    _monthKey(DateTime(now.year, now.month - 2)),
  };
  final windowStart = DateTime(now.year, now.month - 2, 1);

  final agg = <String, _Agg>{};
  final catMonthTotals = <String, double>{};
  var kept = 0;
  var monthExpense = 0.0;

  for (final b in bills) {
    final k = _monthKey(b.date);
    if (!windowKeys.contains(k)) continue; // 防御：窗口外数据不参与
    kept++;
    final name =
        b.merchant.trim().isEmpty ? kUnnotedMerchant : b.merchant.trim();
    final a = agg.putIfAbsent(name, _Agg.new);
    a.total += b.amount;
    a.count++;
    a.months.add(k);
    if (k == curKey) {
      a.monthAmount += b.amount;
      a.monthCount++;
      monthExpense += b.amount;
      final cid = b.categoryId;
      if (cid != null) {
        catMonthTotals[cid] = (catMonthTotals[cid] ?? 0) + b.amount;
        a.monthCatAmount[cid] = (a.monthCatAmount[cid] ?? 0) + b.amount;
      }
    }
  }

  MerchantStat toStat(String name, _Agg a) => MerchantStat(
        merchant: name,
        totalAmount: a.total,
        count: a.count,
        monthAmount: a.monthAmount,
        monthCount: a.monthCount,
        months: a.months,
      );

  // 本月 TOP 榜：本月金额降序（并列按笔数、名称稳定排序）
  final top = [
    for (final e in agg.entries)
      if (e.value.monthCount > 0) toStat(e.key, e.value),
  ]..sort((x, y) {
      final c = y.monthAmount.compareTo(x.monthAmount);
      if (c != 0) return c;
      final c2 = y.monthCount.compareTo(x.monthCount);
      if (c2 != 0) return c2;
      return x.merchant.compareTo(y.merchant);
    });

  // 常客：近 3 个自然月每月都出现，按窗口总金额降序
  final regulars = [
    for (final e in agg.entries)
      if (e.value.months.containsAll(windowKeys)) toStat(e.key, e.value),
  ]..sort((x, y) {
      final c = y.totalAmount.compareTo(x.totalAmount);
      if (c != 0) return c;
      return x.merchant.compareTo(y.merchant);
    });

  // 新面孔：本月有记录，且前两个自然月都没有
  final prevKeys = windowKeys.toSet()..remove(curKey);
  final newcomers = [
    for (final e in agg.entries)
      if (e.value.monthCount > 0 &&
          !e.value.months.any(prevKeys.contains))
        toStat(e.key, e.value),
  ]..sort((x, y) {
      final c = y.monthAmount.compareTo(x.monthAmount);
      if (c != 0) return c;
      return x.merchant.compareTo(y.merchant);
    });

  // 依赖预警：商户占其分类本月支出 > 阈值比例且金额 > 阈值
  final alerts = <DependencyAlert>[];
  for (final e in agg.entries) {
    for (final ce in e.value.monthCatAmount.entries) {
      final catTotal = catMonthTotals[ce.key] ?? 0;
      if (catTotal <= 0) continue;
      if (ce.value / catTotal > alertRatio && ce.value > alertMinAmount) {
        alerts.add(DependencyAlert(
          merchant: e.key,
          categoryId: ce.key,
          categoryName: categoryNames[ce.key] ?? '未分类',
          merchantAmount: ce.value,
          categoryAmount: catTotal,
        ));
      }
    }
  }
  alerts.sort((x, y) => y.merchantAmount.compareTo(x.merchantAmount));

  return MerchantInsightsReport(
    generatedAt: now,
    windowStart: windowStart,
    currentMonth: curKey,
    topMerchants: top.length > topN ? top.sublist(0, topN) : top,
    regulars: regulars,
    newcomers: newcomers,
    alerts: alerts,
    expenseBillCount: kept,
    currentMonthExpense: monthExpense,
  );
}
