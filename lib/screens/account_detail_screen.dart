import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../core/refresh_bus.dart';
import '../core/theme.dart';
import '../models/account.dart';
import '../models/bill.dart';
import '../services/api_service.dart';
import 'add_bill_screen.dart';

/// 账户详情页：根据账户类型展示不同的 hero / 统计区，
/// 下面再统一展示该账户的所有账单（按日期分组、支持分页）。
class AccountDetailScreen extends StatefulWidget {
  const AccountDetailScreen({super.key, required this.accountId});

  final String accountId;

  @override
  State<AccountDetailScreen> createState() => _AccountDetailScreenState();
}

class _AccountDetailScreenState extends State<AccountDetailScreen> {
  Account? _account;
  bool _loadingAccount = true;

  final _scroll = ScrollController();
  List<Bill> _bills = [];
  bool _loadingBills = true;
  bool _loadingMore = false;
  bool _hasMore = true;
  int _page = 1;

  double _totalIncome = 0;
  double _totalExpense = 0;

  @override
  void initState() {
    super.initState();
    refreshBus.addListener(_onBump);
    _loadAccount();
    _loadBills(refresh: true);
    _scroll.addListener(() {
      if (_scroll.position.pixels >=
              _scroll.position.maxScrollExtent - 200 &&
          !_loadingMore &&
          _hasMore) {
        _loadMoreBills();
      }
    });
  }

  @override
  void dispose() {
    refreshBus.removeListener(_onBump);
    _scroll.dispose();
    super.dispose();
  }

  void _onBump() {
    if (!mounted) return;
    _loadAccount();
    _loadBills(refresh: true);
  }

  Future<void> _loadAccount() async {
    try {
      // 复用列表接口找出当前账户（带 info）；后端没有单账户 GET
      final res = await ApiService.getAccounts(scope: 'all');
      if (!mounted) return;
      final list = (res['accounts'] as List? ?? [])
          .map((a) => Account.fromJson(a as Map<String, dynamic>))
          .toList();
      Account? found;
      for (final a in list) {
        if (a.id == widget.accountId) {
          found = a;
          break;
        }
      }
      setState(() {
        _account = found;
        _loadingAccount = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loadingAccount = false);
    }
  }

  Future<void> _loadBills({bool refresh = false}) async {
    if (refresh) {
      setState(() {
        _loadingBills = true;
        _page = 1;
        _hasMore = true;
      });
    }
    try {
      final res = await ApiService.getBills(
        page: 1,
        limit: 20,
        accountId: widget.accountId,
      );
      if (!mounted) return;
      setState(() {
        _bills = (res['bills'] as List? ?? [])
            .map((b) => Bill.fromJson(b as Map<String, dynamic>))
            .toList();
        _totalIncome =
            (res['summary']?['totalIncome'] as num?)?.toDouble() ?? 0;
        _totalExpense =
            (res['summary']?['totalExpense'] as num?)?.toDouble() ?? 0;
        _hasMore = _bills.length >= 20;
        _page = 2;
        _loadingBills = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loadingBills = false);
    }
  }

  Future<void> _loadMoreBills() async {
    setState(() => _loadingMore = true);
    try {
      final res = await ApiService.getBills(
        page: _page,
        limit: 20,
        accountId: widget.accountId,
      );
      if (!mounted) return;
      final more = (res['bills'] as List? ?? [])
          .map((b) => Bill.fromJson(b as Map<String, dynamic>))
          .toList();
      setState(() {
        _bills.addAll(more);
        _hasMore = more.length >= 20;
        _page++;
        _loadingMore = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loadingMore = false);
    }
  }

  Future<void> _deleteBill(Bill bill) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16)),
        title: const Text('确认删除'),
        content: Text(
            '删除「${bill.category.name}」¥${bill.amount.toStringAsFixed(2)}？'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('取消')),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('删除',
                style: TextStyle(color: AppColors.expense)),
          ),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await ApiService.deleteBill(bill.id);
      bumpRefresh();
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('删除失败'),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  Map<String, List<Bill>> get _grouped {
    final map = <String, List<Bill>>{};
    for (final b in _bills) {
      final key = DateFormat('yyyy-MM-dd').format(b.date);
      map.putIfAbsent(key, () => []).add(b);
    }
    return map;
  }

