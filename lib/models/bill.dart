import 'dart:convert';

import '../crypto/key_chain.dart';
import '../widgets/amount_text.dart';

/// 全局金额格式化统一走 widgets/amount_text.dart 的 formatAmount（千分位）。
String fmtMoney(double amount) => '¥${formatAmount(amount)}';
String fmtMoneyInt(double amount) => '¥${formatAmount(amount, decimals: 0)}';

class BillCategory {
  final String id;
  final String name;
  final String? icon;
  final String? color;

  BillCategory({required this.id, required this.name, this.icon, this.color});

  factory BillCategory.fromJson(Map<String, dynamic> j) => BillCategory(
        id: j['id'] as String,
        name: j['name'] as String,
        icon: j['icon'] as String?,
        color: j['color'] as String?,
      );
}

class BillAccount {
  final String id;
  /// 账户名密文（用账本 DEK 解）
  final String? nameCipher;
  final int nameDekVer;
  final String type;

  BillAccount({
    required this.id,
    this.nameCipher,
    this.nameDekVer = 1,
    required this.type,
  });

  factory BillAccount.fromJson(Map<String, dynamic> j) => BillAccount(
        id: j['id'] as String,
        nameCipher: j['nameCipher'] as String?,
        nameDekVer: (j['nameDekVer'] as num?)?.toInt() ?? 1,
        type: j['type'] as String,
      );

  /// 客户端用账本 DEK 解出账户名（需要外部告知 ledgerId）
  String nameOf(String ledgerId) {
    if (nameCipher == null) return '【未命名】';
    return KeyChain.instance.decryptText(
      ledgerId: ledgerId,
      cipherBase64: nameCipher!,
      dekVer: nameDekVer,
      systemFallback: '账户',
    );
  }
}

/// 记账人（共享账本下区分用）
class BillUser {
  final String id;
  final String username;
  final String? nickname;
  BillUser({
    required this.id,
    required this.username,
    this.nickname,
  });

  factory BillUser.fromJson(Map<String, dynamic> j) => BillUser(
        id: j['id'] as String,
        username: j['username'] as String? ?? '',
        nickname: j['nickname'] as String?,
      );

  /// 优先昵称
  String get displayName {
    final n = (nickname ?? '').trim();
    if (n.isNotEmpty) return n;
    return username;
  }
}

class Bill {
  final String id;
  final String ledgerId;
  final String type;
  final double amount;
  final BillCategory category;
  final BillAccount account;
  /// 备注密文（base64） + 加密版本（0 = 系统占位）
  final String? noteCipher;
  final int noteDekVer;
  final DateTime date;
  final BillUser? user; // 记账人
  /// 是否转账/借贷类账单（不计收支）；编辑时用于隐藏"转为借贷/转账"入口
  final bool isTransfer;
  /// 来源渠道：manual / alipay / wechat / stock / transfer / reconcile
  /// stock = 股票每日结算的纸面盈亏（只读，不可编辑/删除）
  final String source;

  Bill({
    required this.id,
    required this.ledgerId,
    required this.type,
    required this.amount,
    required this.category,
    required this.account,
    this.noteCipher,
    this.noteDekVer = 1,
    required this.date,
    this.user,
    this.isTransfer = false,
    this.source = 'manual',
  });

  factory Bill.fromJson(Map<String, dynamic> json) => Bill(
        id: json['id'] as String,
        ledgerId: (json['ledgerId'] as String?) ?? '',
        type: json['type'] as String,
        amount: (json['amount'] as num).toDouble(),
        category: BillCategory.fromJson(json['category'] as Map<String, dynamic>),
        account: BillAccount.fromJson(json['account'] as Map<String, dynamic>),
        noteCipher: json['noteCipher'] as String?,
        noteDekVer: (json['noteDekVer'] as num?)?.toInt() ?? 1,
        // 后端存的是 UTC，解析后转本地时区，否则显示的时分会差 8 小时（如晚上 21:05 显示成 13:05）
        date: DateTime.parse(json['date'] as String).toLocal(),
        user: json['user'] is Map<String, dynamic>
            ? BillUser.fromJson(json['user'] as Map<String, dynamic>)
            : null,
        isTransfer: json['isTransfer'] as bool? ?? false,
        source: json['source'] as String? ?? 'manual',
      );

  /// 客户端用账本 DEK 解出来的备注
  String get note {
    if (noteCipher == null || noteCipher!.isEmpty) return '';
    // noteDekVer==0：系统/明文备注（服务端无法加密的自动账单）。
    // noteCipher 存 UTF-8 明文；旧的"自动入账"为 0 字节占位。
    if (noteDekVer == 0) {
      try {
        final bytes = base64Decode(noteCipher!);
        if (bytes.isEmpty) return '自动入账';
        return utf8.decode(bytes);
      } catch (_) {
        return '自动入账';
      }
    }
    // 加密备注：空/过短密文（iv16+mac32 起步）视为无备注，避免显示"解密失败"
    try {
      if (base64Decode(noteCipher!).length < 48) return '';
    } catch (_) {
      return '';
    }
    return KeyChain.instance.decryptText(
      ledgerId: ledgerId,
      cipherBase64: noteCipher!,
      dekVer: noteDekVer,
    );
  }

  bool get isIncome => type == 'income';
  String get amountText =>
      '${isIncome ? '+' : '-'}${fmtMoney(amount)}';
  String? get recorderName => user?.displayName;
}
