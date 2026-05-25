import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../core/refresh_bus.dart';
import '../core/theme.dart';
import '../crypto/key_chain.dart';
import '../models/account.dart';
import '../services/api_service.dart';
import '../services/auth_service.dart';
import '../services/pending_dek_resolver.dart';
import 'account_detail_screen.dart';

double math_pow(double a, double b) => math.pow(a, b).toDouble();

class AccountsScreen extends StatefulWidget {
  const AccountsScreen({super.key});
  @override
  State<AccountsScreen> createState() => _AccountsScreenState();
}

class _AccountsScreenState extends State<AccountsScreen>
    with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  List<Account> _accounts = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    refreshBus.addListener(_onBump);
    _load();
  }

  @override
  void dispose() {
    refreshBus.removeListener(_onBump);
    super.dispose();
  }

  void _onBump() {
    if (mounted) _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      // 进入账户页时：如果本账本 DEK 还没拿到（pending 状态），尝试重拉一次
      final cur = await AuthService.getCurrentLedgerId();
      if (cur != null && !KeyChain.instance.hasDek(cur)) {
        await PendingDekResolver.rehydrate(requireLedgerId: cur);
      }
      final res = await ApiService.getAccounts();
      if (!mounted) return;
      setState(() {
        _accounts = (res['accounts'] as List? ?? [])
            .map((a) => Account.fromJson(a as Map<String, dynamic>))
            .toList();
        _loading = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  double get _totalBalance =>
      _accounts.fold(0.0, (s, a) => s + a.balance);

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return Scaffold(
      appBar: AppBar(
        title: const Text('账户'),
        actions: [
          IconButton(
            tooltip: '添加账户',
            icon: const Icon(Icons.add_rounded),
            onPressed: () => _showAccountSheet(context),
          ),
        ],
      ),
      body: _loading
          ? Center(
              child: CircularProgressIndicator(color: AppColors.primary))
          : RefreshIndicator(
              color: AppColors.primary,
              onRefresh: _load,
              child: _accounts.isEmpty ? _empty() : _list(),
            ),
    );
  }

  Widget _list() {
    return CustomScrollView(
      slivers: [
        // Total balance card
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
            child: Builder(builder: (_) {
              final fg = AppColors.onPrimaryGradient;
              return Container(
                padding: const EdgeInsets.all(24),
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
                    Text('总资产',
                        style: TextStyle(color: fg.withOpacity(0.7), fontSize: 13)),
                    const SizedBox(height: 6),
                    Text(
                      '¥${_totalBalance.toStringAsFixed(2)}',
                      style: TextStyle(
                          color: fg,
                          fontSize: 36,
                          fontWeight: FontWeight.bold,
                          letterSpacing: -1),
                    ),
                    const SizedBox(height: 4),
                    Text('共 ${_accounts.length} 个账户',
                        style: TextStyle(
                            color: fg.withOpacity(0.55), fontSize: 12)),
                  ],
                ),
              );
            }),
          ),
        ),
        // —— 我的账户 ——
        if (_mineAccounts.isNotEmpty) _sectionSliver('我的账户', _mineAccounts.length),
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
          sliver: SliverList(
            delegate: SliverChildBuilderDelegate(
              (_, i) => _AccountTile(
                account: _mineAccounts[i],
                onEdit: () => _showAccountSheet(context,
                    account: _mineAccounts[i]),
                onDelete: () => _deleteAccount(_mineAccounts[i]),
              ),
              childCount: _mineAccounts.length,
            ),
          ),
        ),
        // —— 共享账户 ——
        if (_sharedAccounts.isNotEmpty)
          _sectionSliver('共享账户', _sharedAccounts.length, hint: '账本成员共用'),
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 100),
          sliver: SliverList(
            delegate: SliverChildBuilderDelegate(
              (_, i) => _AccountTile(
                account: _sharedAccounts[i],
                onEdit: () => _showAccountSheet(context,
                    account: _sharedAccounts[i]),
                onDelete: () => _deleteAccount(_sharedAccounts[i]),
              ),
              childCount: _sharedAccounts.length,
            ),
          ),
        ),
      ],
    );
  }

  List<Account> get _mineAccounts =>
      _accounts.where((a) => !a.isShared).toList();
  List<Account> get _sharedAccounts =>
      _accounts.where((a) => a.isShared).toList();

  Widget _sectionSliver(String title, int count, {String? hint}) =>
      SliverToBoxAdapter(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 18, 20, 6),
          child: Row(children: [
            Text(title,
                style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: AppColors.text2)),
            const SizedBox(width: 6),
            Text('· $count',
                style: TextStyle(fontSize: 12, color: AppColors.text3)),
            if (hint != null) ...[
              const Spacer(),
              Text(hint,
                  style: TextStyle(fontSize: 11, color: AppColors.text3)),
            ],
          ]),
        ),
      );

  Future<void> _deleteAccount(Account account) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16)),
        title: const Text('确认删除'),
        content: Text('删除账户「${account.name}」？\n该账户下的账单也会一并删除。'),
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
      await ApiService.deleteAccount(account.id);
      bumpRefresh();
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('删除失败'),
          behavior: SnackBarBehavior.floating,
        ));
      }
    }
  }

  void _showAccountSheet(BuildContext context, {Account? account}) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _AccountSheet(
        account: account,
        onSaved: bumpRefresh,
      ),
    );
  }

  Widget _empty() => Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Text('🏦', style: TextStyle(fontSize: 56)),
            const SizedBox(height: 16),
            Text('还没有账户',
                style:
                    TextStyle(color: AppColors.text2, fontSize: 16)),
            const SizedBox(height: 6),
            Text('点击右上角 + 添加账户',
                style:
                    TextStyle(color: AppColors.text2, fontSize: 13)),
            const SizedBox(height: 24),
            ElevatedButton.icon(
              onPressed: () => _showAccountSheet(context),
              icon: const Icon(Icons.add_rounded),
              label: const Text('添加账户'),
            ),
          ],
        ),
      );
}

// ── Account tile ──────────────────────────────────────────────
class _AccountTile extends StatelessWidget {
  const _AccountTile({
    required this.account,
    required this.onEdit,
    required this.onDelete,
  });