  @override
  Widget build(BuildContext context) {
    if (_loadingAccount && _account == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('账户详情')),
        body: Center(
            child: CircularProgressIndicator(color: AppColors.primary)),
      );
    }
    if (_account == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('账户详情')),
        body: Center(
          child: Text('账户不存在或没有访问权限',
              style: TextStyle(color: AppColors.text2)),
        ),
      );
    }
    final a = _account!;
    return Scaffold(
      appBar: AppBar(
        title: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(a.typeEmoji, style: const TextStyle(fontSize: 18)),
            const SizedBox(width: 8),
            Flexible(
              child: Text(a.name,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 16)),
            ),
          ],
        ),
      ),
      body: RefreshIndicator(
        color: AppColors.primary,
        onRefresh: () async {
          await _loadAccount();
          await _loadBills(refresh: true);
        },
        child: CustomScrollView(
          controller: _scroll,
          slivers: [
            // ── Hero header ──────────────────────────────
            SliverToBoxAdapter(child: _heroHeader(a)),
            // ── 类型相关详情卡 ────────────────────────────
            SliverToBoxAdapter(child: _typeSpecificCard(a)),
            // ── 账户内汇总（收入/支出） ───────────────────
            if (a.balanceVisible) SliverToBoxAdapter(child: _summary()),
            // ── 账单列表 header ──────────────────────────
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 18, 20, 8),
                child: Row(children: [
                  Text('账单明细',
                      style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: AppColors.text1)),
                  const SizedBox(width: 6),
                  Text('共 ${_bills.length} 条',
                      style: TextStyle(
                          fontSize: 11, color: AppColors.text3)),
                ]),
              ),
            ),
            // ── 账单列表 ──────────────────────────────────
            if (_loadingBills)
              SliverFillRemaining(
                hasScrollBody: false,
                child: Center(
                  child: CircularProgressIndicator(
                      color: AppColors.primary),
                ),
              )
            else if (_bills.isEmpty)
              SliverFillRemaining(
                hasScrollBody: false,
                child: _emptyBills(),
              )
            else
              _billsSliver(),
            const SliverToBoxAdapter(child: SizedBox(height: 24)),
          ],
        ),
      ),
    );
  }

  // ── Hero header（顶部大卡） ────────────────────────────────
  Widget _heroHeader(Account a) {
    // 信用卡 / 负债：用"欠款"标签；正向账户用"当前余额"
    String label;
    double value;
    Color valueColor;
    if (a.isCredit) {
      final owed = a.balance < 0 ? -a.balance : 0.0;
      label = '当前欠款';
      value = owed;
      valueColor = owed > 0
          ? AppColors.expenseLight
          : AppColors.onPrimaryGradient;
    } else if (a.isDebt) {
      final owed = a.balance < 0 ? -a.balance : a.balance.abs();
      label = '剩余欠款';
      value = owed;
      valueColor = AppColors.onPrimaryGradient;
    } else {
      label = '当前余额';
      value = a.balance;
      valueColor = AppColors.onPrimaryGradient;
    }
    final fg = AppColors.onPrimaryGradient;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: AppColors.primaryGradient,
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: fg.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Center(
                  child:
                      Text(a.typeEmoji, style: const TextStyle(fontSize: 22)),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(a.name,
                        style: TextStyle(
                            color: fg,
                            fontSize: 16,
                            fontWeight: FontWeight.w600)),
                    const SizedBox(height: 2),
                    Row(children: [
                      Text(a.typeLabel,
                          style: TextStyle(
                              color: fg.withOpacity(0.65), fontSize: 12)),
                      if (a.isShared) ...[
                        const SizedBox(width: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 5, vertical: 1),
                          decoration: BoxDecoration(
                            color: fg.withOpacity(0.18),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text('共享',
                              style: TextStyle(
                                  fontSize: 10,
                                  color: fg,
                                  fontWeight: FontWeight.w600)),
                        ),
                      ],
                    ]),
                  ],
                ),
              ),
            ]),
            const SizedBox(height: 18),
            Text(label,
                style:
                    TextStyle(color: fg.withOpacity(0.7), fontSize: 12)),
            const SizedBox(height: 4),
            Text(
              a.balanceVisible
                  ? '¥${value.toStringAsFixed(2)}'
                  : '****',
              style: TextStyle(
                  color: valueColor,
                  fontSize: 34,
                  fontWeight: FontWeight.bold,
                  letterSpacing: -1),
            ),
            // 信用卡显示额度进度
            if (a.isCredit && (a.creditLimit ?? 0) > 0) ...[
              const SizedBox(height: 12),
              _creditUsageBar(a),
            ],
            // 负债显示还款进度
            if (a.isDebt && (a.info?.totalPeriods ?? 0) > 0) ...[
              const SizedBox(height: 12),
              _debtProgressBar(a),
            ],
          ],
        ),
      ),
    );
  }

  Widget _creditUsageBar(Account a) {
    final limit = a.creditLimit ?? 0;
    final used = a.balance < 0 ? -a.balance : 0.0;
    final ratio = limit > 0 ? (used / limit).clamp(0.0, 1.0) : 0.0;
    final fg = AppColors.onPrimaryGradient;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(children: [
          Text('已用额度',
              style:
                  TextStyle(color: fg.withOpacity(0.7), fontSize: 11)),
          const Spacer(),
          Text(
              '¥${used.toStringAsFixed(0)} / ¥${limit.toStringAsFixed(0)}',
              style: TextStyle(
                  color: fg,
                  fontSize: 11,
                  fontWeight: FontWeight.w600)),
        ]),
        const SizedBox(height: 6),
        ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: LinearProgressIndicator(
            value: ratio,
            minHeight: 6,
            backgroundColor: fg.withOpacity(0.15),
            valueColor: AlwaysStoppedAnimation<Color>(
              ratio > 0.9
                  ? AppColors.expenseLight
                  : ratio > 0.7
                      ? AppColors.warningLight
                      : fg,
            ),
          ),
        ),
        const SizedBox(height: 4),
        Text('使用率 ${(ratio * 100).toStringAsFixed(0)}%',
            style:
                TextStyle(color: fg.withOpacity(0.55), fontSize: 10)),
      ],
    );
  }

  Widget _debtProgressBar(Account a) {
    final info = a.info!;
    final paid = info.paidPeriods ?? 0;
    final total = info.totalPeriods ?? 1;
    final ratio = (paid / total).clamp(0.0, 1.0);
    final fg = AppColors.onPrimaryGradient;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(children: [
          Text('还款进度',
              style:
                  TextStyle(color: fg.withOpacity(0.7), fontSize: 11)),
          const Spacer(),
          Text('$paid / $total 期',
              style: TextStyle(
                  color: fg,
                  fontSize: 11,
                  fontWeight: FontWeight.w600)),
        ]),
        const SizedBox(height: 6),
        ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: LinearProgressIndicator(
            value: ratio,
            minHeight: 6,
            backgroundColor: fg.withOpacity(0.15),
            valueColor: AlwaysStoppedAnimation<Color>(fg),
          ),
        ),
        const SizedBox(height: 4),
        Text('已完成 ${(ratio * 100).toStringAsFixed(1)}%',
            style:
                TextStyle(color: fg.withOpacity(0.55), fontSize: 10)),
      ],
    );
  }

  // ── 类型相关详情卡 ────────────────────────────────────────
  Widget _typeSpecificCard(Account a) {
    switch (a.type) {
      case 'CREDIT':
        return _creditDetailCard(a);
      case 'DEBT':
        return _debtDetailCard(a);
      case 'INSURANCE':
        return _insuranceDetailCard(a);
      case 'INVESTMENT':
        return _investmentDetailCard(a);
      default:
        return const SizedBox.shrink();
    }
  }

  Widget _sectionCard({
    required String title,
    required String emoji,
    required List<Widget> children,
  }) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
      child: Container(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppColors.border),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              Text(emoji, style: const TextStyle(fontSize: 16)),
              const SizedBox(width: 6),
              Text(title,
                  style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: AppColors.text1)),
            ]),
            const SizedBox(height: 10),
            ...children,
          ],
        ),
      ),
    );
  }

  Widget _kvRow(String k, String v, {Color? valueColor, bool bold = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(k,
              style: TextStyle(
                  fontSize: 12, color: AppColors.text2)),
          const SizedBox(width: 10),
          const Spacer(),
          Flexible(
            child: Text(v,
                textAlign: TextAlign.right,
                style: TextStyle(
                    fontSize: 13,
                    color: valueColor ?? AppColors.text1,
                    fontWeight: bold ? FontWeight.w700 : FontWeight.w500)),
          ),
        ],
      ),
    );
  }

  Widget _creditDetailCard(Account a) {
    final i = a.info;
    final fmt = DateFormat('M月d日');
    return _sectionCard(
      title: '本期账单',
      emoji: '💳',
      children: [
        if (i?.periodStart != null && i?.periodEnd != null)
          _kvRow('账期',
              '${fmt.format(i!.periodStart!)} ~ ${fmt.format(i.periodEnd!)}'),
        if (i?.periodBill != null)
          _kvRow('本期账单', '¥${i!.periodBill!.toStringAsFixed(2)}',
              bold: true),
        if ((i?.paid ?? 0) > 0)
          _kvRow('已还', '¥${i!.paid!.toStringAsFixed(2)}',
              valueColor: AppColors.income),
        if ((i?.unpaid ?? 0) > 0)
          _kvRow('未还', '¥${i!.unpaid!.toStringAsFixed(2)}',
              valueColor: AppColors.expense, bold: true),
        if ((i?.ongoingSpent ?? 0) > 0)
          _kvRow('下期未出账', '¥${i!.ongoingSpent!.toStringAsFixed(2)}',
              valueColor: AppColors.text2),
        const Divider(height: 18),
        if (a.statementDay != null)
          _kvRow('账单日', '每月 ${a.statementDay} 号'),
        if (a.dueDay != null) _kvRow('还款日', '每月 ${a.dueDay} 号'),
        if (i?.dueDate != null)
          _kvRow(
            '下次还款',
            i!.isOverdue
                ? '已逾期 ${-(i.daysToDue ?? 0)} 天'
                : i.isDueToday
                    ? '今天'
                    : i.isDueTomorrow
                        ? '明天'
                        : '${fmt.format(i.dueDate!)} (剩 ${i.daysToDue ?? 0} 天)',
            valueColor: i.isOverdue || i.isDueToday || i.isDueTomorrow
                ? AppColors.expense
                : null,
            bold: i.isOverdue || i.isDueToday,
          ),
        if (a.creditLimit != null)
          _kvRow('信用额度', '¥${a.creditLimit!.toStringAsFixed(0)}'),
      ],
    );
  }

  Widget _debtDetailCard(Account a) {
    final i = a.info;
    final fmt = DateFormat('yyyy-MM-dd');
    return _sectionCard(
      title: '贷款详情',
      emoji: '🏚️',
      children: [
        if (a.loanPrincipal != null)
          _kvRow('贷款本金', '¥${a.loanPrincipal!.toStringAsFixed(0)}'),
        if (a.loanTermMonths != null)
          _kvRow('贷款期限',
              '${a.loanTermMonths} 个月 (${(a.loanTermMonths! / 12).toStringAsFixed(0)} 年)'),
        if (a.interestRate != null)
          _kvRow('年利率', '${a.interestRate!.toStringAsFixed(2)}%'),
        if (a.repaymentMethodLabel != null)
          _kvRow('还款方式', a.repaymentMethodLabel!),
        if (a.firstPaymentDate != null)
          _kvRow('首次还款', fmt.format(a.firstPaymentDate!)),
        if (a.dueDay != null) _kvRow('每月还款日', '每月 ${a.dueDay} 号'),
        const Divider(height: 18),
        if ((i?.monthlyPayment ?? 0) > 0)
          _kvRow('月供', '¥${i!.monthlyPayment!.toStringAsFixed(2)}',
              valueColor: AppColors.primary, bold: true),
        if ((i?.monthlyInterest ?? 0) > 0)
          _kvRow('当期月息估算',
              '¥${i!.monthlyInterest!.toStringAsFixed(0)}',
              valueColor: AppColors.text2),
        if (i?.dueDate != null)
          _kvRow(
            '下次还款',
            i!.isDueToday
                ? '今天'
                : i.isDueTomorrow
                    ? '明天'
                    : '${DateFormat('M月d日').format(i.dueDate!)} (剩 ${i.daysToDue ?? 0} 天)',
            valueColor: i.isDueToday || i.isDueTomorrow
                ? AppColors.expense
                : null,
            bold: i.isDueToday,
          ),
      ],
    );
  }

  Widget _insuranceDetailCard(Account a) {
    final i = a.info;
    final fmt = DateFormat('yyyy-MM-dd');
    return _sectionCard(
      title: '自动入账',
      emoji: '🛡️',
      children: [
        if (a.autoDepositDay != null && a.autoDepositAmount != null) ...[
          _kvRow('每月入账日', '每月 ${a.autoDepositDay} 号'),
          _kvRow('入账金额',
              '¥${a.autoDepositAmount!.toStringAsFixed(2)}',
              valueColor: AppColors.income, bold: true),
          if (i?.lastDepositDate != null)
            _kvRow('上次入账', fmt.format(i!.lastDepositDate!)),
          if (i?.nextDepositDate != null)
            _kvRow('下次入账', fmt.format(i!.nextDepositDate!),
                valueColor: AppColors.primary, bold: true),
        ] else
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Text(
              '未设置自动入账。可在「编辑账户」中开启，下次打开账户时会自动补齐入账。',
              style: TextStyle(fontSize: 12, color: AppColors.text2),
            ),
          ),
      ],
    );
  }

  Widget _investmentDetailCard(Account a) {
    return _sectionCard(
      title: '投资账户',
      emoji: '📈',
      children: [
        _kvRow('账户余额', '¥${a.balance.toStringAsFixed(2)}',
            bold: true),
        const SizedBox(height: 2),
        Text(
          '建议在每次买入/卖出 / 收到分红时记一笔，方便追溯收益。',
          style: TextStyle(
              fontSize: 11, color: AppColors.text3, height: 1.4),
        ),
      ],
    );
  }

  // ── 汇总：累计收入/支出 ────────────────────────────────────
  Widget _summary() {
    final net = _totalIncome - _totalExpense;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppColors.border),
        ),
        child: Row(children: [
          Expanded(
            child: _stat('收入', '+¥${_totalIncome.toStringAsFixed(2)}',
                AppColors.income),
          ),
          Container(
              width: 1, height: 32, color: AppColors.border),
          Expanded(
            child: _stat('支出', '-¥${_totalExpense.toStringAsFixed(2)}',
                AppColors.expense),
          ),
          Container(
              width: 1, height: 32, color: AppColors.border),
          Expanded(
            child: _stat(
                '净额',
                '${net >= 0 ? '+' : '-'}¥${net.abs().toStringAsFixed(2)}',
                net >= 0 ? AppColors.income : AppColors.expense),
          ),
        ]),
      ),
    );
  }

  Widget _stat(String label, String value, Color color) => Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Text(label,
              style:
                  TextStyle(fontSize: 11, color: AppColors.text2)),
          const SizedBox(height: 4),
          Text(value,
              style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: color)),
        ],
      );

  // ── 账单 sliver（按日分组） ────────────────────────────────
  Widget _billsSliver() {
    final groups = _grouped;
    final dates = groups.keys.toList();
    return SliverList(
      delegate: SliverChildBuilderDelegate(
        (_, i) {
          if (i == dates.length) {
            if (_loadingMore) {
              return Padding(
                padding: const EdgeInsets.all(16),
                child: Center(
                    child: CircularProgressIndicator(
                        color: AppColors.primary)),
              );
            }
            return const SizedBox(height: 8);
          }
          final date = dates[i];
          final items = groups[date]!;
          final dayIncome =
              items.where((b) => b.isIncome).fold(0.0, (s, b) => s + b.amount);
          final dayExpense = items
              .where((b) => !b.isIncome)
              .fold(0.0, (s, b) => s + b.amount);
          return Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(height: 8),
                Row(children: [
                  Text(_formatDate(date),
                      style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: AppColors.text2)),
                  const Spacer(),
                  if (dayIncome > 0)
                    Text('+¥${dayIncome.toStringAsFixed(2)} ',
                        style: const TextStyle(
                            fontSize: 11, color: AppColors.income)),
                  if (dayExpense > 0)
                    Text('-¥${dayExpense.toStringAsFixed(2)}',
                        style: const TextStyle(
                            fontSize: 11, color: AppColors.expense)),
                ]),
                const SizedBox(height: 6),
                Container(
                  decoration: BoxDecoration(
                    color: AppColors.surface,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: AppColors.border),
                  ),
                  child: Column(
                    children: items.asMap().entries.map((e) {
                      final isLast = e.key == items.length - 1;
                      return _BillRow(
                        bill: e.value,
                        showDivider: !isLast,
                        onTap: () async {
                          final ok = await Navigator.push<bool>(
                            context,
                            MaterialPageRoute(
                              builder: (_) => AddBillScreen(bill: e.value),
                            ),
                          );
                          if (ok == true) _onBump();
                        },
                        onDelete: () => _deleteBill(e.value),
                      );
                    }).toList(),
                  ),
                ),
              ],
            ),
          );
        },
        childCount: dates.length + 1,
      ),
    );
  }

  String _formatDate(String dateStr) {
    final date = DateTime.parse(dateStr);
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final yesterday = today.subtract(const Duration(days: 1));
    final d = DateTime(date.year, date.month, date.day);
    if (d == today) return '今天';
    if (d == yesterday) return '昨天';
    return DateFormat('M月d日 EEEE', 'zh').format(date);
  }

  Widget _emptyBills() => Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const SizedBox(height: 24),
            const Text('🧾', style: TextStyle(fontSize: 42)),
            const SizedBox(height: 10),
            Text('该账户还没有账单',
                style:
                    TextStyle(color: AppColors.text2, fontSize: 14)),
            const SizedBox(height: 4),
            Text('记账时选择该账户即可自动归档',
                style:
                    TextStyle(color: AppColors.text3, fontSize: 12)),
          ],
        ),
      );
}

