import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:finance_app/screens/notifications_screen.dart';

Map<String, dynamic> _item(String id,
        {bool unread = true, String? title, String severity = 'warning'}) =>
    {
      'id': id,
      'type': 'cfo_proposal',
      'title': title ?? '标题$id',
      'body': '正文$id',
      'ledgerId': null,
      'payload': {'severity': severity},
      'readAt': unread ? null : DateTime(2025, 1, 1).toIso8601String(),
      'createdAt': DateTime(2025, 1, 2, 8, 17).toIso8601String(),
    };

Map<String, dynamic> _page(List<Map<String, dynamic>> items,
        {bool hasMore = false}) =>
    {
      'items': items,
      'total': items.length,
      'page': 1,
      'pageSize': 20,
      'hasMore': hasMore,
    };

void main() {
  testWidgets('加载态：数据未返回时显示加载指示器', (tester) async {
    final completer = Completer<Map<String, dynamic>>();
    await tester.pumpWidget(MaterialApp(
      home: NotificationsScreen(
        listFetcher: ({int page = 1, int pageSize = 20}) => completer.future,
      ),
    ));
    await tester.pump();
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    // 收尾，避免悬挂 future
    completer.complete(_page(const []));
    await tester.pumpAndSettle();
  });

  testWidgets('空态：无通知时显示友好空状态', (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: NotificationsScreen(
        listFetcher: ({int page = 1, int pageSize = 20}) async =>
            _page(const []),
      ),
    ));
    await tester.pumpAndSettle();
    expect(find.text('暂无通知'), findsOneWidget);
    expect(find.text('全部已读'), findsNothing);
  });

  testWidgets('列表：未读有圆点标记，已读没有', (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: NotificationsScreen(
        listFetcher: ({int page = 1, int pageSize = 20}) async => _page([
          _item('n1', unread: true, title: '预算超支预警'),
          _item('n2', unread: false, title: '月报已生成'),
        ]),
      ),
    ));
    await tester.pumpAndSettle();
    expect(find.text('预算超支预警'), findsOneWidget);
    expect(find.text('月报已生成'), findsOneWidget);
    expect(find.byKey(const Key('unread-dot-n1')), findsOneWidget);
    expect(find.byKey(const Key('unread-dot-n2')), findsNothing);
    // 存在未读 → 出现「全部已读」
    expect(find.text('全部已读'), findsOneWidget);
  });

  testWidgets('点击单条未读：标记已读并去掉未读圆点', (tester) async {
    final marked = <String>[];
    await tester.pumpWidget(MaterialApp(
      home: NotificationsScreen(
        listFetcher: ({int page = 1, int pageSize = 20}) async => _page([
          _item('n1', unread: true, title: '大额支出提醒'),
        ]),
        readMarker: (id) async => marked.add(id),
      ),
    ));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('unread-dot-n1')), findsOneWidget);

    await tester.tap(find.text('大额支出提醒'));
    await tester.pumpAndSettle();
    expect(marked, ['n1']);
    expect(find.byKey(const Key('unread-dot-n1')), findsNothing);
    // 全部已读后「全部已读」按钮消失
    expect(find.text('全部已读'), findsNothing);
  });

  testWidgets('点击已读条目：不重复触发已读接口', (tester) async {
    final marked = <String>[];
    await tester.pumpWidget(MaterialApp(
      home: NotificationsScreen(
        listFetcher: ({int page = 1, int pageSize = 20}) async => _page([
          _item('n2', unread: false, title: '旧通知'),
        ]),
        readMarker: (id) async => marked.add(id),
      ),
    ));
    await tester.pumpAndSettle();
    await tester.tap(find.text('旧通知'));
    await tester.pumpAndSettle();
    expect(marked, isEmpty);
  });

  testWidgets('全部已读：调用接口并清除所有未读标记', (tester) async {
    var allReadCalled = 0;
    final read = <String>[];
    await tester.pumpWidget(MaterialApp(
      home: NotificationsScreen(
        listFetcher: ({int page = 1, int pageSize = 20}) async => _page([
          _item('n1', unread: true),
          _item('n2', unread: true),
          _item('n3', unread: false),
        ]),
        readMarker: (id) async => read.add(id),
        allReadMarker: () async => allReadCalled++,
      ),
    ));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('unread-dot-n1')), findsOneWidget);
    expect(find.byKey(const Key('unread-dot-n2')), findsOneWidget);

    await tester.tap(find.text('全部已读'));
    await tester.pumpAndSettle();
    expect(allReadCalled, 1);
    expect(find.byKey(const Key('unread-dot-n1')), findsNothing);
    expect(find.byKey(const Key('unread-dot-n2')), findsNothing);
    expect(find.text('全部已读'), findsNothing);
    // 全部已读走批量接口，不逐条调用
    expect(read, isEmpty);
  });
}