  final Account account;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  /// 余额显示：信用卡和负债用绝对值，标签换成"欠款"，颜色用红色
  (String label, double value, Color color) get _balanceDisplay {
    if (account.isCredit) {
      final owed = account.balance < 0 ? -account.balance : 0;
      return ('欠款', owed.toDouble(),
          owed > 0 ? AppColors.expense : AppColors.text1);
    }
    if (account.isDebt) {
      final owed =
          account.balance < 0 ? -account.balance : account.balance.abs();
      return ('欠款', owed,
          owed > 0 ? AppColors.expense : AppColors.text1);
    }
    return (
      '余额',
      account.balance,
      account.balance >= 0 ? AppColors.text1 : AppColors.expense
    );
  }

  @override
  Widget build(BuildContext context) {
    final (balLabel, balValue, balColor) = _balanceDisplay;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Material(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: () {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) =>
                    AccountDetailScreen(accountId: account.id),
              ),
            );
          },
          child: Container(
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppColors.border),
        ),
        child: Column(
          children: [
            ListTile(
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
              leading: Container(
                width: 46,
                height: 46,
                decoration: BoxDecoration(
                  color: AppColors.surfaceAlt,
                  borderRadius: BorderRadius.circular(13),
                ),
                child: Center(
                  child: Text(account.typeEmoji,
                      style: const TextStyle(fontSize: 22)),
                ),
              ),
              title: Row(children: [
                Flexible(
                  child: Text(account.name,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                          color: AppColors.text1)),
                ),
                if (account.isShared) ...[
                  const SizedBox(width: 6),
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 5, vertical: 1),
                    decoration: BoxDecoration(
                      color: AppColors.primary.withOpacity(0.12),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text('共享',
                        style: TextStyle(
                            fontSize: 10,
                            color: AppColors.primary,
                            fontWeight: FontWeight.w600)),
                  ),
                ],
              ]),
              subtitle: Text(
                  account.isShared
                      ? '${account.typeLabel} · 账本共用'
                      : account.typeLabel,
                  style:
                      TextStyle(fontSize: 12, color: AppColors.text2)),
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(
                        '¥${balValue.toStringAsFixed(2)}',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: balColor,
                        ),
                      ),
                      Text(balLabel,
                          style: TextStyle(
                              fontSize: 11, color: AppColors.text2)),
                    ],
                  ),
                  const SizedBox(width: 8),
                  PopupMenuButton<String>(
                    icon: Icon(Icons.more_vert_rounded,
                        color: AppColors.text2, size: 20),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12)),
                    itemBuilder: (_) => [
                      PopupMenuItem(
                          value: 'edit',
                          child: Row(children: [
                            Icon(Icons.edit_outlined,
                                size: 18, color: AppColors.text2),
                            SizedBox(width: 10),
                            Text('编辑'),
                          ])),
                      const PopupMenuItem(
                          value: 'delete',
                          child: Row(children: [
                            Icon(Icons.delete_outline_rounded,
                                size: 18, color: AppColors.expense),
                            SizedBox(width: 10),
                            Text('删除',
                                style: TextStyle(color: AppColors.expense)),
                          ])),
                    ],
                    onSelected: (v) {
                      if (v == 'edit') onEdit();
                      if (v == 'delete') onDelete();
                    },
                  ),
                ],
              ),
            ),
            // ── 类型相关信息条 ─────────────────────────────────
            if (account.info != null) _infoBanner(account.info!),
          ],
        ),
      ),
        ),
      ),
    );
  }

  Widget _infoBanner(AccountInfo info) {
    switch (info.kind) {
      case 'credit':
        return _creditBanner(info);
      case 'debt':
        return _debtBanner(info);
      case 'auto_deposit':
        return _autoDepositBanner(info);
      default:
        return const SizedBox.shrink();
    }
  }

  Widget _creditBanner(AccountInfo i) {
    final bill = i.periodBill ?? 0;
    final unpaid = i.unpaid ?? 0;
    final paid = i.paid ?? 0;
    final ongoing = i.ongoingSpent ?? 0;
    final overdue = i.isOverdue;
    final dueToday = i.isDueToday;
    final dueTomorrow = i.isDueTomorrow;
    final urgent = overdue || dueToday || dueTomorrow;
    final color = unpaid > 0
        ? (urgent ? AppColors.expense : AppColors.warning)
        : AppColors.income;

    String urgentText() {
      if (overdue) return '已逾期 ${-(i.daysToDue ?? 0)} 天';
      if (dueToday) return '今天还款日';
      if (dueTomorrow) return '明天还款日';
      return '剩 ${i.daysToDue ?? 0} 天';
    }

    return Container(
      padding: const EdgeInsets.fromLTRB(14, 8, 14, 12),
      decoration: BoxDecoration(
        border:
            Border(top: BorderSide(color: AppColors.border, width: 1)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Text('本期账单',
                style: TextStyle(
                    fontSize: 11, color: AppColors.text2)),
            const SizedBox(width: 4),
            Text('¥${bill.toStringAsFixed(2)}',
                style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: AppColors.text1)),
            const Spacer(),
            if (unpaid > 0)
              Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: color.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(urgentText(),
                    style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: color)),
              )
            else if (bill > 0)
              Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: AppColors.income.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  Icon(Icons.check_circle_rounded,
                      size: 12, color: AppColors.income),
                  const SizedBox(width: 2),
                  Text('已还清',
                      style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color: AppColors.income)),
                ]),
              ),
          ]),
          const SizedBox(height: 3),
          Wrap(
            spacing: 10,
            runSpacing: 2,
            children: [
              if (unpaid > 0)
                _kv('未还', '¥${unpaid.toStringAsFixed(2)}',
                    color: color),
              if (paid > 0 && unpaid > 0)
                _kv('已还', '¥${paid.toStringAsFixed(2)}'),
              if (ongoing > 0) _kv('未出账', '¥${ongoing.toStringAsFixed(2)}'),
              if (i.dueDate != null)
                _kv('还款日', _md(i.dueDate!)),
            ],
          ),
        ],
      ),
    );
  }

  Widget _debtBanner(AccountInfo i) {
    final urgent = i.isDueToday || i.isDueTomorrow;
    final color = urgent ? AppColors.expense : AppColors.text2;
    final repayLabel = account.repaymentMethodLabel;
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 8, 14, 12),
      decoration: BoxDecoration(
        border:
            Border(top: BorderSide(color: AppColors.border, width: 1)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Icon(Icons.event_rounded, size: 14, color: color),
            const SizedBox(width: 4),
            Text(
              i.isDueToday
                  ? '今天还款日'
                  : i.isDueTomorrow
                      ? '明天还款日'
                      : (i.dueDate != null
                          ? '下次还款 ${_md(i.dueDate!)}'
                          : '还款日未设'),
              style: TextStyle(
                  fontSize: 12,
                  color: color,
                  fontWeight:
                      urgent ? FontWeight.w700 : FontWeight.w500),
            ),
            const Spacer(),
            if (repayLabel != null)
              Text(repayLabel,
                  style: TextStyle(
                      fontSize: 11, color: AppColors.text3)),
          ]),
          if ((i.monthlyPayment ?? 0) > 0) ...[
            const SizedBox(height: 4),
            Row(children: [
              Icon(Icons.payments_outlined,
                  size: 13, color: AppColors.primary),
              const SizedBox(width: 3),
              Text('月供 ',
                  style: TextStyle(
                      fontSize: 11, color: AppColors.text2)),
              Text('¥${i.monthlyPayment!.toStringAsFixed(2)}',
                  style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: AppColors.primary)),
              if ((i.totalPeriods ?? 0) > 0) ...[
                const SizedBox(width: 8),
                Text(
                  '· 已还 ${i.paidPeriods ?? 0}/${i.totalPeriods} 期',
                  style: TextStyle(
                      fontSize: 11, color: AppColors.text2),
                ),
              ],
            ]),
          ],
          if ((i.interestRate ?? 0) > 0 ||
              account.loanPrincipal != null) ...[
            const SizedBox(height: 3),
            Wrap(
              spacing: 10,
              runSpacing: 2,
              children: [
                if (account.loanPrincipal != null)
                  _kv('本金',
                      '¥${account.loanPrincipal!.toStringAsFixed(0)}'),
                if ((i.interestRate ?? 0) > 0)
                  _kv('年利率', '${i.interestRate!.toStringAsFixed(2)}%'),
                if ((i.monthlyInterest ?? 0) > 0)
                  _kv('月息 ≈',
                      '¥${i.monthlyInterest!.toStringAsFixed(0)}'),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _autoDepositBanner(AccountInfo i) {
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 8, 14, 12),
      decoration: BoxDecoration(
        border:
            Border(top: BorderSide(color: AppColors.border, width: 1)),
      ),
      child: Row(children: [
        Icon(Icons.autorenew_rounded,
            size: 14, color: AppColors.income),
        const SizedBox(width: 4),
        Text(
          '每月自动入账 ¥${(i.amount ?? 0).toStringAsFixed(0)}',
          style: TextStyle(
              fontSize: 12,
              color: AppColors.text1,
              fontWeight: FontWeight.w500),
        ),
        const Spacer(),
        if (i.nextDepositDate != null)
          Text('下次 ${_md(i.nextDepositDate!)}',
              style: TextStyle(fontSize: 11, color: AppColors.text2)),
      ]),
    );
  }

  Widget _kv(String k, String v, {Color? color}) => RichText(
        text: TextSpan(
          children: [
            TextSpan(
                text: '$k ',
                style: TextStyle(
                    fontSize: 11, color: AppColors.text3)),
            TextSpan(
                text: v,
                style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: color ?? AppColors.text1)),
          ],
        ),
      );

  String _md(DateTime d) =>
      '${d.month}月${d.day}日';
}

