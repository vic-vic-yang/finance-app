import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:finance_app/crypto/key_chain.dart';
import 'package:finance_app/models/bill.dart';
import 'package:finance_app/screens/add_bill_screen.dart';

/// 「记一笔」表单测试：
/// - validateBillDraft 纯校验（金额 / 分类 / 账户 / 转账双方）全分支单测
/// - widget 链路：金额必填、类型切换的分类联动、转账账户联动、
///   createBill / transfer / convertBill 的提交参数正确性
/// 网络层通过注入的 _FakeAddBillApi 隔离；DEK 直接 putDek 进 KeyChain（纯 Dart 加密）。
void main() {
  // ── Fake API ─────────────────────────────────────────────────
  final baseCategories = [
    {'id': 'c-food', 'name': '餐饮', 'type': 'expense', 'icon': '🍜'},
    {'id': 'c-trans', 'name': '交通', 'type': 'expense', 'icon': '🚌'},
    {'id': 'c-salary', 'name': '工资', 'type': 'income', 'icon': '💰'},
  ];

  Map<String, dynamic> accJson(String id) => {
        'id': id,
        'ledgerId': 'l1',
        'nameCipher': null,
        'nameDekVer': 1,
        'type': 'BANK',
        'balance': 1000,
        'initialBalance': 0,
        'ownerId': null,
      };

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    // 给测试账本装一把全零 DEK，保存时的备注加密走纯 Dart SM4，无需插件
    KeyChain.instance
        .putDek(ledgerId: 'l1', rawDek: Uint8List(16), dekVersion: 1);
  });

  Future<void> pumpN(WidgetTester tester, [int n = 6]) async {
    for (var i = 0; i < n; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
  }

  /// tab 切换动画约 300ms，多给几帧确保 _onTabChanged 落停后再断言
  Future<void> tapTab(WidgetTester tester, String label) async {
    await tester.tap(find.text(label));
    await pumpN(tester, 12);
  }

  Future<void> pumpScreen(
    WidgetTester tester,
    FakeAddBillApi api, {
    Bill? bill,
  }) async {
    // 页面是固定 Column（头部 + 数字键盘），默认 800×600 测试表面会溢出，
    // 拉高视口避免 RenderFlex overflow 干扰断言
    tester.view.physicalSize = const Size(1080, 1400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(
      home: AddBillScreen(api: api, bill: bill),
    ));
    await pumpN(tester);
  }

  Future<void> tapKey(WidgetTester tester, String k) async {
    await tester.tap(find.byKey(Key('numkey-$k')));
    await tester.pump();
  }

  /// 成功保存后：等对勾 overlay 动画（约 900ms）播完并 pop，避免悬挂 ticker
  Future<void> finishSaveAnimation(WidgetTester tester) async {
    await tester.pump(const Duration(seconds: 1));
    await tester.pump(const Duration(milliseconds: 300));
  }

  /// 校验失败提示后：等 SnackBar（4s）消失，避免悬挂 Timer
  Future<void> dismissSnackBar(WidgetTester tester) async {
    await tester.pump(const Duration(seconds: 5));
    await tester.pump(const Duration(milliseconds: 300));
  }

  // ── validateBillDraft 纯校验 ─────────────────────────────────
  group('validateBillDraft', () {
    test('金额为零 / 负数：提示输入有效金额', () {
      expect(
          validateBillDraft(
              amount: 0, type: 'expense', categoryId: 'c', accountId: 'a'),
          '请输入有效金额');
      expect(
          validateBillDraft(
              amount: -5, type: 'expense', categoryId: 'c', accountId: 'a'),
          '请输入有效金额');
      expect(validateBillDraft(amount: 0, type: 'transfer'), '请输入有效金额');
    });

    test('支出缺分类 / 缺账户', () {
      expect(validateBillDraft(amount: 10, type: 'expense', accountId: 'a'),
          '请选择分类');
      expect(validateBillDraft(amount: 10, type: 'expense', categoryId: 'c'),
          '请选择账户');
    });

    test('收入同样要求分类 + 账户', () {
      expect(validateBillDraft(amount: 10, type: 'income'), '请选择分类');
      expect(
          validateBillDraft(
              amount: 10, type: 'income', categoryId: 'c', accountId: 'a'),
          isNull);
    });

    test('转账：缺转出 / 缺转入 / 两账户相同', () {
      expect(validateBillDraft(amount: 10, type: 'transfer'), '请选择转出账户');
      expect(validateBillDraft(amount: 10, type: 'transfer', accountId: 'a'),
          '请选择转入账户');
      expect(
          validateBillDraft(
              amount: 10, type: 'transfer', accountId: 'a', toAccountId: 'a'),
          '转出和转入账户不能相同');
      expect(
          validateBillDraft(
              amount: 10, type: 'transfer', accountId: 'a', toAccountId: 'b'),
          isNull);
    });

    test('合法支出草稿返回 null', () {
      expect(
          validateBillDraft(
              amount: 0.01, type: 'expense', categoryId: 'c', accountId: 'a'),
          isNull);
    });
  });

  // ── widget：金额校验 ─────────────────────────────────────────
  testWidgets('金额未输入点完成：提示有效金额且不调用任何接口', (tester) async {
    final api = FakeAddBillApi(
      categories: baseCategories,
      myAccounts: [accJson('a1'), accJson('a2')],
    );
    await pumpScreen(tester, api);

    await tapKey(tester, '✓');
    await tester.pump();

    expect(find.text('请输入有效金额'), findsOneWidget);
    expect(api.createdBills, isEmpty);
    expect(api.transfers, isEmpty);

    await dismissSnackBar(tester);
  });

  testWidgets('小数最多两位，第四位被忽略；00 键一次输入两个零', (tester) async {
    final api = FakeAddBillApi(
      categories: baseCategories,
      myAccounts: [accJson('a1'), accJson('a2')],
    );
    await pumpScreen(tester, api);

    await tapKey(tester, '1');
    await tapKey(tester, '.');
    await tapKey(tester, '2');
    await tapKey(tester, '3');
    await tapKey(tester, '4'); // 第三位小数，应被忽略
    expect(find.text('1.23'), findsOneWidget);

    // 退格清空后验证 00 键
    await tapKey(tester, '⌫');
    await tapKey(tester, '⌫');
    await tapKey(tester, '⌫');
    await tapKey(tester, '⌫');
    await tapKey(tester, '5');
    await tapKey(tester, '00');
    expect(find.text('500'), findsOneWidget);
  });

  // ── widget：支出提交参数 ─────────────────────────────────────
  testWidgets('支出：算式 34+23=57，createBill 参数正确', (tester) async {
    final api = FakeAddBillApi(
      categories: baseCategories,
      myAccounts: [accJson('a1'), accJson('a2')],
    );
    await pumpScreen(tester, api);

    await tapKey(tester, '3');
    await tapKey(tester, '4');
    await tapKey(tester, '+');
    await tapKey(tester, '2');
    await tapKey(tester, '3');
    expect(find.text('57'), findsOneWidget); // 头部合计

    await tapKey(tester, '✓');
    await pumpN(tester, 3);

    expect(api.createdBills, hasLength(1));
    final call = api.createdBills.single;
    expect(call['type'], 'expense');
    expect(call['amount'], 57.0);
    // 默认分类 = 第一个支出分类；默认账户 = 第一个账户
    expect(call['categoryId'], 'c-food');
    expect(call['accountId'], 'a1');
    // 备注（空串）也加密上传，dekVer 跟随 KeyChain 里的版本
    expect(call['noteCipher'], isA<String>());
    expect((call['noteCipher'] as String).isNotEmpty, isTrue);
    expect(call['noteDekVer'], 1);
    expect(api.transfers, isEmpty);
    expect(api.updatedBills, isEmpty);

    await finishSaveAnimation(tester);
  });

  // ── widget：类型切换联动 ─────────────────────────────────────
  testWidgets('切到收入 tab：分类联动为收入分类，提交 type=income', (tester) async {
    final api = FakeAddBillApi(
      categories: baseCategories,
      myAccounts: [accJson('a1'), accJson('a2')],
    );
    await pumpScreen(tester, api);

    await tapTab(tester, '收入');
    await pumpN(tester);

    // 分类 pill 与头部徽标都切换为收入分类「工资」
    expect(find.text('工资'), findsWidgets);

    await tapKey(tester, '1');
    await tapKey(tester, '00');
    await tapKey(tester, '✓');
    await pumpN(tester, 3);

    expect(api.createdBills, hasLength(1));
    final call = api.createdBills.single;
    expect(call['type'], 'income');
    expect(call['amount'], 100.0);
    expect(call['categoryId'], 'c-salary');

    await finishSaveAnimation(tester);
  });

  // ── widget：转账联动与提交 ───────────────────────────────────
  testWidgets('转账：默认转出/转入为前两个不同账户，transfer 参数正确', (tester) async {
    final api = FakeAddBillApi(
      categories: baseCategories,
      myAccounts: [accJson('a1'), accJson('a2')],
    );
    await pumpScreen(tester, api);

    await tapTab(tester, '转账');
    await pumpN(tester);

    // 转账模式下不再显示分类 pill
    expect(find.text('分类'), findsNothing);
    expect(find.text('转出'), findsOneWidget);
    expect(find.text('转入'), findsOneWidget);

    await tapKey(tester, '8');
    await tapKey(tester, '8');
    await tapKey(tester, '✓');
    await pumpN(tester, 3);

    expect(api.transfers, hasLength(1));
    final call = api.transfers.single;
    expect(call['fromAccountId'], 'a1');
    expect(call['toAccountId'], 'a2');
    expect(call['amount'], 88.0);
    // DEK 就位 → 两条轨迹备注密文都生成
    expect(call['fromNoteCipher'], isNotNull);
    expect(call['toNoteCipher'], isNotNull);
    expect(call['noteDekVer'], 1);
    // 转账不走 createBill
    expect(api.createdBills, isEmpty);

    await finishSaveAnimation(tester);
  });

  testWidgets('转账：账本只有一个账户时无法凑齐转入方，提示选择转入账户', (tester) async {
    final api = FakeAddBillApi(
      categories: baseCategories,
      myAccounts: [accJson('a1')],
      allAccounts: [accJson('a1')],
    );
    await pumpScreen(tester, api);

    await tapTab(tester, '转账');
    await pumpN(tester);

    await tapKey(tester, '5');
    await tapKey(tester, '0');
    await tapKey(tester, '✓');
    await tester.pump();

    expect(find.text('请选择转入账户'), findsOneWidget);
    expect(api.transfers, isEmpty);

    await dismissSnackBar(tester);
  });

  // ── widget：缺分类 / 缺账户 ──────────────────────────────────
  testWidgets('无可用分类：提示选择分类', (tester) async {
    final api = FakeAddBillApi(
      categories: const [],
      myAccounts: [accJson('a1')],
    );
    await pumpScreen(tester, api);

    await tapKey(tester, '1');
    await tapKey(tester, '0');
    await tapKey(tester, '✓');
    await tester.pump();

    expect(find.text('请选择分类'), findsOneWidget);
    expect(api.createdBills, isEmpty);

    await dismissSnackBar(tester);
  });

  testWidgets('无可用账户：提示选择账户', (tester) async {
    final api = FakeAddBillApi(
      categories: baseCategories,
      myAccounts: const [],
      allAccounts: const [],
    );
    await pumpScreen(tester, api);

    await tapKey(tester, '1');
    await tapKey(tester, '0');
    await tapKey(tester, '✓');
    await tester.pump();

    expect(find.text('请选择账户'), findsOneWidget);
    expect(api.createdBills, isEmpty);

    await dismissSnackBar(tester);
  });

  // ── widget：编辑普通账单 → 转账 = convertBill ────────────────
  testWidgets('编辑普通账单切到转账保存：调用 convertBill 转为账户间转账', (tester) async {
    final bill = Bill(
      id: 'b1',
      ledgerId: 'l1',
      type: 'expense',
      amount: 58.5,
      category: BillCategory(id: 'c-food', name: '餐饮'),
      account: BillAccount(id: 'a1', type: 'BANK'),
      date: DateTime(2025, 6, 1),
    );
    final api = FakeAddBillApi(
      categories: baseCategories,
      myAccounts: [accJson('a1'), accJson('a2')],
    );
    await pumpScreen(tester, api, bill: bill);

    expect(find.text('编辑账单'), findsOneWidget);

    await tapTab(tester, '转账');
    await pumpN(tester);

    // 金额沿用账单金额，直接保存 → convert
    await tapKey(tester, '✓');
    await pumpN(tester, 3);

    expect(api.converted, hasLength(1));
    final call = api.converted.single;
    expect(call['id'], 'b1');
    expect(call['to'], 'transfer');
    expect(call['toAccountId'], 'a2'); // 自动选了与本账户不同的转入方
    // convert 不走 transfer / createBill
    expect(api.transfers, isEmpty);
    expect(api.createdBills, isEmpty);

    await finishSaveAnimation(tester);
  });

  // ── widget：转账账单锁定 tab ─────────────────────────────────
  testWidgets('编辑转账账单：不可切回收/支 tab，弹回并提示', (tester) async {
    final bill = Bill(
      id: 'b2',
      ledgerId: 'l1',
      type: 'expense',
      amount: 200,
      category: BillCategory(id: 'c-food', name: '餐饮'),
      account: BillAccount(id: 'a1', type: 'BANK'),
      date: DateTime(2025, 6, 1),
      isTransfer: true,
    );
    final api = FakeAddBillApi(
      categories: baseCategories,
      myAccounts: [accJson('a1'), accJson('a2')],
    );
    await pumpScreen(tester, api, bill: bill);

    await tapTab(tester, '支出');
    await pumpN(tester);

    expect(find.text('转账账单不可改为收/支；如需变更请删除后重新记账'),
        findsOneWidget);
    // 仍是转账 UI（转出/转入 pills）
    expect(find.text('转出'), findsOneWidget);

    await dismissSnackBar(tester);
  });
}

