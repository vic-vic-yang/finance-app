class Ledger {
  final String id;
  final String name;
  final String? icon;
  final bool isPersonal;
  final String ownerId;
  final String ownerName;
  final String? ownerNickname;
  final String role; // owner / member
  final int memberCount;
  final int billCount;

  Ledger({
    required this.id,
    required this.name,
    this.icon,
    required this.isPersonal,
    required this.ownerId,
    required this.ownerName,
    this.ownerNickname,
    required this.role,
    required this.memberCount,
    required this.billCount,
  });

  factory Ledger.fromJson(Map<String, dynamic> j) => Ledger(
        id: j['id'] as String,
        name: j['name'] as String,
        icon: j['icon'] as String?,
        isPersonal: j['isPersonal'] as bool? ?? false,
        ownerId: j['ownerId'] as String,
        ownerName: j['ownerName'] as String? ?? '',
        ownerNickname: j['ownerNickname'] as String?,
        role: j['role'] as String? ?? 'member',
        memberCount: (j['memberCount'] as num?)?.toInt() ?? 1,
        billCount: (j['billCount'] as num?)?.toInt() ?? 0,
      );

  bool get isOwner => role == 'owner';
  bool get isShared => memberCount > 1;
  String get displayIcon => icon ?? (isPersonal ? '💰' : '📒');

  /// 账本创建者显示名（昵称优先，回退用户名）
  String get ownerDisplayName {
    final n = (ownerNickname ?? '').trim();
    if (n.isNotEmpty) return n;
    return ownerName;
  }
}

class LedgerMember {
  final String id;
  final String userId;
  final String username;
  final String? nickname;
  final String role;
  final DateTime joinedAt;

  LedgerMember({
    required this.id,
    required this.userId,
    required this.username,
    this.nickname,
    required this.role,
    required this.joinedAt,
  });

  factory LedgerMember.fromJson(Map<String, dynamic> j) => LedgerMember(
        id: j['id'] as String,
        userId: j['userId'] as String,
        username: j['username'] as String,
        nickname: j['nickname'] as String?,
        role: j['role'] as String,
        joinedAt: DateTime.parse(j['joinedAt'] as String),
      );

  bool get isOwner => role == 'owner';

  /// 显示名（昵称优先，回退用户名）
  String get displayName {
    final n = (nickname ?? '').trim();
    if (n.isNotEmpty) return n;
    return username;
  }
}
