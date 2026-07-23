import 'dart:convert';
import 'dart:typed_data';

import '../crypto/sm_crypto.dart';

/// 加密备份（.sikubak）编解码 + 数据包组装 / 重加密。
///
/// 隐私不变式：
///  - 备份文件里唯一的数据载荷是 payloadCipher = SM4(账本 DEK, 明文数据包)，
///    离开设备的永远是密文；
///  - 恢复时在本机解开 → 用「新账本的新 DEK」把各 cipher 字段重加密后
///    才上传服务端，服务端收到的一切仍是密文。
///
/// 文件格式（JSON）：
///   {
///     "version": 1,
///     "app": "siku",
///     "exportedAt": "<utc iso>",
///     "ledgerName": "...",          // 账本名不是敏感字段，便于挑选文件
///     "payloadCipher": "<base64>"   // iv(16)||ct||mac(32)，同 noteCipher 格式
///   }
///
/// 明文数据包（payloadCipher 解开后）：
///   { ledgerName, ledgerIcon, categories[], accounts[], bills[],
///     budgets[], goals[], loans[], recurring[] }
///   其中 cipher 字段均为「解密后的明文」+ 原 id，供恢复时重加密 + 服务端重映射。
class BackupCodec {
  BackupCodec._();

  static const fileVersion = 1;
  static const fileExtension = 'sikubak';

  // ── 单字段加解密 ─────────────────────────────────────────

  /// 解密一个 cipher 字段（账单备注 / 账户名 / 目标名…）。
  /// dekVer==0 表示服务端系统账单：cipher 直接是 base64(utf8 明文)。
  /// 解密失败抛异常（导出方应统计后提示，不静默吞）。
  static String decryptField(
    String? cipherBase64,
    int dekVer,
    Uint8List dek,
  ) {
    if (cipherBase64 == null || cipherBase64.isEmpty) return '';
    final raw = base64.decode(cipherBase64);
    if (dekVer == 0) {
      if (raw.isEmpty) return '';
      return utf8.decode(raw);
    }
    if (raw.length < 48) return ''; // iv16+mac32 起步，过短视为无内容
    return utf8.decode(SmCrypto.sm4Decrypt(raw, dek));
  }

  /// 用指定 DEK 加密一段明文，输出 base64（iv||ct||mac）
  static String encryptField(String plain, Uint8List dek) {
    final blob =
        SmCrypto.sm4Encrypt(Uint8List.fromList(utf8.encode(plain)), dek);
    return base64.encode(blob);
  }

  // ── 备份文件封包 / 解包 ──────────────────────────────────

  /// 明文数据包 → 备份文件 JSON Map
  static Map<String, dynamic> encodeFile({
    required Map<String, dynamic> bundle,
    required Uint8List dek,
    DateTime? exportedAt,
  }) {
    final plain = utf8.encode(jsonEncode(bundle));
    final blob = SmCrypto.sm4Encrypt(Uint8List.fromList(plain), dek);
    return {
      'version': fileVersion,
      'app': 'siku',
      'exportedAt':
          (exportedAt ?? DateTime.now().toUtc()).toIso8601String(),
      'ledgerName': bundle['ledgerName'],
      'ledgerIcon': bundle['ledgerIcon'],
      'payloadCipher': base64.encode(blob),
    };
  }

  /// 备份文件 JSON → 密文载荷字节（供逐个 DEK 尝试解密）。
  /// 格式非法抛 [FormatException]。
  static Uint8List payloadBlobOf(Map<String, dynamic> fileJson) {
    final v = fileJson['version'];
    if (v != fileVersion) {
      throw FormatException('不支持的备份文件版本：${v ?? '未知'}');
    }
    final cipher = fileJson['payloadCipher'];
    if (cipher is! String || cipher.isEmpty) {
      throw const FormatException('备份文件缺少数据载荷（payloadCipher）');
    }
    try {
      return Uint8List.fromList(base64.decode(cipher));
    } catch (_) {
      throw const FormatException('备份文件数据载荷不是合法 base64');
    }
  }