/// 脚本化的 AddBillApi：记录所有写入调用，读取返回内存数据
class FakeAddBillApi extends AddBillApi {
  FakeAddBillApi({
    List<Map<String, dynamic>>? categories,
    List<Map<String, dynamic>>? myAccounts,
    List<Map<String, dynamic>>? allAccounts,
  })  : categories = categories ?? const [],
        myAccounts = myAccounts ?? const [],
        allAccounts = allAccounts ?? myAccounts ?? const [];

  final List<Map<String, dynamic>> categories;
  final List<Map<String, dynamic>> myAccounts;
  final List<Map<String, dynamic>> allAccounts;

  final List<Map<String, dynamic>> createdBills = [];
  final List<Map<String, dynamic>> updatedBills = [];
  final List<Map<String, dynamic>> transfers = [];
  final List<Map<String, dynamic>> converted = [];

  @override
  Future<Map<String, dynamic>> getCategories() async =>
      {'categories': categories};

  @override
  Future<Map<String, dynamic>> getAccounts({String? scope}) async =>
      {'accounts': scope == 'all' ? allAccounts : myAccounts};

  @override
  Future<Map<String, dynamic>> getBill(String id) async =>
      {'bill': <String, dynamic>{}};

  @override
  Future<Map<String, dynamic>> createBill({
    required String type,
    required double amount,
    required String categoryId,
    required String accountId,
    required String noteCipher,
    required int noteDekVer,
    DateTime? date,
  }) async {
    createdBills.add({
      'type': type,
      'amount': amount,
      'categoryId': categoryId,
      'accountId': accountId,
      'noteCipher': noteCipher,
      'noteDekVer': noteDekVer,
      'date': date,
    });
    return {'bill': <String, dynamic>{}};
  }

