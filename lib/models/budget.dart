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
      );

  bool get isOverall => categoryId == null;
  String get displayName => isOverall ? '总预算' : (categoryName ?? '');
  String get displayIcon => isOverall ? '💼' : (categoryIcon ?? '📂');
  String get periodLabel => period == 'YEARLY' ? '年度' : '月度';
  bool get isOverBudget => progress > 1.0;
}