  /// 密文载荷 + DEK → 明文数据包。密钥错误时 SM4 完整性校验会抛异常。
  static Map<String, dynamic> decodePayload(Uint8List blob, Uint8List dek) {
    final plain = SmCrypto.sm4Decrypt(blob, dek);
    final obj = jsonDecode(utf8.decode(plain));
    if (obj is! Map<String, dynamic>) {
      throw const FormatException('备份数据包结构非法');
    }
    return obj;
  }

  // ── 导出：API 原始数据 → 明文数据包 ──────────────────────

  /// 把各列表 API 的原始 JSON 组装成明文数据包（cipher 字段本机解密）。
  /// 返回 bundle + 解密失败计数（调用方提示用户，不静默丢数据）。
  static ({Map<String, dynamic> bundle, int decryptFailures}) assembleBundle({
    required String ledgerName,
    String? ledgerIcon,
    required List<dynamic> categories,
    required List<dynamic> accounts,
    required List<dynamic> bills,
    required List<dynamic> budgets,
    required List<dynamic> goals,
    required List<dynamic> loans,
    required List<dynamic> recurring,
    required Uint8List dek,
  }) {
    var failures = 0;
    String dec(String? cipher, int dekVer) {
      try {
        return decryptField(cipher, dekVer, dek);
      } catch (_) {
        failures++;
        return '';
      }
    }

    final bundle = <String, dynamic>{
      'ledgerName': ledgerName,
      'ledgerIcon': ledgerIcon,
      // 分类全量导出（含系统分类：恢复端按名称复用，跨实例也能对上）
      'categories': [
        for (final c in categories)
          {
            'id': c['id'],
            'name': c['name'],
            'type': c['type'],
            'icon': c['icon'],
            'color': c['color'],
            'isSystem': c['isSystem'] == true,
            'parentId': c['parentId'],
            'parentName': c['parentName'],
          },
      ],
      'accounts': [
        for (final a in accounts)
          {
            'id': a['id'],
            'name': dec(a['nameCipher'] as String?,
                (a['nameDekVer'] as num?)?.toInt() ?? 1),
            'type': a['type'],
            'balance': a['balance'] ?? 0,
            'initialBalance': a['initialBalance'] ?? 0,
            'icon': a['icon'],
            'color': a['color'],
            'ownerId': a['ownerId'],
            'statementDay': a['statementDay'],
            'dueDay': a['dueDay'],
            'creditLimit': a['creditLimit'],
            'interestRate': a['interestRate'],
            'loanPrincipal': a['loanPrincipal'],
            'loanTermMonths': a['loanTermMonths'],
            'firstPaymentDate': a['firstPaymentDate'],
            'repaymentMethod': a['repaymentMethod'],
            'autoDepositDay': a['autoDepositDay'],
            'autoDepositAmount': a['autoDepositAmount'],
            'autoDepositCategoryId': a['autoDepositCategoryId'],
            'lastAutoProcessedAt': a['lastAutoProcessedAt'],
            'createdAt': a['createdAt'],
            'updatedAt': a['updatedAt'],
          },
      ],
      'bills': [
        for (final b in bills)
          {
            'id': b['id'],
            // 账单行的 account/category 是嵌套对象，取其 id 即可
            'accountId': b['accountId'] ?? (b['account'] as Map?)?['id'],
            'categoryId':
                b['categoryId'] ?? (b['category'] as Map?)?['id'],
            'type': b['type'],
            'amount': b['amount'],
            'note': dec(b['noteCipher'] as String?,
                (b['noteDekVer'] as num?)?.toInt() ?? 1),
            'date': b['date'],
            'externalId': b['externalId'],
            'source': b['source'],
            'isTransfer': b['isTransfer'] == true,
            'bankBalance': b['bankBalance'],
            'merchantHash': b['merchantHash'],
            'createdAt': b['createdAt'],
            'updatedAt': b['updatedAt'],
          },
      ],
      'budgets': [
        for (final b in budgets)
          {
            'id': b['id'],
            'categoryId': b['categoryId'],
            'amount': b['amount'],
            'period': b['period'],
            'startDate': b['startDate'],
            'createdAt': b['createdAt'],
            'updatedAt': b['updatedAt'],
          },
      ],
      'goals': [
        for (final g in goals)
          {
            'id': g['id'],
            'name': dec(g['nameCipher'] as String?,
                (g['nameDekVer'] as num?)?.toInt() ?? 1),
            'targetAmount': g['targetAmount'],
            'startDate': g['startDate'],
            'accountId': g['accountId'],
            'initialBalance': g['initialBalance'],
            'deadline': g['deadline'],
            'icon': g['icon'],
            'color': g['color'],
            'isCompleted': g['isCompleted'] == true,
            'completedAt': g['completedAt'],
            'createdAt': g['createdAt'],
            'updatedAt': g['updatedAt'],
          },
      ],
      'loans': [
        for (final l in loans)
          {
            'id': l['id'],
            'direction': l['direction'],
            'amount': l['amount'],
            'repaidAmount': l['repaidAmount'] ?? 0,
            'accountId': l['accountId'],
            'note': dec(l['noteCipher'] as String?,
                (l['noteDekVer'] as num?)?.toInt() ?? 1),
            'voucherKey': l['voucherKey'],
            'date': l['date'],
            'settledAt': l['settledAt'],
            'createdAt': l['createdAt'],
          },
      ],
      'recurring': [
        for (final r in recurring)
          {
            'id': r['id'],
            'categoryId': r['categoryId'],
            'accountId': r['accountId'],
            'type': r['type'],
            'amount': r['amount'],
            'note': dec(r['noteCipher'] as String?,
                (r['noteDekVer'] as num?)?.toInt() ?? 1),
            'cycleType': r['cycleType'],
            'cycleDay': r['cycleDay'],
            'nextDate': r['nextDate'],
            'isActive': r['isActive'] ?? true,
            'isAuto': r['isAuto'] ?? false,
            'confidence': r['confidence'],
            'createdAt': r['createdAt'],
            'updatedAt': r['updatedAt'],
          },
      ],
    };
    return (bundle: bundle, decryptFailures: failures);
  }