// ── Add/Edit account bottom sheet ─────────────────────────────
class _AccountSheet extends StatefulWidget {
  const _AccountSheet({this.account, required this.onSaved});
  final Account? account;
  final VoidCallback onSaved;

  @override
  State<_AccountSheet> createState() => _AccountSheetState();
}

/// sheet 的两步：先选类型，再填信息
enum _Step { type, form }

class _AccountSheetState extends State<_AccountSheet> {
  final _nameCtrl = TextEditingController();
  final _balanceCtrl = TextEditingController();
  // 信用卡专用
  final _statementDayCtrl = TextEditingController();
  final _dueDayCtrl = TextEditingController();
  final _creditLimitCtrl = TextEditingController();
  // 负债专用（dueDay 复用）
  final _interestRateCtrl = TextEditingController();
  final _loanPrincipalCtrl = TextEditingController();
  final _loanTermCtrl = TextEditingController();
  DateTime? _firstPaymentDate;
  String? _repaymentMethod;
  // 自动入账（社保 / 公积金）
  final _autoDepositDayCtrl = TextEditingController();
  final _autoDepositAmountCtrl = TextEditingController();
  String _type = 'CASH';
  bool _isShared = false;
  bool _saving = false;
  Map<String, String?> _errors = {};
  /// 新建从"选类型"开始；编辑从"表单"开始
  late _Step _step;

  /// (code, emoji, label, desc)
  static const _types = <(String, String, String, String)>[
    ('CASH',       '💵', '现金',     ''),
    ('BANK',       '🏦', '银行卡',   '储蓄卡 / 借记卡 / 存折'),
    ('VIRTUAL',    '📱', '虚拟账户', '微信 / 支付宝 / 电子钱包'),
    ('CREDIT',     '💳', '信用卡',   '信用卡'),
    ('INVESTMENT', '📈', '投资理财', '理财 / 股票 / 基金 / 债券'),
    ('INSURANCE',  '🛡️', '社保',     '社保 / 公积金 / 商业保险'),
    ('DEBT',       '🏚️', '负债账户', '房贷 / 车贷 / 借款'),
    ('OTHER',      '💰', '其他',     ''),
  ];

