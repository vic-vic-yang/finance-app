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
  final String name;
  final String type;

  BillAccount({required this.id, required this.name, required this.type});

  factory BillAccount.fromJson(Map<String, dynamic> j) => BillAccount(
        id: j['id'] as String,
        name: j['name'] as String,
        type: j['type'] as String,
      );
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
  final String type;
  final double amount;
  final BillCategory category;
  final BillAccount account;
  final String note;
  final DateTime date;
  final BillUser? user; // 记账人

  Bill({
    required this.id,
    required this.type,
    required this.amount,
    required this.category,
    required this.account,
    required this.note,
    required this.date,
    this.user,
  });

  factory Bill.fromJson(Map<String, dynamic> json) => Bill(
        id: json['id'] as String,
        type: json['type'] as String,
        amount: (json['amount'] as num).toDouble(),
        category: BillCategory.fromJson(json['category'] as Map<String, dynamic>),
        account: BillAccount.fromJson(json['account'] as Map<String, dynamic>),
        note: json['note'] as String? ?? '',
        date: DateTime.parse(json['date'] as String),
        user: json['user'] is Map<String, dynamic>
            ? BillUser.fromJson(json['user'] as Map<String, dynamic>)
            : null,
      );

  bool get isIncome => type == 'income';
  String get amountText => '${isIncome ? '+' : '-'}¥${amount.toStringAsFixed(2)}';
  /// 记账人显示名（昵称优先，回退用户名）
  String? get recorderName => user?.displayName;
}