  // ── 恢复：明文数据包 + 新 DEK → import-backup 请求体 ─────

  /// 用「新账本 DEK」把数据包各 cipher 字段重加密，组装成
  /// POST /ledgers/import-backup 的请求体。明文字段（金额/日期/类型）
  /// 与服务端日常存储口径一致；id 保留原值，由服务端重映射。
  static Map<String, dynamic> buildImportBody({
    required Map<String, dynamic> bundle,
    required String newLedgerName,
    String? newLedgerIcon,
    required String dekWrapped,
    required Uint8List newDek,
  }) {
    String enc(String? plain) => encryptField(plain ?? '', newDek);

    List<dynamic> rows(String key) =>
        (bundle[key] as List?) ?? const [];

    return {
      'name': newLedgerName,
      'icon': newLedgerIcon ?? bundle['ledgerIcon'] ?? '📒',
      'dekWrapped': dekWrapped,
      'categories': [
        for (final c in rows('categories'))
          {
            'id': c['id'],
            'name': c['name'],
            'type': c['type'],
            'icon': c['icon'],
            'color': c['color'],
            'parentId': c['parentId'],
            'parentName': c['parentName'],
            'isSystem': c['isSystem'] == true,
          },
      ],
      'accounts': [
        for (final a in rows('accounts'))
          {
            'id': a['id'],
            'nameCipher': enc(a['name'] as String?),
            'nameDekVer': 1,
            'type': a['type'],
            'balance': a['balance'] ?? 0,
            'initialBalance': a['initialBalance'] ?? 0,
            'icon': a['icon'],
            'color': a['color'],
            'ownerId': a['ownerId'],
            'statementDay': a['statementDay'],
            'dueDay': a['dueDay'],
            'creditLimit': a['creditLimit'],
            'interestRate': a['interestRate'],
            'loanPrincipal': a['loanPrincipal'],
            'loanTermMonths': a['loanTermMonths'],
            'firstPaymentDate': a['firstPaymentDate'],
            'repaymentMethod': a['repaymentMethod'],
            'autoDepositDay': a['autoDepositDay'],
            'autoDepositAmount': a['autoDepositAmount'],
            'autoDepositCategoryId': a['autoDepositCategoryId'],
            'lastAutoProcessedAt': a['lastAutoProcessedAt'],
            'createdAt': a['createdAt'],
            'updatedAt': a['updatedAt'],
          },
      ],
      'bills': [
        for (final b in rows('bills'))
          {
            'id': b['id'],
            'accountId': b['accountId'],
            'categoryId': b['categoryId'],
            'type': b['type'],
            'amount': b['amount'],
            'noteCipher': enc(b['note'] as String?),
            'noteDekVer': 1,
            'date': b['date'],
            'externalId': b['externalId'],
            'source': b['source'] ?? 'manual',
            'isTransfer': b['isTransfer'] == true,
            'bankBalance': b['bankBalance'],
            'merchantHash': b['merchantHash'],
            'createdAt': b['createdAt'],
            'updatedAt': b['updatedAt'],
          },
      ],
      'budgets': [
        for (final b in rows('budgets'))
          {
            'id': b['id'],
            'categoryId': b['categoryId'],
            'amount': b['amount'],
            'period': b['period'],
            'startDate': b['startDate'],
            'createdAt': b['createdAt'],
            'updatedAt': b['updatedAt'],
          },
      ],
      'goals': [
        for (final g in rows('goals'))
          {
            'id': g['id'],
            'nameCipher': enc(g['name'] as String?),
            'nameDekVer': 1,
            'targetAmount': g['targetAmount'],
            'startDate': g['startDate'],
            'accountId': g['accountId'],
            'initialBalance': g['initialBalance'],
            'deadline': g['deadline'],
            'icon': g['icon'],
            'color': g['color'],
            'isCompleted': g['isCompleted'] == true,
            'completedAt': g['completedAt'],
            'createdAt': g['createdAt'],
            'updatedAt': g['updatedAt'],
          },
      ],
      'loans': [
        for (final l in rows('loans'))
          {
            'id': l['id'],
            'direction': l['direction'],
            'amount': l['amount'],
            'repaidAmount': l['repaidAmount'] ?? 0,
            'accountId': l['accountId'],
            // Loan.noteCipher 是 String 列；无备注保持 null
            'noteCipher': (l['note'] as String?)?.isNotEmpty == true
                ? enc(l['note'] as String?)
                : null,
            'noteDekVer': 1,
            'voucherKey': l['voucherKey'],
            'date': l['date'],
            'settledAt': l['settledAt'],
            'createdAt': l['createdAt'],
          },
      ],
      'recurring': [
        for (final r in rows('recurring'))
          {
            'id': r['id'],
            'categoryId': r['categoryId'],
            'accountId': r['accountId'],
            'type': r['type'] ?? 'expense',
            'amount': r['amount'],
            'noteCipher': (r['note'] as String?)?.isNotEmpty == true
                ? enc(r['note'] as String?)
                : null,
            'noteDekVer': 1,
            'cycleType': r['cycleType'],
            'cycleDay': r['cycleDay'],
            'nextDate': r['nextDate'],
            'isActive': r['isActive'] ?? true,
            'isAuto': r['isAuto'] ?? false,
            'confidence': r['confidence'],
            'createdAt': r['createdAt'],
            'updatedAt': r['updatedAt'],
          },
      ],
    };
  }

  /// 备份文件名：司库备份-账本名-YYYYMMDD.sikubak（过滤路径非法字符）
  static String fileNameFor(String ledgerName, DateTime day) {
    final safe = ledgerName
        .replaceAll(RegExp(r'[\\/:*?"<>|\s]+'), '_')
        .trim();
    final y = day.year.toString().padLeft(4, '0');
    final m = day.month.toString().padLeft(2, '0');
    final d = day.day.toString().padLeft(2, '0');
    return '司库备份-${safe.isEmpty ? '账本' : safe}-$y$m$d.$fileExtension';
  }
}
