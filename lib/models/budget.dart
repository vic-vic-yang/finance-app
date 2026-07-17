/// 预算里某成员的花费（家庭共同预算「谁花了多少」）
class BudgetMemberSpent {
  final String userId;
  final String name;
  final double spent;
  BudgetMemberSpent(
      {required this.userId, required this.name, required this.spent});
  factory BudgetMemberSpent.fromJson(Map<String, dynamic> j) =>
      BudgetMemberSpent(
        userId: j['userId'] as String? ?? '',
        name: j['name'] as String? ?? '成员',
        spent: (j['spent'] as num?)?.toDouble() ?? 0,
      );
}

class Budget {
  final String id;
  final String? categoryId;
  final String? categoryName;
  final String? categoryIcon;
  final double amount;
  final double spent;
  final double remaining;
  final double progress; // 0~1+，>1 表示超支
  final String period; // MONTHLY / YEARLY
  final DateTime periodStart;
  final DateTime periodEnd;
  final List<BudgetMemberSpent> members;

  Budget({
    required this.id,
    this.categoryId,
    this.categoryName,
    this.categoryIcon,
    required this.amount,
    required this.spent,
    required this.remaining,
    required this.progress,
    required this.period,
    required this.periodStart,
    required this.periodEnd,
    this.members = const [],
  });

  factory Budget.fromJson(Map<String, dynamic> j) => Budget(
        id: j['id'] as String,
        categoryId: j['categoryId'] as String?,
        categoryName:
            j['category'] is Map ? j['category']['name'] as String? : null,
        categoryIcon:
            j['category'] is Map ? j['category']['icon'] as String? : null,
        amount: (j['amount'] as num).toDouble(),
        spent: (j['spent'] as num?)?.toDouble() ?? 0,
        remaining: (j['remaining'] as num?)?.toDouble() ?? 0,
        progress: (j['progress'] as num?)?.toDouble() ?? 0,
        period: j['period'] as String? ?? 'MONTHLY',
        periodStart: DateTime.parse(j['periodStart'] as String),
        periodEnd: DateTime.parse(j['periodEnd'] as String),
        members: ((j['members'] as List?) ?? [])
            .map((e) =>
                BudgetMemberSpent.fromJson(e as Map<String, dynamic>))
            .toList(),
      );

  bool get isOverall => categoryId == null;
  String get displayName => isOverall ? '总预算' : (categoryName ?? '');
  String get displayIcon => isOverall ? '💼' : (categoryIcon ?? '📂');
  String get periodLabel => period == 'YEARLY' ? '年度' : '月度';
  bool get isOverBudget => progress > 1.0;
}