  @override
  Future<Map<String, dynamic>> updateBill(
    String id, {
    required String type,
    required double amount,
    required String categoryId,
    required String accountId,
    required String noteCipher,
    required int noteDekVer,
    DateTime? date,
    String? toAccountId,
  }) async {
    updatedBills.add({
      'id': id,
      'type': type,
      'amount': amount,
      'categoryId': categoryId,
      'accountId': accountId,
      'noteCipher': noteCipher,
      'noteDekVer': noteDekVer,
      'date': date,
      'toAccountId': toAccountId,
    });
    return {'bill': <String, dynamic>{}};
  }

  @override
  Future<Map<String, dynamic>> transfer({
    required String fromAccountId,
    required String toAccountId,
    required double amount,
    String? note,
    String? fromNoteCipher,
    String? toNoteCipher,
    int? noteDekVer,
  }) async {
    transfers.add({
      'fromAccountId': fromAccountId,
      'toAccountId': toAccountId,
      'amount': amount,
      'note': note,
      'fromNoteCipher': fromNoteCipher,
      'toNoteCipher': toNoteCipher,
      'noteDekVer': noteDekVer,
    });
    return {'ok': true};
  }

  @override
  Future<Map<String, dynamic>> convertBill(
    String id, {
    required String to,
    String? toAccountId,
  }) async {
    converted.add({'id': id, 'to': to, 'toAccountId': toAccountId});
    return {'ok': true};
  }
}
