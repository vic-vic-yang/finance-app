/// ======================================================================
/// 时机式功能发现 · 触发判断纯函数
/// ======================================================================
///
/// 只做纯计算（无 Flutter / 网络依赖），便于单测。调用方负责把账单
/// 数据整理成输入；「一生一次」的裁决在 feature_discovery_service.dart。
library;

/// 连续记账天数（streak）。
///
/// 以「今天或昨天」为终点向前数连续有账单的**自然日**数：
///   - 今天有账单 → 从今天往前数；
///   - 今天没有但昨天有 → 从昨天往前数（今天还没记，不算断签）；
///   - 今天昨天都没有 → 0。
/// [billDates] 中的时分秒会被忽略，只按自然日去重。
int bookkeepingStreak(Iterable<DateTime> billDates, DateTime now) {
  final days = <DateTime>{};
  for (final d in billDates) {
    days.add(DateTime(d.year, d.month, d.day));
  }
  if (days.isEmpty) return 0;
  final today = DateTime(now.year, now.month, now.day);
  var cursor = today;
  if (!days.contains(cursor)) {
    cursor = cursor.subtract(const Duration(days: 1));
    if (!days.contains(cursor)) return 0;
  }
  var streak = 0;
  while (days.contains(cursor)) {
    streak++;
    cursor = cursor.subtract(const Duration(days: 1));
  }
  return streak;
}

/// 近 [windowDays] 天内出现次数最多的商户；次数 ≥ [minCount] 才返回，
/// 否则返回 null。商户名为空串的条目不参与统计。
/// 返回记录 (merchant, count)；并列时取窗口内最近一次出现的商户。
({String merchant, int count})? frequentMerchant(
  Iterable<({String merchant, DateTime date})> entries, {
  required DateTime now,
  int windowDays = 30,
  int minCount = 3,
}) {
  final windowStart = DateTime(now.year, now.month, now.day)
      .subtract(Duration(days: windowDays - 1));
  final counts = <String, int>{};
  final lastSeen = <String, DateTime>{};
  for (final e in entries) {
    final name = e.merchant.trim();
    if (name.isEmpty) continue;
    final day = DateTime(e.date.year, e.date.month, e.date.day);
    if (day.isBefore(windowStart)) continue;
    counts[name] = (counts[name] ?? 0) + 1;
    final prev = lastSeen[name];
    if (prev == null || day.isAfter(prev)) lastSeen[name] = day;
  }
  String? best;
  for (final entry in counts.entries) {
    if (entry.value < minCount) continue;
    if (best == null) {
      best = entry.key;
      continue;
    }
    final c = entry.value.compareTo(counts[best]!);
    if (c > 0 ||
        (c == 0 && lastSeen[entry.key]!.isAfter(lastSeen[best]!))) {
      best = entry.key;
    }
  }
  if (best == null) return null;
  return (merchant: best, count: counts[best]!);
}
