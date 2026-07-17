import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../../core/theme.dart';
import '../../widgets/glass.dart';
import 'tools_common.dart';

/// 贷款计算器：等额本息 vs 等额本金 + 提前还款测算。房贷/车贷/消费贷通用，纯本地计算。
class LoanCalculatorScreen extends StatefulWidget {
  const LoanCalculatorScreen({super.key});

  @override
  State<LoanCalculatorScreen> createState() => _LoanCalculatorScreenState();
}

class _LoanCalculatorScreenState extends State<LoanCalculatorScreen> {
  final _amountCtrl = TextEditingController(); // 贷款金额（万元）
  final _rateCtrl = TextEditingController(text: '3.5'); // 年利率 %
  final _yearsCtrl = TextEditingController(text: '30'); // 年限

  // 提前还款
  final _prepayCtrl = TextEditingController(); // 提前还款金额（元）
  final _prepayMonthCtrl = TextEditingController(text: '12'); // 第几个月还

  int _method = 0; // 0=等额本息 1=等额本金

  @override
  void initState() {
    super.initState();
    for (final c in [
      _amountCtrl,
      _rateCtrl,
      _yearsCtrl,
      _prepayCtrl,
      _prepayMonthCtrl
    ]) {
      c.addListener(() => setState(() {}));
    }
  }