  @override
  void initState() {
    super.initState();
    final a = widget.account;
    if (a != null) {
      _nameCtrl.text = a.name;
      // 信用卡/负债账户的 balance 是负数，UI 上让用户看到"欠款"正数
      final isOwedType = a.type == 'CREDIT' || a.type == 'DEBT';
      _balanceCtrl.text = (isOwedType ? a.balance.abs() : a.balance)
          .toStringAsFixed(2);
      _type = a.type;
      _isShared = a.isShared;
      if (a.statementDay != null) {
        _statementDayCtrl.text = a.statementDay.toString();
      }
      if (a.dueDay != null) _dueDayCtrl.text = a.dueDay.toString();
      if (a.creditLimit != null) {
        _creditLimitCtrl.text = a.creditLimit!.toStringAsFixed(0);
      }
      if (a.interestRate != null) {
        _interestRateCtrl.text = a.interestRate!.toStringAsFixed(2);
      }
      if (a.loanPrincipal != null) {
        _loanPrincipalCtrl.text =
            a.loanPrincipal!.toStringAsFixed(0);
      }
      if (a.loanTermMonths != null) {
        _loanTermCtrl.text = a.loanTermMonths.toString();
      }
      _firstPaymentDate = a.firstPaymentDate;
      _repaymentMethod = a.repaymentMethod;
      if (a.autoDepositDay != null) {
        _autoDepositDayCtrl.text = a.autoDepositDay.toString();
      }
      if (a.autoDepositAmount != null) {
        _autoDepositAmountCtrl.text =
            a.autoDepositAmount!.toStringAsFixed(2);
      }
      _step = _Step.form;
    } else {
      _step = _Step.type;
    }
  }

  /// 找到当前 type 对应的 (emoji, label, desc)
  (String, String, String) get _currentTypeMeta {
    for (final t in _types) {
      if (t.$1 == _type) return (t.$2, t.$3, t.$4);
    }
    return ('💰', '其他', '');
  }

  /// 名称建议：根据类型给默认 hint
  String get _nameHint {
    switch (_type) {
      case 'CASH':
        return '如：钱包现金';
      case 'BANK':
        return '如：招行储蓄卡';
      case 'VIRTUAL':
        return '如：支付宝、微信钱包';
      case 'CREDIT':
        return '如：招行信用卡';
      case 'INVESTMENT':
        return '如：富途证券、招行理财';
      case 'INSURANCE':
        return '如：上海社保、住房公积金';
      case 'DEBT':
        return '如：建行房贷、车贷';
      default:
        return '账户名称';
    }
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _balanceCtrl.dispose();
    _statementDayCtrl.dispose();
    _dueDayCtrl.dispose();
    _creditLimitCtrl.dispose();
    _interestRateCtrl.dispose();
    _loanPrincipalCtrl.dispose();
    _loanTermCtrl.dispose();
    _autoDepositDayCtrl.dispose();
    _autoDepositAmountCtrl.dispose();
    super.dispose();
  }

  /// 解析日（1-31），非法返回 null
  int? _parseDay(TextEditingController c) {
    final v = int.tryParse(c.text.trim());
    if (v == null || v < 1 || v > 31) return null;
    return v;
  }

  double? _parseAmount(TextEditingController c) {
    final v = double.tryParse(c.text.trim());
    if (v == null || v < 0) return null;
    return v;
  }

