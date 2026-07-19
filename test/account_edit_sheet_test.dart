import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:finance_app/models/account.dart';
import 'package:finance_app/screens/accounts_screen.dart'
    show showAccountEditSheet;

void main() {
  testWidgets('编辑账户弹层能正常渲染（表单步）', (tester) async {
    final acc = Account(
      id: 'a1',
      ledgerId: 'l1',
      nameCipher: null, // 无需解密，直接显示【未命名】
      type: 'BANK',
      balance: 1019.10,
      initialBalance: 204.16,
    );
    await tester.pumpWidget(MaterialApp(
      home: Builder(
        builder: (ctx) => Scaffold(
          body: Center(
            child: ElevatedButton(
              onPressed: () => showAccountEditSheet(ctx, acc),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    ));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    // 弹层应显示表单内容，而不是只有蒙层
    expect(find.text('编辑账户'), findsOneWidget);
    expect(find.text('账户名称'), findsOneWidget);
  });
}
