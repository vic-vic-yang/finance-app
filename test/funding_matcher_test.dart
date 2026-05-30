import 'package:flutter_test/flutter_test.dart';
import 'package:finance_app/services/funding_matcher.dart';

void main() {
  group('normalizeFundingHint', () {
    test('银行卡 → 银行:尾号', () {
      expect(normalizeFundingHint('招商银行储蓄卡(5476)'), '招商:5476');
      expect(normalizeFundingHint('中国工商银行信用卡(1234)'), '工商:1234');
    });
    test('钱包类归一', () {
      expect(normalizeFundingHint('花呗'), '花呗');
      expect(normalizeFundingHint('账户余额'), '支付宝余额');
      expect(normalizeFundingHint('余额宝'), '余额宝');
    });
    test('空/未知原样 trim', () {
      expect(normalizeFundingHint('  '), '');
      expect(normalizeFundingHint('未知方式'), '未知方式');
    });
  });

  group('matchAccountId', () {
    final accounts = [
      ('a1', '招商信用卡5476'),
      ('a2', '支付宝余额'),
      ('a3', '花呗'),
    ];
    test('已记忆映射优先', () {
      final id = matchAccountId('招商:5476', accounts, {'招商:5476': 'aX'});
      expect(id, 'aX');
    });
    test('按尾号+名称模糊匹配', () {
      expect(matchAccountId('招商:5476', accounts, {}), 'a1');
      expect(matchAccountId('花呗', accounts, {}), 'a3');
    });
    test('匹配不上返回 null', () {
      expect(matchAccountId('建行:9999', accounts, {}), isNull);
    });
  });
}
