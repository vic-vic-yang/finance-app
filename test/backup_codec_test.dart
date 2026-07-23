import 'dart:convert';
import 'dart:typed_data';

import 'package:finance_app/crypto/sm_crypto.dart';
import 'package:finance_app/services/backup_codec.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final dek = SmCrypto.generateSm4Key();
  final newDek = SmCrypto.generateSm4Key();

  String enc(String plain, [Uint8List? k]) =>
      BackupCodec.encryptField(plain, k ?? dek);

  /// 造一份「API 原始返回」形态的数据（cipher 字段为 base64 密文）
  Map<String, List<dynamic>> fakeApiData() => {
        'categories': [
          {
            'id': 'c1',
            'name': '餐饮',
            'type': 'expense',
            'icon': '🍜',
            'color': '#F44336',
            'isSystem': true,
            'parentId': null,
            'parentName': null,
          },
          {
            'id': 'c2',
            'name': '早餐',
            'type': 'expense',
            'icon': '🥐',
            'color': null,
            'isSystem': true,
            'parentId': 'c1',
            'parentName': '餐饮',
          },
          {
            'id': 'c3',
            'name': '自定义',
            'type': 'income',
            'icon': null,
            'color': null,
            'isSystem': false,
            'parentId': null,
            'parentName': null,
          },
        ],
        'accounts': [
          {
            'id': 'a1',
            'nameCipher': enc('招行工资卡'),
            'nameDekVer': 1,
            'type': 'BANK',
            'balance': 1234.56,
            'initialBalance': 100.0,
            'icon': '💳',
            'color': null,
            'ownerId': 'user-me',
            'statementDay': null,
            'dueDay': null,
            'creditLimit': null,
            'interestRate': null,
            'loanPrincipal': null,
            'loanTermMonths': null,
            'firstPaymentDate': null,
            'repaymentMethod': null,
            'autoDepositDay': 5,
            'autoDepositAmount': 8000,
            'autoDepositCategoryId': 'c3',
            'lastAutoProcessedAt': '2025-12-05T00:00:00.000Z',
            'createdAt': '2025-01-01T00:00:00.000Z',
            'updatedAt': '2025-12-01T00:00:00.000Z',
          },
        ],
        'bills': [
          {
            'id': 'b1',
            'type': 'expense',
            'amount': 35.5,
            'noteCipher': enc('楼下早餐店'),
            'noteDekVer': 1,
            'date': '2025-12-01T08:00:00.000Z',
            'externalId': null,
            'source': 'manual',
            'isTransfer': false,
            'bankBalance': null,
            'merchantHash': null,
            'createdAt': '2025-12-01T08:01:00.000Z',
            'updatedAt': '2025-12-01T08:01:00.000Z',
            'account': {'id': 'a1'},
            'category': {'id': 'c2'},
          },
          {
            // dekVer==0：服务端系统账单，cipher 是 base64(utf8 明文)
            'id': 'b2',
            'type': 'income',
            'amount': 8000,
            'noteCipher': base64.encode(utf8.encode('自动入账')),
            'noteDekVer': 0,
            'date': '2025-12-05T00:00:00.000Z',
            'source': 'manual',
            'isTransfer': false,
            'createdAt': '2025-12-05T00:00:00.000Z',
            'updatedAt': '2025-12-05T00:00:00.000Z',
            'account': {'id': 'a1'},
            'category': {'id': 'c3'},
          },
        ],
        'budgets': [
          {
            'id': 'bg1',
            'categoryId': 'c1',
            'amount': 500,
            'period': 'MONTHLY',
            'startDate': '2025-12-01',
            'createdAt': '2025-11-01T00:00:00.000Z',
            'updatedAt': '2025-11-01T00:00:00.000Z',
          },
        ],
        'goals': [
          {
            'id': 'g1',
            'nameCipher': enc('日本旅行基金'),
            'nameDekVer': 1,
            'targetAmount': 20000,
            'startDate': '2025-06-01T00:00:00.000Z',
            'accountId': 'a1',
            'initialBalance': 0,
            'deadline': null,
            'icon': '✈️',
            'color': null,
            'isCompleted': false,
            'completedAt': null,
            'createdAt': '2025-06-01T00:00:00.000Z',
            'updatedAt': '2025-06-01T00:00:00.000Z',
          },
        ],
        'loans': [
          {
            'id': 'l1',
            'direction': 'lend',
            'amount': 500,
            'repaidAmount': 100,
            'accountId': 'a1',
            'noteCipher': enc('借给老王'),
            'noteDekVer': 1,
            'voucherKey': null,
            'date': '2025-11-01T00:00:00.000Z',
            'settledAt': null,
            'createdAt': '2025-11-01T00:00:00.000Z',
          },
        ],
        'recurring': [
          {
            'id': 'r1',
            'categoryId': 'c1',
            'accountId': 'a1',
            'type': 'expense',
            'amount': 15,
            'noteCipher': enc('视频会员'),
            'noteDekVer': 1,
            'cycleType': 'monthly',
            'cycleDay': 1,
            'nextDate': '2026-01-01T00:00:00.000Z',
            'isActive': true,
            'isAuto': false,
            'confidence': null,
            'createdAt': '2025-01-01T00:00:00.000Z',
            'updatedAt': '2025-01-01T00:00:00.000Z',
          },
        ],
      };

  Map<String, dynamic> assemble() {
    final data = fakeApiData();
    final (:bundle, :decryptFailures) = BackupCodec.assembleBundle(
      ledgerName: '家庭账本',
      ledgerIcon: '🏠',
      categories: data['categories']!,
      accounts: data['accounts']!,
      bills: data['bills']!,
      budgets: data['budgets']!,
      goals: data['goals']!,
      loans: data['loans']!,
      recurring: data['recurring']!,
      dek: dek,
    );
    expect(decryptFailures, 0);
    return bundle;
  }

  group('组装明文数据包', () {
    test('cipher 字段全部解密为明文；嵌套 account/category 取 id', () {
      final bundle = assemble();
      expect((bundle['accounts'] as List)[0]['name'], '招行工资卡');
      expect((bundle['goals'] as List)[0]['name'], '日本旅行基金');
      expect((bundle['loans'] as List)[0]['note'], '借给老王');
      expect((bundle['recurring'] as List)[0]['note'], '视频会员');
      final bills = bundle['bills'] as List;
      expect(bills[0]['note'], '楼下早餐店');
      expect(bills[0]['accountId'], 'a1');
      expect(bills[0]['categoryId'], 'c2');
      // dekVer==0 的系统账单明文也解得出
      expect(bills[1]['note'], '自动入账');
    });
  });

  group('备份文件封包 / 解包 roundtrip', () {
    test('encodeFile → payloadBlobOf → decodePayload 还原明文数据包', () {
      final bundle = assemble();
      final file = BackupCodec.encodeFile(bundle: bundle, dek: dek);
      // 文件里没有明文：payloadCipher 之外只有元信息
      expect(file['version'], 1);
      expect(file['ledgerName'], '家庭账本');
      expect(file.keys,
          containsAll(['version', 'app', 'exportedAt', 'ledgerName', 'payloadCipher']));
      final fileStr = jsonEncode(file);
      expect(fileStr.contains('招行工资卡'), isFalse);
      expect(fileStr.contains('楼下早餐店'), isFalse);
      expect(fileStr.contains('日本旅行基金'), isFalse);

      final blob = BackupCodec.payloadBlobOf(file);
      final restored = BackupCodec.decodePayload(blob, dek);
      expect(restored['ledgerName'], '家庭账本');
      expect((restored['accounts'] as List)[0]['name'], '招行工资卡');
      expect((restored['bills'] as List).length, 2);
    });

    test('用错误的 DEK 解密 → HMAC 校验失败抛异常', () {
      final bundle = assemble();
      final file = BackupCodec.encodeFile(bundle: bundle, dek: dek);
      final blob = BackupCodec.payloadBlobOf(file);
      expect(() => BackupCodec.decodePayload(blob, SmCrypto.generateSm4Key()),
          throwsStateError);
    });

    test('版本不符 / 缺 payloadCipher → FormatException', () {
      expect(() => BackupCodec.payloadBlobOf({'version': 99}),
          throwsFormatException);
      expect(
          () => BackupCodec.payloadBlobOf({'version': 1, 'payloadCipher': ''}),
          throwsFormatException);
      expect(
          () => BackupCodec.payloadBlobOf({'version': 1, 'payloadCipher': '!!!'}),
          throwsFormatException);
    });
  });

  group('恢复重加密', () {
    test('buildImportBody：cipher 字段用新 DEK 重加密，新 DEK 可解出原文', () {
      final bundle = assemble();
      final body = BackupCodec.buildImportBody(
        bundle: bundle,
        newLedgerName: '家庭账本（恢复）',
        dekWrapped: 'd3JhcHBlZA==',
        newDek: newDek,
      );
      expect(body['name'], '家庭账本（恢复）');
      expect(body['dekWrapped'], 'd3JhcHBlZA==');

      String dec(String cipher) =>
          BackupCodec.decryptField(cipher, 1, newDek);
      final accounts = body['accounts'] as List;
      expect(dec(accounts[0]['nameCipher'] as String), '招行工资卡');
      expect(accounts[0]['nameDekVer'], 1);
      // 原 id 保留（服务端负责重映射）
      expect(accounts[0]['id'], 'a1');
      expect(accounts[0]['ownerId'], 'user-me');

      final bills = body['bills'] as List;
      expect(dec(bills[0]['noteCipher'] as String), '楼下早餐店');
      // dekVer==0 的系统账单也被规范化成新 DEK 密文
      expect(dec(bills[1]['noteCipher'] as String), '自动入账');
      expect(bills[1]['noteDekVer'], 1);
      expect(bills[0]['accountId'], 'a1');
      expect(bills[0]['categoryId'], 'c2');

      final goals = body['goals'] as List;
      expect(dec(goals[0]['nameCipher'] as String), '日本旅行基金');

      final loans = body['loans'] as List;
      expect(dec(loans[0]['noteCipher'] as String), '借给老王');

      final recurring = body['recurring'] as List;
      expect(dec(recurring[0]['noteCipher'] as String), '视频会员');

      // 密文与旧 DEK 不通用（旧 DEK 解不开新密文）
      expect(() => BackupCodec.decryptField(
          bills[0]['noteCipher'] as String, 1, dek), throwsStateError);
    });

    test('空备注的借贷 / 周期账单恢复为 noteCipher=null', () {
      final bundle = assemble();
      (bundle['loans'] as List)[0]['note'] = '';
      (bundle['recurring'] as List)[0]['note'] = '';
      final body = BackupCodec.buildImportBody(
        bundle: bundle,
        newLedgerName: 'x',
        dekWrapped: 'd3JhcHBlZA==',
        newDek: newDek,
      );
      expect((body['loans'] as List)[0]['noteCipher'], isNull);
      expect((body['recurring'] as List)[0]['noteCipher'], isNull);
    });
  });

  group('辅助', () {
    test('备份文件名：司库备份-账本名-YYYYMMDD.sikubak，非法字符替换', () {
      final name = BackupCodec.fileNameFor('家庭/账本: A', DateTime(2026, 1, 5));
      expect(name, '司库备份-家庭_账本_A-20260105.sikubak');
    });
  });
}