  /// 类型相关的额外字段
  List<Widget> _typeSpecificFields() {
    switch (_type) {
      case 'CREDIT':
        return [
          const SizedBox(height: 18),
          _miniSectionHeader('💳 信用卡设置'),
          const SizedBox(height: 10),
          Row(children: [
            Expanded(
              child: _dayField(
                label: '账单日',
                hint: '如 5',
                controller: _statementDayCtrl,
                helper: '每月这一天出账',
                errorText: _errors['statementDay'],
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _dayField(
                label: '还款日',
                hint: '如 25',
                controller: _dueDayCtrl,
                helper: '每月这一天前还清',
                errorText: _errors['dueDay'],
              ),
            ),
          ]),
          const SizedBox(height: 10),
          _amountField(
            label: '信用额度（选填）',
            hint: '如 50000',
            controller: _creditLimitCtrl,
          ),
          const SizedBox(height: 6),
          _hintTip(
              '记账时选信用卡 = 先消费记账，到账单日后会显示本期账单，还款日临近会提醒。'),
        ];
      case 'DEBT':
        return _debtFields();
      case 'INSURANCE':
        return [
          const SizedBox(height: 18),
          _miniSectionHeader('🛡️ 自动入账设置（选填）'),
          const SizedBox(height: 10),
          Row(children: [
            Expanded(
              child: _dayField(
                label: '每月入账日',
                hint: '如 15',
                controller: _autoDepositDayCtrl,
                errorText: _errors['autoDepositDay'],
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _amountField(
                label: '入账金额',
                hint: '如 800',
                controller: _autoDepositAmountCtrl,
                errorText: _errors['autoDepositAmount'],
              ),
            ),
          ]),
          if (_errors['autoDeposit'] != null) ...[
            const SizedBox(height: 4),
            Text(_errors['autoDeposit']!,
                style: const TextStyle(fontSize: 12, color: Colors.red)),
          ],
          const SizedBox(height: 6),
          _hintTip(
              '填了之后，每次打开账户页会自动补齐错过的入账（不依赖定时任务，不怕服务挂）。'),
        ];
      default:
        return const [];
    }
  }

  /// 负债账户必填字段集合 + 实时月供预览
  List<Widget> _debtFields() {
    final preview = _estimateMonthlyPayment();
    return [
      const SizedBox(height: 18),
      _miniSectionHeader('🏚️ 负债账户设置'),
      const SizedBox(height: 10),
      _amountField(
        label: '贷款本金 *',
        hint: '如 580000',
        controller: _loanPrincipalCtrl,
        allowDecimal: false,
        onChanged: (_) { setState(() {}); _clearError('loanPrincipal'); },
        errorText: _errors['loanPrincipal'],
      ),
      const SizedBox(height: 10),
      // 期限 + 快速选择
      _dayLikeField(
        label: '贷款期限（月）*',
        hint: '如 360 表示 30 年',
        controller: _loanTermCtrl,
        suffix: '月',
        onChanged: (_) { setState(() {}); _clearError('loanTerm'); },
        errorText: _errors['loanTerm'],
      ),
      const SizedBox(height: 4),
      Wrap(
        spacing: 6,
        runSpacing: 6,
        children: const [
          (12, '1年'),
          (36, '3年'),
          (60, '5年'),
          (120, '10年'),
          (240, '20年'),
          (360, '30年'),
        ].map((p) {
          final (months, label) = p;
          final sel = _loanTermCtrl.text.trim() == months.toString();
          return GestureDetector(
            onTap: () => setState(() {
              _loanTermCtrl.text = months.toString();
            }),
            child: Container(
              padding: const EdgeInsets.symmetric(
                  horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: sel ? AppColors.primaryLight : AppColors.surface,
                borderRadius: BorderRadius.circular(6),
                border: Border.all(
                    color: sel
                        ? AppColors.primary
                        : AppColors.border),
              ),
              child: Text(label,
                  style: TextStyle(
                      fontSize: 11,
                      color: sel
                          ? AppColors.primary
                          : AppColors.text2,
                      fontWeight:
                          sel ? FontWeight.w600 : FontWeight.normal)),
            ),
          );
        }).toList(),
      ),
      const SizedBox(height: 12),
      // 月还款日 + 年利率（两个字段统一无 helper，避免高度错位）
      IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: _dayLikeField(
                label: '月还款日 *',
                hint: '如 8',
                controller: _dueDayCtrl,
                suffix: '号',
                onChanged: (_) { setState(() {}); _clearError('dueDay'); },
                errorText: _errors['dueDay'],
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _dayLikeField(
                label: '年利率 % *',
                hint: '如 4.2',
                controller: _interestRateCtrl,
                suffix: '%',
                allowDecimal: true,
                onChanged: (_) { setState(() {}); _clearError('interestRate'); },
                errorText: _errors['interestRate'],
              ),
            ),
          ],
        ),
      ),
      const SizedBox(height: 12),
      _dateField(
        label: '首次还款日期 *',
        value: _firstPaymentDate,
        onChanged: (d) {
          setState(() => _firstPaymentDate = d);
          _clearError('firstPaymentDate');
        },
        errorText: _errors['firstPaymentDate'],
      ),
      const SizedBox(height: 12),
      _label('还款方式 *'),
      const SizedBox(height: 6),
      _repaymentMethodPicker(),
      if (_errors['repaymentMethod'] != null) ...[
        const SizedBox(height: 4),
        Text(_errors['repaymentMethod']!,
            style: const TextStyle(fontSize: 12, color: Colors.red)),
      ],
      const SizedBox(height: 12),
      // 月供预览卡
      Container(
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
        decoration: BoxDecoration(
          color: preview != null
              ? AppColors.primaryLight
              : AppColors.surfaceAlt,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
              color: preview != null
                  ? AppColors.primary
                  : AppColors.border),
        ),
        child: Row(children: [
          Icon(Icons.calculate_outlined,
              size: 18,
              color: preview != null
                  ? AppColors.primary
                  : AppColors.text2),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              preview != null
                  ? '按当前设置，月供约 ¥${preview.toStringAsFixed(2)}'
                  : '填完上面 5 项，会自动算出每月还款',
              style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: preview != null
                      ? AppColors.primary
                      : AppColors.text2),
            ),
          ),
        ]),
      ),
      const SizedBox(height: 6),
      _hintTip('当前欠款由 本金 + 已过期数 + 还款方式 自动算出，无需手填。'),
    ];
  }

  /// 实时估算月供（用第 1 期）
  double? _estimateMonthlyPayment() {
    final p = double.tryParse(_loanPrincipalCtrl.text.trim());
    final n = int.tryParse(_loanTermCtrl.text.trim());
    final r = double.tryParse(_interestRateCtrl.text.trim());
    if (p == null || p <= 0) return null;
    if (n == null || n <= 0) return null;
    if (r == null || r < 0) return null;
    if (_repaymentMethod == null) return null;
    final monthlyRate = r / 100 / 12;
    switch (_repaymentMethod) {
      case 'equal_principal':
        // 第 1 期 = P/n + P × r
        return p / n + p * monthlyRate;
      case 'interest_only':
        return p * monthlyRate;
      case 'equal_payment':
      default:
        if (monthlyRate == 0) return p / n;
        final pow = math_pow(1 + monthlyRate, n.toDouble());
        return (p * monthlyRate * pow) / (pow - 1);
    }
  }

  Widget _miniSectionHeader(String text) => Text(text,
      style: TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w600,
          color: AppColors.text1));

  Widget _label(String text) => Text(text,
      style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w500,
          color: AppColors.text2));

  Widget _dateField({
    required String label,
    required DateTime? value,
    required ValueChanged<DateTime?> onChanged,
    String? errorText,
  }) {
    final hasError = errorText != null;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _label(label),
        const SizedBox(height: 6),
        InkWell(
          onTap: () async {
            final now = DateTime.now();
            final picked = await showDatePicker(
              context: context,
              initialDate: value ?? now,
              firstDate: DateTime(now.year - 30),
              lastDate: DateTime(now.year + 50),
            );
            if (picked != null) onChanged(picked);
          },
          borderRadius: BorderRadius.circular(10),
          child: Container(
            padding: const EdgeInsets.symmetric(
                horizontal: 12, vertical: 12),
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                  color: hasError ? Colors.red : AppColors.border),
            ),
            child: Row(children: [
              Icon(Icons.calendar_today_outlined,
                  size: 16,
                  color: hasError ? Colors.red : AppColors.text2),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  value == null
                      ? '点击选择'
                      : '${value.year}-${value.month.toString().padLeft(2, '0')}-${value.day.toString().padLeft(2, '0')}',
                  style: TextStyle(
                      fontSize: 13,
                      color: value == null
                          ? (hasError ? Colors.red : AppColors.text2)
                          : AppColors.text1),
                ),
              ),
              if (value != null)
                InkWell(
                  onTap: () => onChanged(null),
                  child: Icon(Icons.close_rounded,
                      size: 16, color: AppColors.text3),
                ),
            ]),
          ),
        ),
        if (hasError) ...[
          const SizedBox(height: 4),
          Text(errorText,
              style: const TextStyle(fontSize: 12, color: Colors.red)),
        ],
      ],
    );
  }

  Widget _repaymentMethodPicker() {
    return Wrap(
      spacing: 6,
      runSpacing: 6,
      children: kRepaymentMethods.map((t) {
        final (code, label, _) = t;
        final sel = _repaymentMethod == code;
        return GestureDetector(
          onTap: () {
            setState(() => _repaymentMethod = sel ? null : code);
            _clearError('repaymentMethod');
          },
          child: Container(
            padding:
                const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: sel ? AppColors.primaryLight : AppColors.surface,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                  color: sel ? AppColors.primary : AppColors.border),
            ),
            child: Text(label,
                style: TextStyle(
                    fontSize: 12,
                    color:
                        sel ? AppColors.primary : AppColors.text1,
                    fontWeight: sel
                        ? FontWeight.w600
                        : FontWeight.normal)),
          ),
        );
      }).toList(),
    );
  }

  Widget _hintTip(String text) => Padding(
        padding: const EdgeInsets.only(top: 4),
        child: Text(text,
            style: TextStyle(
                fontSize: 11, color: AppColors.text3, height: 1.4)),
      );

  Widget _dayField({
    required String label,
    required String hint,
    required TextEditingController controller,
    String? helper,
    String? errorText,
  }) =>
      _formField(
        label: label,
        hint: hint,
        controller: controller,
        keyboardType: TextInputType.number,
        suffix: '号',
        helper: helper,
        errorText: errorText,
      );

  Widget _amountField({
    required String label,
    required String hint,
    required TextEditingController controller,
    bool allowDecimal = true,
    ValueChanged<String>? onChanged,
    String? errorText,
  }) =>
      _formField(
        label: label,
        hint: hint,
        controller: controller,
        keyboardType:
            TextInputType.numberWithOptions(decimal: allowDecimal),
        prefix: '¥ ',
        onChanged: onChanged,
        errorText: errorText,
      );

  Widget _formField({
    required String label,
    required String hint,
    required TextEditingController controller,
    TextInputType? keyboardType,
    String? prefix,
    String? suffix,
    String? helper,
    ValueChanged<String>? onChanged,
    String? errorText,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label,
            style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w500,
                color: AppColors.text2)),
        const SizedBox(height: 6),
        TextField(
          controller: controller,
          keyboardType: keyboardType,
          onChanged: onChanged,
          decoration: InputDecoration(
            hintText: hint,
            prefixText: prefix,
            suffixText: suffix,
            errorText: errorText,
            isDense: true,
            filled: true,
            fillColor: AppColors.surface,
            contentPadding: const EdgeInsets.symmetric(
                horizontal: 12, vertical: 12),
            border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: BorderSide(color: AppColors.border)),
            enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: BorderSide(color: AppColors.border)),
            focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide:
                    BorderSide(color: AppColors.primary, width: 1.5)),
            errorBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: const BorderSide(color: Colors.red)),
            focusedErrorBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: const BorderSide(color: Colors.red, width: 1.5)),
          ),
        ),
        if (helper != null && errorText == null) ...[
          const SizedBox(height: 3),
          Text(helper,
              style:
                  TextStyle(fontSize: 11, color: AppColors.text3)),
        ],
      ],
    );
  }

  /// 跟 _formField 一样但暴露 onChanged，并强制不显示 helper，
  /// 用于横向并列字段保持等高
  Widget _dayLikeField({
    required String label,
    required String hint,
    required TextEditingController controller,
    String? suffix,
    bool allowDecimal = false,
    ValueChanged<String>? onChanged,
    String? errorText,
  }) =>
      _formField(
        label: label,
        hint: hint,
        controller: controller,
        keyboardType:
            TextInputType.numberWithOptions(decimal: allowDecimal),
        suffix: suffix,
        onChanged: onChanged,
        errorText: errorText,
      );

  Future<void> _save() async {
    final newErrors = <String, String?>{};

    final name = _nameCtrl.text.trim();
    if (name.isEmpty) newErrors['name'] = '请输入账户名称';

    final balance = double.tryParse(_balanceCtrl.text) ?? 0;

    int? statementDay;
    int? dueDay;
    double? creditLimit;
    double? interestRate;
    int? autoDepositDay;
    double? autoDepositAmount;

    if (_type == 'CREDIT') {
      statementDay = _parseDay(_statementDayCtrl);
      dueDay = _parseDay(_dueDayCtrl);
      if (statementDay == null) newErrors['statementDay'] = '请输入 1-31';
      if (dueDay == null) newErrors['dueDay'] = '请输入 1-31';
      if (_creditLimitCtrl.text.trim().isNotEmpty) {
        creditLimit = _parseAmount(_creditLimitCtrl);
      }
    } else if (_type == 'DEBT') {
      final lp = double.tryParse(_loanPrincipalCtrl.text.trim());
      if (lp == null || lp <= 0) newErrors['loanPrincipal'] = '请输入贷款本金';
      final term = int.tryParse(_loanTermCtrl.text.trim());
      if (term == null || term <= 0 || term > 720) {
        newErrors['loanTerm'] = '请输入期限（月，1-720）';
      }
      dueDay = _parseDay(_dueDayCtrl);
      if (dueDay == null) newErrors['dueDay'] = '请输入 1-31';
      interestRate = double.tryParse(_interestRateCtrl.text.trim());
      if (interestRate == null || interestRate < 0 || interestRate > 100) {
        newErrors['interestRate'] = '请输入利率（0-100）';
      }
      if (_firstPaymentDate == null) newErrors['firstPaymentDate'] = '请选择首次还款日期';
      if (_repaymentMethod == null) newErrors['repaymentMethod'] = '请选择还款方式';
    } else if (_type == 'INSURANCE') {
      final hasDay = _autoDepositDayCtrl.text.trim().isNotEmpty;
      final hasAmt = _autoDepositAmountCtrl.text.trim().isNotEmpty;
      if (hasDay != hasAmt) {
        newErrors['autoDeposit'] = '入账日和入账金额请一起填，或一起留空';
      } else if (hasDay) {
        autoDepositDay = _parseDay(_autoDepositDayCtrl);
        if (autoDepositDay == null) newErrors['autoDepositDay'] = '请输入 1-31';
        autoDepositAmount = _parseAmount(_autoDepositAmountCtrl);
        if (autoDepositAmount == null || autoDepositAmount == 0) {
          newErrors['autoDepositAmount'] = '金额需大于 0';
        }
      }
    }

    if (newErrors.isNotEmpty) {
      setState(() => _errors = newErrors);
      return;
    }
    setState(() => _errors = {});

    final loanPrincipal = _type == 'DEBT' &&
            _loanPrincipalCtrl.text.trim().isNotEmpty
        ? double.tryParse(_loanPrincipalCtrl.text.trim())
        : null;
    final loanTermMonths = _type == 'DEBT' &&
            _loanTermCtrl.text.trim().isNotEmpty
        ? int.tryParse(_loanTermCtrl.text.trim())
        : null;
    final firstPaymentDateStr = _type == 'DEBT' &&
            _firstPaymentDate != null
        ? '${_firstPaymentDate!.year}-${_firstPaymentDate!.month.toString().padLeft(2, '0')}-${_firstPaymentDate!.day.toString().padLeft(2, '0')}'
        : null;
    final repaymentMethod =
        _type == 'DEBT' ? _repaymentMethod : null;

    setState(() => _saving = true);
    try {
      // 找到目标账本 id —— 编辑时用现有账户的；新建用当前账本
      final ledgerId = widget.account?.ledgerId ??
          await AuthService.getCurrentLedgerId() ?? '';
      if (ledgerId.isEmpty || !KeyChain.instance.hasDek(ledgerId)) {
        _toast('账本密钥尚未就绪，请稍后重试');
        return;
      }
      final dekVer = KeyChain.instance.dekVersionOf(ledgerId) ?? 1;
      final nameCipher = KeyChain.instance.encryptText(
        ledgerId: ledgerId,
        plain: name,
      );

      if (widget.account != null) {
        await ApiService.updateAccount(widget.account!.id, {
          'nameCipher': nameCipher,
          'nameDekVer': dekVer,
          'type': _type,
          'isShared': _isShared,
          'statementDay': statementDay,
          'dueDay': dueDay,
          'creditLimit': creditLimit,
          'interestRate': interestRate,
          'loanPrincipal': loanPrincipal,
          'loanTermMonths': loanTermMonths,
          'firstPaymentDate': firstPaymentDateStr,
          'repaymentMethod': repaymentMethod,
          'autoDepositDay': autoDepositDay,
          'autoDepositAmount': autoDepositAmount,
        });
      } else {
        await ApiService.createAccount(
          nameCipher: nameCipher,
          nameDekVer: dekVer,
          type: _type,
          initialBalance: balance,
          isShared: _isShared,
          statementDay: statementDay,
          dueDay: dueDay,
          creditLimit: creditLimit,
          interestRate: interestRate,
          loanPrincipal: loanPrincipal,
          loanTermMonths: loanTermMonths,
          firstPaymentDate: firstPaymentDateStr,
          repaymentMethod: repaymentMethod,
          autoDepositDay: autoDepositDay,
          autoDepositAmount: autoDepositAmount,
        );
      }
      if (!mounted) return;
      Navigator.pop(context);
      widget.onSaved();
    } catch (_) {
      _toast('保存失败，请重试');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  void _clearError(String key) {
    if (_errors.containsKey(key)) setState(() => _errors.remove(key));
  }

  void _toast(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg),
      behavior: SnackBarBehavior.floating,
      backgroundColor: AppColors.text1,
      shape:
          RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final maxH = MediaQuery.of(context).size.height * 0.85;
    return ConstrainedBox(
      constraints: BoxConstraints(maxHeight: maxH),
      child: Container(
        decoration: BoxDecoration(
          color: AppColors.bg,
          borderRadius:
              const BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: _step == _Step.type ? _buildTypeStep() : _buildFormStep(),
      ),
    );
  }

  /// 第 1 步：仅选类型
  Widget _buildTypeStep() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 12),
        Center(
          child: Container(
            width: 36,
            height: 4,
            decoration: BoxDecoration(
              color: AppColors.border,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
        ),
        const SizedBox(height: 14),
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 12, 0),
          child: Row(children: [
            Text('选择账户类型',
                style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: AppColors.text1)),
            const Spacer(),
            IconButton(
              onPressed: () => Navigator.pop(context),
              icon: Icon(Icons.close_rounded, color: AppColors.text2),
            ),
          ]),
        ),
        const SizedBox(height: 4),
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
          child: Text('选好后再填名称、初始余额等信息',
              style: TextStyle(fontSize: 12, color: AppColors.text2)),
        ),
        Flexible(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
            child: Column(
              children: _types.map((t) {
                final (code, emoji, label, desc) = t;
                return Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Material(
                    color: AppColors.surface,
                    borderRadius: BorderRadius.circular(12),
                    child: InkWell(
                      borderRadius: BorderRadius.circular(12),
                      onTap: () => setState(() {
                        _type = code;
                        _step = _Step.form;
                      }),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 14, vertical: 12),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: AppColors.border),
                        ),
                        child: Row(children: [
                          Container(
                            width: 38,
                            height: 38,
                            decoration: BoxDecoration(
                              color: AppColors.surfaceAlt,
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Center(
                              child: Text(emoji,
                                  style: const TextStyle(fontSize: 20)),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment:
                                  CrossAxisAlignment.start,
                              children: [
                                Text(label,
                                    style: TextStyle(
                                        fontSize: 15,
                                        fontWeight: FontWeight.w600,
                                        color: AppColors.text1)),
                                if (desc.isNotEmpty) ...[
                                  const SizedBox(height: 2),
                                  Text(desc,
                                      style: TextStyle(
                                          fontSize: 12,
                                          color: AppColors.text2)),
                                ],
                              ],
                            ),
                          ),
                          Icon(Icons.chevron_right_rounded,
                              color: AppColors.text3, size: 20),
                        ]),
                      ),
                    ),
                  ),
                );
              }).toList(),
            ),
          ),
        ),
      ],
    );
  }

  /// 第 2 步：填名称 / 可见性 / 初始余额
  Widget _buildFormStep() {
    final isEdit = widget.account != null;
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;
    final (emoji, label, desc) = _currentTypeMeta;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Handle + title
        const SizedBox(height: 12),
        Center(
          child: Container(
            width: 36,
            height: 4,
            decoration: BoxDecoration(
              color: AppColors.border,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
        ),
        const SizedBox(height: 14),
        Padding(
          padding: const EdgeInsets.fromLTRB(8, 0, 8, 0),
          child: Row(children: [
            if (!isEdit)
              IconButton(
                tooltip: '换类型',
                onPressed: () => setState(() => _step = _Step.type),
                icon: Icon(Icons.arrow_back_rounded,
                    color: AppColors.text2),
              )
            else
              const SizedBox(width: 12),
            Expanded(
              child: Text(isEdit ? '编辑账户' : '添加账户',
                  style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: AppColors.text1)),
            ),
            IconButton(
              onPressed: () => Navigator.pop(context),
              icon: Icon(Icons.close_rounded, color: AppColors.text2),
            ),
          ]),
        ),
        const SizedBox(height: 8),
        Flexible(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // 已选类型 - 紧凑 pill，点击换
                GestureDetector(
                  onTap: () => setState(() => _step = _Step.type),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 10),
                    decoration: BoxDecoration(
                      color: AppColors.primaryLight,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: AppColors.primary),
                    ),
                    child: Row(children: [
                      Text(emoji,
                          style: const TextStyle(fontSize: 20)),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment:
                              CrossAxisAlignment.start,
                          children: [
                            Text(label,
                                style: TextStyle(
                                    fontSize: 14,
                                    fontWeight: FontWeight.w600,
                                    color: AppColors.primary)),
                            if (desc.isNotEmpty)
                              Text(desc,
                                  style: TextStyle(
                                      fontSize: 11,
                                      color: AppColors.text2)),
                          ],
                        ),
                      ),
                      Text('换',
                          style: TextStyle(
                              fontSize: 12,
                              color: AppColors.primary,
                              fontWeight: FontWeight.w600)),
                      const SizedBox(width: 2),
                      Icon(Icons.swap_horiz_rounded,
                          size: 16, color: AppColors.primary),
                    ]),
                  ),
                ),
                const SizedBox(height: 16),
                // Name
                Text('账户名称',
                    style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                        color: AppColors.text2)),
                const SizedBox(height: 8),
                TextField(
                  controller: _nameCtrl,
                  autofocus: true,
                  textInputAction: TextInputAction.next,
                  onChanged: (_) => _clearError('name'),
                  decoration: InputDecoration(
                    hintText: _nameHint,
                    errorText: _errors['name'],
                    filled: true,
                    fillColor: AppColors.surface,
                    border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide:
                            BorderSide(color: AppColors.border)),
                    enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide:
                            BorderSide(color: AppColors.border)),
                    focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide(
                            color: AppColors.primary, width: 1.5)),
                    errorBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: const BorderSide(color: Colors.red)),
                    focusedErrorBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: const BorderSide(
                            color: Colors.red, width: 1.5)),
                    contentPadding: const EdgeInsets.symmetric(
                        horizontal: 14, vertical: 14),
                  ),
                ),
                const SizedBox(height: 16),
                // 可见性
                Text('可见性',
                    style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                        color: AppColors.text2)),
                const SizedBox(height: 8),
                Row(children: [
                  Expanded(
                    child: _visibilityTile(
                      icon: Icons.lock_outline_rounded,
                      title: '私人',
                      desc: '只有自己能看到和使用',
                      selected: !_isShared,
                      onTap: () => setState(() => _isShared = false),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _visibilityTile(
                      icon: Icons.group_outlined,
                      title: '共享',
                      desc: '账本所有成员可见',
                      selected: _isShared,
                      onTap: () => setState(() => _isShared = true),
                    ),
                  ),
                ]),
                // 负债账户不需要填初始余额，由"贷款本金 + 已还期数"算
                if (!isEdit && _type != 'DEBT') ...[
                  const SizedBox(height: 16),
                  Text(
                    _type == 'CREDIT'
                        ? '当前欠款（已用未还）'
                        : '初始余额',
                    style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                        color: AppColors.text2),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: _balanceCtrl,
                    keyboardType: TextInputType.numberWithOptions(
                      decimal: true,
                      signed: _type != 'CREDIT',
                    ),
                    decoration: InputDecoration(
                      hintText: _type == 'CREDIT'
                          ? '请填正数，如 5000'
                          : '0.00',
                      prefixText: '¥ ',
                      filled: true,
                      fillColor: AppColors.surface,
                      border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide:
                              BorderSide(color: AppColors.border)),
                      enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide:
                              BorderSide(color: AppColors.border)),
                      focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide(
                              color: AppColors.primary, width: 1.5)),
                      contentPadding: const EdgeInsets.symmetric(
                          horizontal: 14, vertical: 14),
                    ),
                  ),
                  if (_type == 'CREDIT') ...[
                    const SizedBox(height: 6),
                    Text(
                      '信用卡是先消费后还款的账户，欠款会自动从总资产中扣除',
                      style: TextStyle(
                          fontSize: 11, color: AppColors.text3),
                    ),
                  ],
                ],
                // ── 类型相关字段 ────────────────────────────────────
                ..._typeSpecificFields(),
              ],
            ),
          ),
        ),
        // 保存按钮
        Padding(
          padding: EdgeInsets.fromLTRB(20, 8, 20, bottomInset + 20),
          child: SizedBox(
            width: double.infinity,
            height: 50,
            child: ElevatedButton(
              onPressed: _saving ? null : _save,
              child: _saving
                  ? SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: AppColors.onPrimary))
                      : Text(isEdit ? '保存修改' : '添加账户',
                          style: const TextStyle(fontSize: 15)),
            ),
          ),
        ),
      ],
    );
  }

  Widget _visibilityTile({
    required IconData icon,
    required String title,
    required String desc,
    required bool selected,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        decoration: BoxDecoration(
          color: selected ? AppColors.primaryLight : AppColors.surface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: selected ? AppColors.primary : AppColors.border,
            width: selected ? 1.5 : 1,
          ),
        ),
        child: Row(children: [
          Icon(icon,
              size: 20,
              color: selected ? AppColors.primary : AppColors.text2),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title,
                    style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: selected
                            ? AppColors.primary
                            : AppColors.text1)),
                const SizedBox(height: 1),
                Text(desc,
                    style: TextStyle(
                        fontSize: 11, color: AppColors.text2)),
              ],
            ),
          ),
        ]),
      ),
    );
  }
}
