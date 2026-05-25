class Account {
  final String id;
  final String name;
  final String type;
  final double balance;
  final String? icon;
  final String? color;

  /// 所有者用户 id：null 表示共享账户
  final String? ownerId;
  /// 所有者用户名（仅共享账本中其他人的账户能看到，自己看不到自己的）
  final String? ownerName;
  /// 所有者昵称
  final String? ownerNickname;
  /// 是否共享账户（所有成员可见可用）
  final bool isShared;
  /// 当前用户是否可以看到该账户的余额（他人私人账户为 false）
  final bool balanceVisible;

  // ── 类型相关配置 ────────────────────────────────────────────
  /// 信用卡账单日（1-31）
  final int? statementDay;
  /// 信用卡还款日 / 负债账户每月还款日（1-31）
  final int? dueDay;
  /// 信用卡信用额度
  final double? creditLimit;
  /// 负债账户年利率（%）
  final double? interestRate;
  /// 负债账户贷款本金
  final double? loanPrincipal;
  /// 负债账户贷款期限（月）
  final int? loanTermMonths;
  /// 负债账户首次还款日期
  final DateTime? firstPaymentDate;
  /// 负债账户还款方式
  final String? repaymentMethod;
  /// 自动入账日（社保/公积金）
  final int? autoDepositDay;
  /// 自动入账金额
  final double? autoDepositAmount;
  /// 自动入账归到哪个分类（可为 null，后端会用"其他收入"兜底）
  final String? autoDepositCategoryId;

  /// 服务端算好的派生信息：信用卡账单 / 负债还款 / 自动入账下次
  final AccountInfo? info;

  Account({
    required this.id,
    required this.name,
    required this.type,
    required this.balance,
    this.icon,
    this.color,
    this.ownerId,
    this.ownerName,
    this.ownerNickname,
    this.isShared = false,
    this.balanceVisible = true,
    this.statementDay,
    this.dueDay,
    this.creditLimit,
    this.interestRate,
    this.loanPrincipal,
    this.loanTermMonths,
    this.firstPaymentDate,
    this.repaymentMethod,
    this.autoDepositDay,
    this.autoDepositAmount,
    this.autoDepositCategoryId,
    this.info,
  });

  factory Account.fromJson(Map<String, dynamic> json) => Account(
        id: json['id'] as String,
        name: json['name'] as String,
        type: json['type'] as String,
        balance: (json['balance'] as num?)?.toDouble() ?? 0,
        icon: json['icon'] as String?,
        color: json['color'] as String?,
        ownerId: json['ownerId'] as String?,
        ownerName: json['ownerName'] as String?,
        ownerNickname: json['ownerNickname'] as String?,
        isShared: json['isShared'] as bool? ?? (json['ownerId'] == null),
        balanceVisible: json['balanceVisible'] as bool? ?? true,
        statementDay: (json['statementDay'] as num?)?.toInt(),
        dueDay: (json['dueDay'] as num?)?.toInt(),
        creditLimit: (json['creditLimit'] as num?)?.toDouble(),
        interestRate: (json['interestRate'] as num?)?.toDouble(),
        loanPrincipal: (json['loanPrincipal'] as num?)?.toDouble(),
        loanTermMonths: (json['loanTermMonths'] as num?)?.toInt(),
        firstPaymentDate: json['firstPaymentDate'] is String
            ? DateTime.tryParse(json['firstPaymentDate'] as String)
            : null,
        repaymentMethod: json['repaymentMethod'] as String?,
        autoDepositDay: (json['autoDepositDay'] as num?)?.toInt(),
        autoDepositAmount:
            (json['autoDepositAmount'] as num?)?.toDouble(),
        autoDepositCategoryId: json['autoDepositCategoryId'] as String?,
        info: json['info'] is Map<String, dynamic>
            ? AccountInfo.fromJson(json['info'] as Map<String, dynamic>)
            : null,
      );

  /// 所有者显示名（昵称优先，回退用户名）
  String? get ownerDisplayName {
    final n = (ownerNickname ?? '').trim();
    if (n.isNotEmpty) return n;
    return ownerName;
  }

  /// 是否归当前用户所有（私人账户判断用）
  bool isOwnedBy(String userId) => ownerId == userId;

  String get typeLabel {
    const m = {
      'CASH': '现金',
      'BANK': '银行卡',
      'VIRTUAL': '虚拟账户',
      'CREDIT': '信用卡',
      'INVESTMENT': '投资理财',
      'INSURANCE': '社保',
      'DEBT': '负债账户',
      'OTHER': '其他',
      // 历史值，遇到老数据时仍可展示
      'ALIPAY': '虚拟账户',
      'WECHAT': '虚拟账户',
    };
    return m[type] ?? '其他';
  }

  /// 子类型说明，让用户更清楚一类账户包含哪些
  String get typeDesc {
    const m = {
      'CASH': '现金',
      'BANK': '储蓄卡 / 借记卡 / 存折',
      'VIRTUAL': '微信 / 支付宝 / 电子钱包',
      'CREDIT': '信用卡',
      'INVESTMENT': '理财 / 股票 / 基金 / 债券',
      'INSURANCE': '社保 / 公积金 / 商业保险',
      'DEBT': '房贷 / 车贷 / 借款',
      'OTHER': '其他',
    };
    return m[type] ?? '其他';
  }

  String get typeEmoji {
    const m = {
      'CASH': '💵',
      'BANK': '🏦',
      'VIRTUAL': '📱',
      'CREDIT': '💳',
      'INVESTMENT': '📈',
      'INSURANCE': '🛡️',
      'DEBT': '🏚️',
      'OTHER': '💰',
      // 历史值
      'ALIPAY': '📱',
      'WECHAT': '📱',
    };
    return m[type] ?? '💰';
  }

  /// 是否为负债类账户：用于资产汇总时显示提示（实际计算时不强制取负，
  /// 用户可自行决定填正还是负）
  bool get isDebt => type == 'DEBT';
  bool get isCredit => type == 'CREDIT';
  bool get isInsurance => type == 'INSURANCE';

  /// 还款方式中文显示
  String? get repaymentMethodLabel {
    const m = {
      'equal_payment': '等额本息',
      'equal_principal': '等额本金',
      'interest_only': '先息后本',
      'lump_sum': '一次性还本付息',
      'flexible': '自由还款',
    };
    if (repaymentMethod == null) return null;
    return m[repaymentMethod!] ?? repaymentMethod;
  }
}

