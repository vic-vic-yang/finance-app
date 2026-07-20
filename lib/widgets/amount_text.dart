import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../core/theme.dart';

/// ======================================================================
/// AmountText · 司库统一金额排版组件
/// ======================================================================
///
/// 用途：全局所有「钱」的显示入口。统一千分位格式、等宽数字（tabular
/// figures，上下行金额逐位对齐）、货币符号降阶、语义色与字阶，避免各页面
/// 各写各的 `¥ + NumberFormat`。
///
/// 配套工具：[formatAmount] —— 纯字符串格式化（对话框文案、拼接文案等
/// 不需要组件的场景），`models/bill.dart` 的 `fmtMoney` 系列即委托给它。
///
/// 字阶表（AmountSize）：
/// ┌────────┬────────┬────────┬───────────────┬─────────────────────┐
/// │ 档位   │ 字号   │ 字重   │ letterSpacing │ 典型场景            │
/// ├────────┼────────┼────────┼───────────────┼─────────────────────┤
/// │ hero   │ 36     │ w700   │ -0.5          │ 首页 hero 结余大卡  │
/// │ card   │ 17     │ w600   │ 0             │ 汇总卡 / 卡内大数字 │
/// │ list   │ 15     │ w600   │ 0             │ 账单列表行金额      │
/// │ aux    │ 13     │ w500   │ 0             │ 小计 / 图例 / 辅注  │
/// └────────┴────────┴────────┴───────────────┴─────────────────────┘
///
/// 语义色（AmountTone）：
///   - neutral → AppColors.text1（余额、总资产等无方向数值）
///   - income  → AppColors.income（红，收入）
///   - expense → AppColors.expense（绿，支出）
///   - auto    → 按数值正负自动：正 = income，负 = expense
/// `color` 参数可整体覆盖（渐变 hero 卡上用 AppColors.onPrimaryGradient）；
/// 覆盖时货币符号跟随主色 70% 透明度，否则固定用 AppColors.text2。
///
/// 用法示例：
/// ```dart
/// // 首页 hero 结余（渐变卡上）
/// AmountText(balance, size: AmountSize.hero, color: AppColors.onPrimaryGradient)
///
/// // 账单行：收入红 +「+」/ 支出绿 +「−」（传带符号数值，tone 语义化）
/// AmountText(bill.isIncome ? bill.amount : -bill.amount,
///     size: AmountSize.list,
///     tone: bill.isIncome ? AmountTone.income : AmountTone.expense,
///     showSign: true)
///
/// // 汇总卡：0 位小数 + 卡片主题色覆盖
/// AmountText(total.abs(), size: AmountSize.card, decimals: 0, color: color)
///
/// // 纯文案拼接（对话框等）
/// Text('删除「餐饮」${'¥${formatAmount(123.45)}'}？')
/// ```
///
/// 细节约定：
///   - 数字带 `FontFeature('tnum')` 等宽数字，列表上下行逐位对齐。
///   - 货币符号（默认 ¥）字号 = 数字 × 0.62，字重降一级。
///   - `showSign` 时正数前缀 `+`、负数前缀 `−`（U+2212，比连字符美观），
///     数字部分取绝对值；符号颜色跟随数字主色。
///   - 不 `showSign` 时负数按 intl 默认行为输出（`¥-1,234.00`），与旧
///     `fmtMoney` 行为一致。
///   - 单行渲染：`softWrap: false` + `overflow: ellipsis`，大数不破行。
class AmountText extends StatelessWidget {
  const AmountText(
    this.amount, {
    super.key,
    this.size = AmountSize.list,
    this.tone = AmountTone.neutral,
    this.color,
    this.decimals = 2,
    this.symbol = '¥',
    this.showSymbol = true,
    this.showSign = false,
    this.textAlign,
  });

  /// 数值。`showSign` 时请传带符号原值（正 = 收，负 = 支）。
  final double amount;

  /// 字号字阶，默认 [AmountSize.list]。
  final AmountSize size;

  /// 语义色，默认 [AmountTone.neutral]。被 [color] 覆盖时忽略。
  final AmountTone tone;

  /// 整体颜色覆盖（优先级高于 tone）；符号跟随该色 70% 透明度。
  final Color? color;

