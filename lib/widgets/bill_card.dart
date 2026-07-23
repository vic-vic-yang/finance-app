import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../core/theme.dart';
import '../models/bill.dart';
import 'amount_text.dart';

/// 账单列表行 —— 与 bills_screen 的 `_BillTile` 同风格：
/// surface 底 + 圆角 14（InkWell 同半径裁剪水波）、text1/text2/text3
/// 中性文字、AmountText（list 字阶 + 收支语义 tone + showSign）。
/// 目前用于 CFO「归类其他」列表（recategorize_other_screen）。
class BillCard extends StatelessWidget {
  final Bill bill;
  final VoidCallback? onTap;
  final VoidCallback? onDelete;

  const BillCard({
    super.key,
    required this.bill,
    this.onTap,
    this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final isIncome = bill.isIncome;
    final br = BorderRadius.circular(14);

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: br,
        border: Border.all(color: AppColors.border, width: 0.6),
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: br,
        child: InkWell(
          onTap: onTap,
          borderRadius: br,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            child: Row(
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    // 转账 / 股票纸面盈亏用中性底，不冒充真实收支
                    color: (bill.isTransfer || bill.source == 'stock')
                        ? AppColors.transferLight
                        : (isIncome
                            ? AppColors.incomeLight
                            : AppColors.expenseLight),
                    borderRadius: BorderRadius.circular(11),
                  ),
                  child: Center(
                    // 转账账单一律显示 🔄（与 _BillTile 一致）
                    child: Text(
                      bill.isTransfer
                          ? '🔄'
                          : (bill.category.icon ??
                              (isIncome ? '💰' : '💸')),
                      style: const TextStyle(fontSize: 19),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        bill.isTransfer ? '转账' : bill.category.name,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w500,
                          color: AppColors.text1,
                        ),
                      ),
                      if (bill.note.isNotEmpty) ...[
                        const SizedBox(height: 2),
                        Text(
                          bill.note,
                          style:
                              TextStyle(fontSize: 12, color: AppColors.text2),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    AmountText(
                      isIncome ? bill.amount : -bill.amount,
                      size: AmountSize.list,
                      // 股票纸面盈亏 / 转账用中性 tone，与真实收支的红绿拉开
                      tone: bill.source == 'stock'
                          ? AmountTone.stockPaper
                          : bill.isTransfer
                              ? AmountTone.transfer
                              : (isIncome
                                  ? AmountTone.income
                                  : AmountTone.expense),
                      showSign: true,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      DateFormat('MM-dd HH:mm').format(bill.date),
                      style: TextStyle(fontSize: 11, color: AppColors.text3),
                    ),
                  ],
                ),
                if (onDelete != null) ...[
                  const SizedBox(width: 4),
                  GestureDetector(
                    onTap: onDelete,
                    child: Padding(
                      padding: const EdgeInsets.all(4),
                      child: Icon(Icons.delete_outline_rounded,
                          size: 18, color: AppColors.text2),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
