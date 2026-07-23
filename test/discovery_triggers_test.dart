import 'package:finance_app/services/discovery_triggers.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final now = DateTime(2026, 5, 20, 15, 30);

  DateTime daysAgo(int n, {int hour = 10}) =>
      DateTime(now.year, now.month, now.day - n, hour);

  group('bookkeepingStreak', () {
    test('无账单 → 0', () {
      expect(bookkeepingStreak(const [], now), 0);
    });

    test('只有今天 → 1', () {
      expect(bookkeepingStreak([daysAgo(0)], now), 1);
    });

    test('连续 7 天（含今天）→ 7', () {
      final dates = [for (var i = 0; i < 7; i++) daysAgo(i)];
      expect(bookkeepingStreak(dates, now), 7);
    });

    test('今天没记、昨天起连续 7 天 → 7（今天还没过完不算断签）', () {
      final dates = [for (var i = 1; i <= 7; i++) daysAgo(i)];
      expect(bookkeepingStreak(dates, now), 7);
    });

    test('今天昨天都没有 → 0', () {
      final dates = [for (var i = 2; i <= 8; i++) daysAgo(i)];
      expect(bookkeepingStreak(dates, now), 0);
    });

    test('中间断一天 → 只数到今天为止的连续段', () {
      final dates = [
        daysAgo(0), daysAgo(1), daysAgo(2),
        // 3 天前断了
        daysAgo(4), daysAgo(5), daysAgo(6),
      ];
      expect(bookkeepingStreak(dates, now), 3);
    });

    test('同一天多笔只算一天；时分秒被忽略', () {
      final dates = [
        DateTime(now.year, now.month, now.day, 0, 1),
        DateTime(now.year, now.month, now.day, 23, 59),
        daysAgo(1, hour: 8),
        daysAgo(1, hour: 22),
      ];
      expect(bookkeepingStreak(dates, now), 2);
    });
  });

  group('frequentMerchant', () {
    test('无数据 → null', () {
      expect(frequentMerchant(const [], now: now), isNull);
    });

    test('窗口内出现 2 次（< minCount）→ null', () {
      final entries = [
        (merchant: '星巴克', date: daysAgo(1)),
        (merchant: '星巴克', date: daysAgo(3)),
      ];
      expect(frequentMerchant(entries, now: now), isNull);
    });

    test('窗口内出现 3 次 → 返回商户与次数', () {
      final entries = [
        (merchant: '星巴克', date: daysAgo(1)),
        (merchant: '星巴克', date: daysAgo(8)),
        (merchant: '星巴克', date: daysAgo(15)),
        (merchant: '瑞幸', date: daysAgo(2)),
      ];
      final hit = frequentMerchant(entries, now: now);
      expect(hit, isNotNull);
      expect(hit!.merchant, '星巴克');
      expect(hit.count, 3);
    });

    test('窗口外（≥30 天前）的记录不计入', () {
      final entries = [
        (merchant: '星巴克', date: daysAgo(1)),
        (merchant: '星巴克', date: daysAgo(31)),
        (merchant: '星巴克', date: daysAgo(45)),
      ];
      expect(frequentMerchant(entries, now: now), isNull);
    });

    test('空商户名 / 纯空白不参与统计', () {
      final entries = [
        (merchant: '', date: daysAgo(1)),
        (merchant: '   ', date: daysAgo(2)),
        (merchant: '', date: daysAgo(3)),
      ];
      expect(frequentMerchant(entries, now: now), isNull);
    });

    test('次数最多者胜出；并列取最近出现者', () {
      final entries = [
        (merchant: '星巴克', date: daysAgo(10)),
        (merchant: '星巴克', date: daysAgo(11)),
        (merchant: '星巴克', date: daysAgo(12)),
        // 瑞幸同样 3 次但最近一笔更近
        (merchant: '瑞幸', date: daysAgo(1)),
        (merchant: '瑞幸', date: daysAgo(5)),
        (merchant: '瑞幸', date: daysAgo(9)),
        // 麦当劳 2 次不够
        (merchant: '麦当劳', date: daysAgo(2)),
        (merchant: '麦当劳', date: daysAgo(3)),
      ];
      final hit = frequentMerchant(entries, now: now);
      expect(hit!.merchant, '瑞幸');
      expect(hit.count, 3);
    });

    test('自定义 minCount / windowDays', () {
      final entries = [
        (merchant: '健身房', date: daysAgo(40)),
        (merchant: '健身房', date: daysAgo(70)),
      ];
      // 默认 30 天窗口 → null
      expect(frequentMerchant(entries, now: now), isNull);
      // 90 天窗口 + minCount=2 → 命中
      final hit =
          frequentMerchant(entries, now: now, windowDays: 90, minCount: 2);
      expect(hit!.merchant, '健身房');
      expect(hit.count, 2);
    });
  });
}
