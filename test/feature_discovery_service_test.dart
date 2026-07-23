import 'dart:convert';

import 'package:finance_app/services/feature_discovery_service.dart';
import 'package:finance_app/widgets/feature_discovery_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  const kTestKey = FeatureDiscoveryService.kStreakForecast;
  const kOtherKey = FeatureDiscoveryService.kMerchantRecurring;

  Future<void> loginAs(String userId) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('auth_user', jsonEncode({'id': userId}));
  }

  group('FeatureDiscoveryService 持久化', () {
    test('未展示过 isShown=false；markShown 后=true', () async {
      SharedPreferences.setMockInitialValues({});
      await loginAs('u1');
      final fd = FeatureDiscoveryService.instance;

      expect(await fd.isShown(kTestKey), isFalse);
      await fd.markShown(kTestKey);
      expect(await fd.isShown(kTestKey), isTrue);
      // 另一个 key 不受影响
      expect(await fd.isShown(kOtherKey), isFalse);
    });

    test('按 userId 隔离：A 账号已展示，B 账号不受影响', () async {
      SharedPreferences.setMockInitialValues({});
      final fd = FeatureDiscoveryService.instance;

      await loginAs('user-a');
      await fd.markShown(kTestKey);
      expect(await fd.isShown(kTestKey), isTrue);

      // 切到 B 账号：同一场景仍未展示
      await loginAs('user-b');
      expect(await fd.isShown(kTestKey), isFalse);

      // 切回 A：状态还在
      await loginAs('user-a');
      expect(await fd.isShown(kTestKey), isTrue);
    });

    test('未登录（anon）也能持久化，且与登录账号隔离', () async {
      SharedPreferences.setMockInitialValues({});
      final fd = FeatureDiscoveryService.instance;

      await fd.markShown(kTestKey);
      expect(await fd.isShown(kTestKey), isTrue);

      await loginAs('user-a');
      expect(await fd.isShown(kTestKey), isFalse);
    });

    test('reset 只重置指定 key', () async {
      SharedPreferences.setMockInitialValues({});
      await loginAs('u1');
      final fd = FeatureDiscoveryService.instance;

      await fd.markShown(kTestKey);
      await fd.markShown(kOtherKey);
      await fd.reset(kTestKey);

      expect(await fd.isShown(kTestKey), isFalse);
      expect(await fd.isShown(kOtherKey), isTrue);
    });

    test('resetAll 清空当前账号全部场景，不影响其他账号', () async {
      SharedPreferences.setMockInitialValues({});
      final fd = FeatureDiscoveryService.instance;

      await loginAs('user-a');
      await fd.markShown(kTestKey);
      await fd.markShown(kOtherKey);
      await loginAs('user-b');
      await fd.markShown(kTestKey);

      // 清 B 账号
      await fd.resetAll();
      expect(await fd.isShown(kTestKey), isFalse);

      // A 账号不受影响
      await loginAs('user-a');
      expect(await fd.isShown(kTestKey), isTrue);
      expect(await fd.isShown(kOtherKey), isTrue);
    });
  });

  group('FeatureDiscoveryService.maybeShow', () {
    testWidgets('首次展示卡片并标记；第二次不再展示', (tester) async {
      SharedPreferences.setMockInitialValues({});
      await loginAs('u1');
      final fd = FeatureDiscoveryService.instance;

      const data = FeatureDiscoveryCardData(
        emoji: '📈',
        title: '已连续记账 7 天，试试现金流预测',
        message: '按当前节奏推算月末结余',
      );

      var goTapped = 0;
      Future<void> trigger(BuildContext context) => fd.maybeShow(
            context,
            kTestKey,
            data,
            onGo: () => goTapped++,
          );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () => trigger(context),
                child: const Text('trigger'),
              ),
            ),
          ),
        ),
      );

      // 第一次：展示卡片
      await tester.tap(find.text('trigger'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text('已连续记账 7 天，试试现金流预测'), findsOneWidget);
      expect(await fd.isShown(kTestKey), isTrue);

      // 「去看看」：关闭卡片 + 触发回调
      await tester.tap(find.text('去看看'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(goTapped, 1);
      expect(find.text('已连续记账 7 天，试试现金流预测'), findsNothing);

      // 第二次：一生一次，不再展示
      await tester.tap(find.text('trigger'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text('已连续记账 7 天，试试现金流预测'), findsNothing);
    });

    testWidgets('「知道了」仅关闭，同样一生一次', (tester) async {
      SharedPreferences.setMockInitialValues({});
      await loginAs('u1');
      final fd = FeatureDiscoveryService.instance;

      const data = FeatureDiscoveryCardData(
        emoji: '🔔',
        title: '预算预警已就位',
        message: '快超支时会提醒你',
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () => fd.maybeShow(context, kOtherKey, data),
                child: const Text('trigger'),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('trigger'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text('预算预警已就位'), findsOneWidget);

      await tester.tap(find.text('知道了'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text('预算预警已就位'), findsNothing);
      expect(await fd.isShown(kOtherKey), isTrue);
    });
  });
}