/// 还款方式选项（UI 用）
const List<(String, String, String)> kRepaymentMethods = [
  ('equal_payment',   '等额本息', '每月固定，本息合计相同（最常见，房贷常用）'),
  ('equal_principal', '等额本金', '每月本金固定，利息递减'),
  ('interest_only',   '先息后本', '前期只还利息，最后一次性还本'),
];

/// 服务端算好的账户派生信息（不存数据库，每次 GET /accounts 时即时算）
class AccountInfo {
  /// 'credit' / 'debt' / 'auto_deposit'
  final String kind;

  // ── credit ─────────────────────────────────────────────
  final DateTime? periodStart;
  final DateTime? periodEnd;
  /// 本期账单金额（已出账）
  final double? periodBill;
  /// 已还（估算）
  final double? paid;
  /// 未还
  final double? unpaid;
  /// 下次出账（未出账的当前周期）支出
  final double? ongoingSpent;
  final DateTime? nextStatementDate;

  // ── credit + debt 共用 ─────────────────────────────────
  final DateTime? dueDate;
  final int? daysToDue;
  final bool isOverdue;
  final bool isDueToday;
  final bool isDueTomorrow;

  // ── debt 专用 ─────────────────────────────────────────
  /// 欠款金额
  final double? owed;
  final double? interestRate;
  /// 月利息估算（简单利率）
  final double? monthlyInterest;
  /// 当期月供（按还款方式计算）
  final double? monthlyPayment;
  /// 已还期数
  final int? paidPeriods;
  /// 总期数
  final int? totalPeriods;

  // ── auto_deposit 专用 ─────────────────────────────────
  final DateTime? nextDepositDate;
  final DateTime? lastDepositDate;
  final double? amount;

  // 信用卡额度（与 credit 一并返回）
  final double? creditLimit;

  AccountInfo({
    required this.kind,
    this.periodStart,
    this.periodEnd,
    this.periodBill,
    this.paid,
    this.unpaid,
    this.ongoingSpent,
    this.nextStatementDate,
    this.dueDate,
    this.daysToDue,
    this.isOverdue = false,
    this.isDueToday = false,
    this.isDueTomorrow = false,
    this.owed,
    this.interestRate,
    this.monthlyInterest,
    this.monthlyPayment,
    this.paidPeriods,
    this.totalPeriods,
    this.nextDepositDate,
    this.lastDepositDate,
    this.amount,
    this.creditLimit,
  });

  factory AccountInfo.fromJson(Map<String, dynamic> j) {
    DateTime? p(dynamic x) =>
        x is String && x.isNotEmpty ? DateTime.parse(x) : null;
    return AccountInfo(
      kind: j['kind'] as String? ?? '',
      periodStart: p(j['periodStart']),
      periodEnd: p(j['periodEnd']),
      periodBill: (j['periodBill'] as num?)?.toDouble(),
      paid: (j['paid'] as num?)?.toDouble(),
      unpaid: (j['unpaid'] as num?)?.toDouble(),
      ongoingSpent: (j['ongoingSpent'] as num?)?.toDouble(),
      nextStatementDate: p(j['nextStatementDate']),
      dueDate: p(j['dueDate']),
      daysToDue: (j['daysToDue'] as num?)?.toInt(),
      isOverdue: j['isOverdue'] as bool? ?? false,
      isDueToday: j['isDueToday'] as bool? ?? false,
      isDueTomorrow: j['isDueTomorrow'] as bool? ?? false,
      owed: (j['owed'] as num?)?.toDouble(),
      interestRate: (j['interestRate'] as num?)?.toDouble(),
      monthlyInterest: (j['monthlyInterest'] as num?)?.toDouble(),
      monthlyPayment: (j['monthlyPayment'] as num?)?.toDouble(),
      paidPeriods: (j['paidPeriods'] as num?)?.toInt(),
      totalPeriods: (j['totalPeriods'] as num?)?.toInt(),
      nextDepositDate: p(j['nextDepositDate']),
      lastDepositDate: p(j['lastDepositDate']),
      amount: (j['amount'] as num?)?.toDouble(),
      creditLimit: (j['creditLimit'] as num?)?.toDouble(),
    );
  }
}