  /// 小数位，默认 2；传 0 即整数模式（旧 `fmtMoneyInt` 行为）。
  final int decimals;

  /// 货币符号，默认 `¥`。
  final String symbol;

  /// 是否显示货币符号。
  final bool showSymbol;

  /// 是否在符号前加方向符号：正 `+` / 负 `−`（U+2212）。
  final bool showSign;

  final TextAlign? textAlign;

  @override
  Widget build(BuildContext context) {
    final spec = _sizeSpec(size);

    final Color mainColor = color ??
        switch (tone) {
          AmountTone.neutral => AppColors.text1,
          AmountTone.income => AppColors.income,
          AmountTone.expense => AppColors.expense,
          AmountTone.auto =>
            amount >= 0 ? AppColors.income : AppColors.expense,
        };
    // 符号降阶：默认 text2；color 覆盖时跟随主色 70% 透明度
    final Color symbolColor =
        color != null ? color!.withValues(alpha: 0.7) : AppColors.text2;

    const tnum = [FontFeature('tnum')];
    final digitStyle = TextStyle(
      fontSize: spec.fontSize,
      fontWeight: spec.weight,
      letterSpacing: spec.letterSpacing,
      color: mainColor,
      fontFeatures: tnum,
    );
    final symbolStyle = digitStyle.copyWith(
      fontSize: spec.fontSize * 0.62,
      fontWeight: _demoteWeight(spec.weight),
      letterSpacing: 0,
      color: symbolColor,
    );

    final String sign =
        !showSign ? '' : (amount >= 0 ? '+' : '−');
    final double digits = showSign ? amount.abs() : amount;
    final parts = splitAmount(digits, decimals: decimals);

    return Text.rich(
      TextSpan(children: [
        if (sign.isNotEmpty) TextSpan(text: sign, style: digitStyle),
        if (showSymbol) TextSpan(text: symbol, style: symbolStyle),
        TextSpan(text: parts.integer, style: digitStyle),
        if (parts.fraction.isNotEmpty)
          TextSpan(text: parts.fraction, style: digitStyle),
      ]),
      softWrap: false,
      overflow: TextOverflow.ellipsis,
      maxLines: 1,
      textAlign: textAlign,
    );
  }
}

/// 金额字阶。
enum AmountSize { hero, card, list, aux }

/// 金额语义色。
enum AmountTone { neutral, income, expense, auto }

({double fontSize, FontWeight weight, double letterSpacing}) _sizeSpec(
        AmountSize s) =>
    switch (s) {
      AmountSize.hero => (fontSize: 36, weight: FontWeight.w700, letterSpacing: -0.5),
      AmountSize.card => (fontSize: 17, weight: FontWeight.w600, letterSpacing: 0.0),
      AmountSize.list => (fontSize: 15, weight: FontWeight.w600, letterSpacing: 0.0),
      AmountSize.aux  => (fontSize: 13, weight: FontWeight.w500, letterSpacing: 0.0),
    };

/// 字重降一级（w700→w600、w600→w500、w500→w400…），到底保持 w100。
FontWeight _demoteWeight(FontWeight w) {
  const values = FontWeight.values; // w100 … w900
  final i = values.indexOf(w);
  return values[(i - 1).clamp(0, values.length - 1)];
}

final _amountFormatters = <int, NumberFormat>{};

NumberFormat _formatterFor(int decimals) => _amountFormatters.putIfAbsent(
      decimals,
      () => NumberFormat(
          decimals <= 0 ? '#,##0' : '#,##0.${'0' * decimals}'),
    );

/// 金额格式化：千分位分隔，默认 2 位小数。负数由 intl 输出前导 `-`。
///
/// 这是纯字符串工具，供对话框文案 / 拼接文案使用；视觉展示请用 [AmountText]。
String formatAmount(num value, {int decimals = 2}) =>
    _formatterFor(decimals < 0 ? 0 : decimals).format(value);

/// 把金额拆成「整数部分 + 小数部分（含小数点）」，供 [AmountText] 分段排版。
({String integer, String fraction}) splitAmount(num value, {int decimals = 2}) {
  final s = formatAmount(value, decimals: decimals);
  final dot = s.indexOf('.');
  if (dot < 0) return (integer: s, fraction: '');
  return (integer: s.substring(0, dot), fraction: s.substring(dot));
}