  @override
  void dispose() {
    for (final c in [
      _amountCtrl,
      _rateCtrl,
      _yearsCtrl,
      _prepayCtrl,
      _prepayMonthCtrl
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  double get _principal => toolParse(_amountCtrl.text) * 10000; // 万元→元
  double get _monthlyRate => toolParse(_rateCtrl.text) / 100 / 12;
  int get _months => (toolParse(_yearsCtrl.text) * 12).round();

  bool get _valid => _principal > 0 && _months > 0;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: const AuraAppBar(title: '贷款计算器'),
      body: AuraBackground(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 40),
          children: [
            ToolFormCard(
              children: [
                ToolNumField(
                  controller: _amountCtrl,
                  label: '贷款金额',
                  hint: '例如 100',
                  suffix: '万元',
                ),
                ToolNumField(
                  controller: _rateCtrl,
                  label: '年利率',
                  hint: '例如 3.5',
                  suffix: '%',
                ),
                ToolNumField(
                  controller: _yearsCtrl,
                  label: '贷款年限',
                  hint: '例如 30',
                  suffix: '年',
                  allowDecimal: false,
                ),
                ToolSegToggle(
                  labels: const ['等额本息', '等额本金'],
                  index: _method,
                  onChanged: (i) => setState(() => _method = i),
                ),
              ],
            ),
            const SizedBox(height: 14),
            if (_valid) ...[
              _method == 0 ? _equalInstallmentResult() : _equalPrincipalResult(),
              const SizedBox(height: 14),
              _prepaySection(),
              const SizedBox(height: 14),
              _tip(),
            ] else
              _emptyHint(),
          ],
        ),
      ),
    );
  }

  Widget _emptyHint() => GlassCard(
        radius: 16,
        child: Row(children: [
          Icon(Icons.calculate_outlined, color: AppColors.text2, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Text('填入贷款金额、利率、年限即可自动计算',
                style: TextStyle(fontSize: 13, color: AppColors.text2)),
          ),
        ]),
      );

  // ── 等额本息 ───────────────────────────────────────────────
  Widget _equalInstallmentResult() {
    final r = _monthlyRate;
    final n = _months;
    final p = _principal;
    final double monthly;
    if (r == 0) {
      monthly = p / n;
    } else {
      final pow = math.pow(1 + r, n).toDouble();
      monthly = p * r * pow / (pow - 1);
    }
    final total = monthly * n;
    final interest = total - p;
    return ToolResultCard(
      title: '等额本息 · 每月还款固定',
      children: [
        ToolResultRow(
            label: '每月月供', value: '¥${toolMoney(monthly)}', emphasize: true),
        const Divider(height: 18),
        ToolResultRow(
            label: '支付总利息',
            value: '¥${toolMoney(interest)}',
            valueColor: AppColors.expense),
        ToolResultRow(label: '还款总额', value: '¥${toolMoney(total)}'),
        ToolResultRow(label: '贷款本金', value: '¥${toolMoney(p)}'),
        ToolResultRow(
            label: '利息占本金', value: '${(interest / p * 100).toStringAsFixed(1)}%'),
      ],
    );
  }

  // ── 等额本金 ───────────────────────────────────────────────
  Widget _equalPrincipalResult() {
    final r = _monthlyRate;
    final n = _months;
    final p = _principal;
    final monthlyPrincipal = p / n;
    final firstMonth = monthlyPrincipal + p * r; // 首月最高
    final lastMonth = monthlyPrincipal + monthlyPrincipal * r; // 末月最低
    final decreasePerMonth = monthlyPrincipal * r; // 每月递减
    final interest = r * p * (n + 1) / 2;
    final total = p + interest;
    return ToolResultCard(
      title: '等额本金 · 月供逐月递减',
      children: [
        ToolResultRow(
            label: '首月月供', value: '¥${toolMoney(firstMonth)}', emphasize: true),
        const Divider(height: 18),
        ToolResultRow(label: '末月月供', value: '¥${toolMoney(lastMonth)}'),
        ToolResultRow(
            label: '每月递减', value: '¥${toolMoney(decreasePerMonth)}'),
        ToolResultRow(
            label: '支付总利息',
            value: '¥${toolMoney(interest)}',
            valueColor: AppColors.expense),
        ToolResultRow(label: '还款总额', value: '¥${toolMoney(total)}'),
        ToolResultRow(
            label: '利息占本金', value: '${(interest / p * 100).toStringAsFixed(1)}%'),
      ],
    );
  }

  // ── 提前还款（按等额本息、缩短期限测算）────────────────────
  Widget _prepaySection() {
    final prepay = toolParse(_prepayCtrl.text);
    final atMonth = toolParse(_prepayMonthCtrl.text).round();
    Widget? result;
    if (prepay > 0 && atMonth >= 1 && atMonth < _months) {
      result = _prepayResult(prepay, atMonth);
    }
    return GlassCard(
      radius: 18,
      padding: const EdgeInsets.fromLTRB(18, 16, 18, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Text('提前还款测算',
                style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: AppColors.text2)),
            const SizedBox(width: 6),
            Text('· 等额本息 · 缩短期限',
                style: TextStyle(fontSize: 11, color: AppColors.text3)),
          ]),
          const SizedBox(height: 14),
          Row(children: [
            Expanded(
              child: ToolNumField(
                controller: _prepayCtrl,
                label: '提前还款额',
                hint: '例如 100000',
                suffix: '元',
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: ToolNumField(
                controller: _prepayMonthCtrl,
                label: '在第几个月',
                hint: '例如 12',
                suffix: '月',
                allowDecimal: false,
              ),
            ),
          ]),
          if (result != null) ...[
            const SizedBox(height: 16),
            result,
          ] else ...[
            const SizedBox(height: 12),
            Text(
              prepay > 0 && atMonth >= _months
                  ? '还款月份要小于总期数（$_months 期）'
                  : '填写提前还款金额与月份，测算能省多少利息',
              style: TextStyle(fontSize: 12, color: AppColors.text3),
            ),
          ],
        ],
      ),
    );
  }

  Widget _prepayResult(double prepay, int atMonth) {
    final r = _monthlyRate;
    final n = _months;
    final p = _principal;

    // 原方案月供
    final double monthly;
    if (r == 0) {
      monthly = p / n;
    } else {
      final pow = math.pow(1 + r, n).toDouble();
      monthly = p * r * pow / (pow - 1);
    }
    final originalInterest = monthly * n - p;

    // 逐月摊销到 atMonth，得到剩余本金
    double balance = p;
    double paidInterest = 0;
    for (int m = 1; m <= atMonth; m++) {
      final monthInterest = balance * r;
      paidInterest += monthInterest;
      balance -= (monthly - monthInterest);
    }
    // 提前还一笔，月供不变，继续摊销直到结清
    balance -= prepay;
    if (balance <= 0) {
      // 一次性结清
      final newInterest = paidInterest + math.max(0.0, balance + prepay) * 0; // 已结清
      final saved = originalInterest - newInterest;
      return _prepaySummary(
        savedInterest: saved,
        shortenedMonths: n - atMonth,
        note: '本次还款后已结清贷款',
      );
    }
    int extraMonths = 0;
    while (balance > 0.005 && extraMonths < n * 2) {
      final monthInterest = balance * r;
      paidInterest += monthInterest;
      final principalPart = monthly - monthInterest;
      if (principalPart <= 0) break; // 利率异常保护
      balance -= principalPart;
      extraMonths++;
    }
    final newTotalMonths = atMonth + extraMonths;
    final newInterest = paidInterest;
    final saved = originalInterest - newInterest;
    return _prepaySummary(
      savedInterest: saved,
      shortenedMonths: n - newTotalMonths,
      note: '新还款期约 $newTotalMonths 期（原 $n 期）',
    );
  }

  Widget _prepaySummary({
    required double savedInterest,
    required int shortenedMonths,
    required String note,
  }) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.income.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ToolResultRow(
            label: '节省利息',
            value: '¥${toolMoney(savedInterest < 0 ? 0 : savedInterest)}',
            emphasize: true,
            valueColor: AppColors.income,
          ),
          ToolResultRow(
            label: '缩短期限',
            value: shortenedMonths <= 0
                ? '—'
                : '${(shortenedMonths / 12).floor()}年${shortenedMonths % 12}个月',
          ),
          const SizedBox(height: 6),
          Text(note, style: TextStyle(fontSize: 12, color: AppColors.text2)),
        ],
      ),
    );
  }

  Widget _tip() => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4),
        child: Text(
          '说明：结果为按固定利率的理论测算，实际以银行合同为准（LPR 浮动、计息方式等可能略有差异）。',
          style: TextStyle(fontSize: 11.5, color: AppColors.text3, height: 1.5),
        ),
      );
}
