import '../crypto/key_chain.dart';

/// 借贷往来记录：lend=借出(别人欠我/应收)，borrow=借入(我欠别人/应付)
class Loan {
  final String id;
  final String direction; // 'lend' | 'borrow'
  final double amount;
  final double repaidAmount;
  final double outstanding;
  final String? accountId;
  final String? noteCipher;
  final int noteDekVer;
  final String? voucherKey;
  final DateTime date;
  final bool settled;

  Loan({
    required this.id,
    required this.direction,
    required this.amount,
    required this.repaidAmount,
    required this.outstanding,
    this.accountId,
    this.noteCipher,
    this.noteDekVer = 1,
    this.voucherKey,
    required this.date,
    this.settled = false,
  });

  bool get isLend => direction == 'lend';

  /// 用账本 DEK 解密备注
  String noteOf(String ledgerId) {
    if (noteCipher == null || noteCipher!.isEmpty) return '';
    return KeyChain.instance.decryptText(
      ledgerId: ledgerId,
      cipherBase64: noteCipher!,
      dekVer: noteDekVer,
      systemFallback: '',
    );
  }

  factory Loan.fromJson(Map<String, dynamic> j) => Loan(
        id: j['id'] as String? ?? '',
        direction: j['direction'] as String? ?? 'lend',
        amount: (j['amount'] as num?)?.toDouble() ?? 0,
        repaidAmount: (j['repaidAmount'] as num?)?.toDouble() ?? 0,
        outstanding: (j['outstanding'] as num?)?.toDouble() ?? 0,
        accountId: j['accountId'] as String?,
        noteCipher: j['noteCipher'] as String?,
        noteDekVer: (j['noteDekVer'] as num?)?.toInt() ?? 1,
        voucherKey: j['voucherKey'] as String?,
        date: DateTime.tryParse(j['date'] as String? ?? '') ?? DateTime.now(),
        settled: j['settled'] as bool? ?? false,
      );
}
