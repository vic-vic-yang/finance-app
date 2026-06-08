import 'package:intl/intl.dart';

import '../crypto/key_chain.dart';

final _moneyFmt = NumberFormat('#,##0.00');
final _moneyFmtInt = NumberFormat('#,##0');

String fmtMoney(double amount) => '¥${_moneyFmt.format(amount)}';
String fmtMoneyInt(double amount) => '¥${_moneyFmtInt.format(amount)}';

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
      );

  /// 客户端用账本 DEK 解出来的备注
  String get note {
    if (noteCipher == null) return '';
    if (noteDekVer == 0) return '自动入账';
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