// ── 简化版账单行（详情页内不重复显示账户名） ─────────────────
class _BillRow extends StatelessWidget {
  const _BillRow({
    required this.bill,
    required this.showDivider,
    required this.onTap,
    required this.onDelete,
  });

  final Bill bill;
  final bool showDivider;
  final VoidCallback onTap;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(14),
          child: Padding(
            padding:
                const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            child: Row(children: [
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: bill.isIncome
                      ? AppColors.incomeLight
                      : AppColors.expenseLight,
                  borderRadius: BorderRadius.circular(11),
                ),
                child: Center(
                  child: Text(
                    bill.category.icon ?? (bill.isIncome ? '💰' : '💸'),
                    style: const TextStyle(fontSize: 18),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(children: [
                      Flexible(
                        child: Text(bill.category.name,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w500,
                                color: AppColors.text1)),
                      ),
                      if (bill.recorderName != null) ...[
                        const SizedBox(width: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 5, vertical: 1),
                          decoration: BoxDecoration(
                            color: AppColors.surfaceAlt,
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(bill.recorderName!,
                              style: TextStyle(
                                  fontSize: 10,
                                  color: AppColors.text2,
                                  fontWeight: FontWeight.w500)),
                        ),
                      ],
                    ]),
                    if (bill.note.isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(bill.note,
                          style: TextStyle(
                              fontSize: 12, color: AppColors.text2),
                          overflow: TextOverflow.ellipsis),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                Text(bill.amountText,
                    style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        color: bill.isIncome
                            ? AppColors.income
                            : AppColors.expense)),
                const SizedBox(height: 2),
                Text(DateFormat('HH:mm').format(bill.date),
                    style: TextStyle(
                        fontSize: 11, color: AppColors.text2)),
              ]),
              const SizedBox(width: 4),
              GestureDetector(
                onTap: onDelete,
                child: Padding(
                  padding: const EdgeInsets.all(4),
                  child: Icon(Icons.delete_outline_rounded,
                      size: 18, color: AppColors.text2),
                ),
              ),
            ]),
          ),
        ),
        if (showDivider) const Divider(height: 1, indent: 64),
      ],
    );
  }
}
