/// 周期账单（房租、订阅、话费…）。
///
/// 服务器只存 amount/date/categoryId/accountId 明文 + noteCipher 密文。
/// 客户端拿到后用账本 DEK 解 noteCipher 显示。
class RecurringBill {
  final String id;
  final String ledgerId;
  final String categoryId;
  final String accountId;
  final String type; // expense / income
  final double amount;
  /// 密文 base64，可空（用户没写备注时）
  final String? noteCipher;
  final int? noteDekVer;
  final String cycleType; // monthly / weekly / yearly
  final int cycleDay;
  final DateTime nextDate;
  final bool isActive;
  final bool isAuto;
  final double? confidence;
  final DateTime createdAt;
  final DateTime updatedAt;

  RecurringBill({
    required this.id,
    required this.ledgerId,
    required this.categoryId,
    required this.accountId,
    required this.type,
    required this.amount,
    this.noteCipher,
    this.noteDekVer,
    required this.cycleType,
    required this.cycleDay,
    required this.nextDate,
    required this.isActive,
    required this.isAuto,
    this.confidence,
    required this.createdAt,
    required this.updatedAt,
  });

  factory RecurringBill.fromJson(Map<String, dynamic> j) => RecurringBill(
        id: j['id'] as String,
        ledgerId: j['ledgerId'] as String,
        categoryId: j['categoryId'] as String,
        accountId: j['accountId'] as String,
        type: (j['type'] as String?) ?? 'expense',
        amount: (j['amount'] as num).toDouble(),
        noteCipher: j['noteCipher'] as String?,
        noteDekVer: (j['noteDekVer'] as num?)?.toInt(),
        cycleType: j['cycleType'] as String? ?? 'monthly',
        cycleDay: (j['cycleDay'] as num).toInt(),
        nextDate: DateTime.parse(j['nextDate'] as String),
        isActive: j['isActive'] as bool? ?? true,
        isAuto: j['isAuto'] as bool? ?? false,
        confidence: (j['confidence'] as num?)?.toDouble(),
        createdAt: DateTime.parse(j['createdAt'] as String),
        updatedAt: DateTime.parse(j['updatedAt'] as String),
      );

  String get cycleLabel {
    switch (cycleType) {
      case 'weekly':
        const wk = ['一', '二', '三', '四', '五', '六', '日'];
        final i = (cycleDay - 1).clamp(0, 6);
        return '每周${wk[i]}';
      case 'yearly':
        final mm = cycleDay ~/ 100;
        final dd = cycleDay % 100;
        return '每年 $mm月$dd日';
      default:
        return '每月 $cycleDay 号';
    }
  }
}

/// AI 检测出的周期候选（未入库）
class RecurringCandidate {
  final String categoryId;
  final String accountId;
  final String type;
  final double amount;
  final String cycleType;
  final int cycleDay;
  final double confidence;
  final int sampleCount;
  final List<String> sampleBillIds;
  final double avgIntervalDays;
  final double stddevDays;
  final DateTime lastDate;
  final DateTime nextDate;

  RecurringCandidate({
    required this.categoryId,
    required this.accountId,
    required this.type,
    required this.amount,
    required this.cycleType,
    required this.cycleDay,
    required this.confidence,
    required this.sampleCount,
    required this.sampleBillIds,
    required this.avgIntervalDays,
    required this.stddevDays,
    required this.lastDate,
    required this.nextDate,
  });

  factory RecurringCandidate.fromJson(Map<String, dynamic> j) =>
      RecurringCandidate(
        categoryId: j['categoryId'] as String,
        accountId: j['accountId'] as String,
        type: (j['type'] as String?) ?? 'expense',
        amount: (j['amount'] as num).toDouble(),
        cycleType: j['cycleType'] as String? ?? 'monthly',
        cycleDay: (j['cycleDay'] as num).toInt(),
        confidence: (j['confidence'] as num).toDouble(),
        sampleCount: (j['sampleCount'] as num).toInt(),
        sampleBillIds: (j['sampleBillIds'] as List).cast<String>(),
        avgIntervalDays: (j['avgIntervalDays'] as num).toDouble(),
        stddevDays: (j['stddevDays'] as num).toDouble(),
        lastDate: DateTime.parse(j['lastDate'] as String),
        nextDate: DateTime.parse(j['nextDate'] as String),
      );
}
