import '../crypto/key_chain.dart';

/// 绑定的账户信息（从服务端返回，客户端解密名称）
class GoalAccount {
  final String id;
  final String nameCipher;
  final int nameDekVer;
  final double balance;
  final bool balanceVisible;

  GoalAccount({
    required this.id,
    required this.nameCipher,
    required this.nameDekVer,
    required this.balance,
    required this.balanceVisible,
  });

  factory GoalAccount.fromJson(Map<String, dynamic> j) => GoalAccount(
        id: j['id'] as String,
        nameCipher: j['nameCipher'] as String? ?? '',
        nameDekVer: (j['nameDekVer'] as num?)?.toInt() ?? 1,
        balance: (j['balance'] as num?)?.toDouble() ?? 0,
        balanceVisible: j['balanceVisible'] as bool? ?? false,
      );

  /// 客户端解密账户名
  String name(String ledgerId) => nameCipher.isEmpty
      ? '账户'
      : KeyChain.instance.decryptText(
          ledgerId: ledgerId,
          cipherBase64: nameCipher,
          dekVer: nameDekVer,
          systemFallback: '账户',
        );
}

class SavingsGoal {
  final String id;
  final String userId;
  final String ledgerId;
  /// 目标名密文 base64
  final String nameCipher;
  final int nameDekVer;
  final double targetAmount;
  final double currentSaved;
  /// 0..999（>1 表示超额完成）
  final double progress;
  /// 按当前速度预计还需多少天达成（已达成返回 null）
  final int? etaDays;
  final DateTime startDate;
  final DateTime? deadline;
  final String? icon;
  final String? color;
  final bool isCompleted;
  final DateTime? completedAt;
  final DateTime createdAt;

  // ── 账户绑定 ──
  final String? accountId;
  final double? initialBalance;
  /// null=未绑定, true=计入现有余额, false=从零开始
  final bool? useExistingBalance;
  final GoalAccount? account;

  SavingsGoal({
    required this.id,
    required this.userId,
    required this.ledgerId,
    required this.nameCipher,
    required this.nameDekVer,
    required this.targetAmount,
    required this.currentSaved,
    required this.progress,
    this.etaDays,
    required this.startDate,
    this.deadline,
    this.icon,
    this.color,
    required this.isCompleted,
    this.completedAt,
    required this.createdAt,
    this.accountId,
    this.initialBalance,
    this.useExistingBalance,
    this.account,
  });

  /// 客户端解密的目标名
  String get name => KeyChain.instance.decryptText(
        ledgerId: ledgerId,
        cipherBase64: nameCipher,
        dekVer: nameDekVer,
        systemFallback: '目标',
      );

  /// 绑定的账户名（解密后）
  String? accountName() {
    if (account == null) return null;
    return account!.name(ledgerId);
  }

  factory SavingsGoal.fromJson(Map<String, dynamic> j) => SavingsGoal(
        id: j['id'] as String,
        userId: j['userId'] as String,
        ledgerId: j['ledgerId'] as String,
        nameCipher: j['nameCipher'] as String,
        nameDekVer: (j['nameDekVer'] as num).toInt(),
        targetAmount: (j['targetAmount'] as num).toDouble(),
        currentSaved: (j['currentSaved'] as num?)?.toDouble() ?? 0,
        progress: (j['progress'] as num?)?.toDouble() ?? 0,
        etaDays: (j['etaDays'] as num?)?.toInt(),
        startDate: DateTime.parse(j['startDate'] as String),
        deadline: j['deadline'] == null
            ? null
            : DateTime.tryParse(j['deadline'] as String),
        icon: j['icon'] as String?,
        color: j['color'] as String?,
        isCompleted: j['isCompleted'] as bool? ?? false,
        completedAt: j['completedAt'] == null
            ? null
            : DateTime.tryParse(j['completedAt'] as String),
        createdAt: DateTime.parse(j['createdAt'] as String),
        accountId: j['accountId'] as String?,
        initialBalance: (j['initialBalance'] as num?)?.toDouble(),
        useExistingBalance: j['useExistingBalance'] as bool?,
        account: j['account'] == null
            ? null
            : GoalAccount.fromJson(j['account'] as Map<String, dynamic>),
      );
}
