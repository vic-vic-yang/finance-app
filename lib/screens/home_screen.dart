import 'dart:async';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../core/refresh_bus.dart';
import '../core/theme.dart';
import '../crypto/key_chain.dart';
import '../models/bill.dart';
import '../models/account.dart';
import '../models/budget.dart';
import '../models/ledger.dart';
import '../models/insight.dart';
import '../services/api_service.dart';
import '../services/auth_service.dart';
import '../services/pending_dek_resolver.dart';
import '../widgets/glass.dart';
import 'account_detail_screen.dart';
import 'chat_screen.dart';
import 'accounts_screen.dart';
import 'bills_screen.dart';
import 'budgets_screen.dart';
import 'ledgers_screen.dart';
import 'profile_screen.dart';
import 'recurring_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});
  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen>
    with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  List<Account> _accounts    = [];
  List<Bill>    _recentBills  = [];
  List<Budget>  _budgets      = [];
  List<Ledger>  _ledgers      = [];
  Ledger?       _currentLedger;
  double _income  = 0;
  double _expense = 0;
  bool   _loading = true;
  String _username = '';
  String? _nickname;

  /// 问候用：昵称优先，否则用户名
  String get _greetName {
    final n = (_nickname ?? '').trim();
    if (n.isNotEmpty) return n;
    return _username;
  }

  /// 资产 tab：0=我的, 1=共享, 2=全部
  int _assetTab = 0;

  /// 家庭资产（含其他成员私人账户的总和）
  double _familyTotal = 0;
  double _othersTotal = 0;

  /// AI 洞察 feed
  List<AiInsight> _insights = [];

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
    final user = await AuthService.getUser();
    if (mounted) {
      setState(() {
        _username = user?['username'] ?? '';
        _nickname = user?['nickname'] as String?;
      });
    }
    try {
      final now   = DateTime.now();
      final start = '${now.year}-${now.month.toString().padLeft(2, '0')}-01';
      final last  = DateTime(now.year, now.month + 1, 0).day;
      final end   = '${now.year}-${now.month.toString().padLeft(2, '0')}-${last.toString().padLeft(2, '0')}';

      final results = await Future.wait([
        ApiService.getAccounts(),
        ApiService.getBills(limit: 8),
        ApiService.getStats(startDate: start, endDate: end),
        ApiService.getBudgets(),
        ApiService.getLedgers(),
        // AI 洞察：实时算，失败不应影响首页其他数据
        ApiService.aiInsights().catchError(
          (_) => <String, dynamic>{'insights': []},
        ),
      ]);

      if (!mounted) return;
      final ledgers = (results[4]['ledgers'] as List? ?? [])
          .map((l) => Ledger.fromJson(l as Map<String, dynamic>))
          .toList();
      final currentId = results[4]['currentLedgerId'] as String?;
      setState(() {
        _accounts = (results[0]['accounts'] as List? ?? [])
            .map((a) => Account.fromJson(a as Map<String, dynamic>)).toList();
        _recentBills = (results[1]['bills'] as List? ?? [])
            .map((b) => Bill.fromJson(b as Map<String, dynamic>)).toList();
        final sum = (results[2]['summary'] as Map?) ?? {};
        _income  = (sum['totalIncome']  as num?)?.toDouble() ?? 0;
        _expense = (sum['totalExpense'] as num?)?.toDouble() ?? 0;
        final asset = (results[2]['assetSummary'] as Map?) ?? {};
        _familyTotal = (asset['total']  as num?)?.toDouble() ?? 0;
        _othersTotal = (asset['others'] as num?)?.toDouble() ?? 0;
        _budgets = (results[3]['budgets'] as List? ?? [])
            .map((b) => Budget.fromJson(b as Map<String, dynamic>)).toList();
        _insights = (results[5]['insights'] as List? ?? [])
            .map((i) => AiInsight.fromJson(i as Map<String, dynamic>)).toList();
        _ledgers = ledgers;
        _currentLedger = ledgers.firstWhere(
          (l) => l.id == currentId,
          orElse: () => ledgers.isNotEmpty
              ? ledgers.first
              : Ledger(
                  id: '', name: '我的账本',
                  isPersonal: true, ownerId: '', ownerName: '',
                  role: 'owner', memberCount: 1, billCount: 0),
        );
        _loading = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: RefreshIndicator(
        color: AppColors.primary,
        onRefresh: _load,
        child: CustomScrollView(
          slivers: [
            _appBar(),
            if (_loading)
              SliverFillRemaining(
                child: Center(child: CircularProgressIndicator(color: AppColors.primary)),
              )
            else ...[
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(20, 4, 20, 0),
                sliver: SliverToBoxAdapter(child: _summaryCard()),
              ),
              if (_insights.isNotEmpty) ...[
                _sectionTitleWithAction(
                  '🤖 AI 洞察',
                  '订阅管家',
                  () async {
                    await Navigator.push(
                      context,
                      MaterialPageRoute(builder: (_) => const RecurringScreen()),
                    );
                    if (mounted) _load();
                  },
                ),
                SliverToBoxAdapter(child: _insightsList()),
              ],
              if (_hasAnyBudget) ...[
                _sectionTitleWithAction(
                  _shownBudgetPeriod == 'YEARLY' ? '本年预算' : '本月预算',
                  '管理',
                  () => Navigator.push(
                    context,
                    MaterialPageRoute(
                        builder: (_) => const BudgetsScreen()),
                  ),
                ),
                SliverToBoxAdapter(child: _budgetTotalCard()),
              ],
              if (_accounts.isNotEmpty) ...[
                _sectionTitleWithAction(
                  '我的账户',
                  '管理',
                  () => Navigator.push(
                    context,
                    MaterialPageRoute(
                        builder: (_) => const AccountsScreen()),
                  ),
                ),
                SliverToBoxAdapter(child: _accountsList()),
              ] else
                SliverToBoxAdapter(child: _noAccount()),
              if (_recentBills.isEmpty)
                ...[
                  _sectionTitle('最近账单'),
                  SliverToBoxAdapter(child: _emptyBills()),
                ]
              else ...[
                _sectionTitleWithAction(
                  '最近账单',
                  '全部',
                  () => Navigator.push(
                    context,
                    MaterialPageRoute(
                        builder: (_) => const BillsScreen()),
                  ),
                ),
                SliverList(
                  delegate: SliverChildBuilderDelegate(
                    (_, i) => _BillRow(
                      bill: _recentBills[i],
                      showRecorder:
                          _currentLedger != null && _currentLedger!.isShared,
                    ),
                    childCount: _recentBills.length,
                  ),
                ),
              ],
              const SliverToBoxAdapter(child: SizedBox(height: 100)),
            ],
          ],
        ),
      ),
    );
  }

  Widget _appBar() {
    final h = DateTime.now().hour;
    final greeting = h < 12 ? '早上好' : h < 18 ? '下午好' : '晚上好';
    final l = _currentLedger;
    return AuraSliverAppBar(
      avatarTap: () => Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => const ProfileScreen()),
      ),
      actions: [
        if (_currentLedger != null && _currentLedger!.id.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(right: 16),
            child: AiButton(
              tooltip: '财记助手',
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => ChatScreen(ledgerId: _currentLedger!.id),
                ),
              ),
            ),
          ),
      ],
      titleWidget: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          // 账本切换器
          GestureDetector(
            onTap: _showLedgerSwitcher,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(l?.displayIcon ?? '💰',
                    style: const TextStyle(fontSize: 18)),
                const SizedBox(width: 6),
                Flexible(
                  child: Text(
                    l?.name ?? '我的账本',
                    style: TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.bold,
                      color: AppColors.text1,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const SizedBox(width: 2),
                if (l != null && l.isShared)
                  Container(
                    margin: const EdgeInsets.only(left: 4),
                    padding: const EdgeInsets.symmetric(
                        horizontal: 5, vertical: 1),
                    decoration: BoxDecoration(
                      color: AppColors.primaryLight,
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      '${l.memberCount}人',
                      style: TextStyle(
                        fontSize: 10,
                        color: AppColors.primary,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                Icon(Icons.keyboard_arrow_down_rounded,
                    size: 22, color: AppColors.text2),
              ],
            ),
          ),
          const SizedBox(height: 2),
          Text(
            '$greeting，$_greetName 👋  ·  ${DateFormat('M月d日').format(DateTime.now())}',
            style: TextStyle(fontSize: 12, color: AppColors.text2),
          ),
        ],
      ),
    );
  }

  /// 弹出账本快速切换 bottom sheet
  Future<void> _showLedgerSwitcher() async {
    await showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (_) => _LedgerSwitcherSheet(
        ledgers: _ledgers,
        currentId: _currentLedger?.id,
        onSwitched: (l) async {
          try {
            await ApiService.switchLedger(l.id);
            final user = await AuthService.getUser() ?? {};
            user['currentLedgerId'] = l.id;
            await AuthService.saveUser(user);
            // 切到的账本若无 DEK（如新加入还在 pending），先尝试 rehydrate；
            // 同时机会式给该账本其他 pending 成员补 wrap
            if (!KeyChain.instance.hasDek(l.id)) {
              await PendingDekResolver.rehydrate(requireLedgerId: l.id);
            }
            unawaited(PendingDekResolver.resolveOne(l.id));
            bumpRefresh();
          } catch (_) {}
        },
        onManage: () async {
          await Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const LedgersScreen()),
          );
          if (mounted) _load();
        },
      ),
    );
  }

  // ── AI 洞察列表 ──────────────────────────────────────────
  Widget _insightsList() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
      child: Column(
        children: [
          for (final ins in _insights.take(4)) _insightCard(ins),
          if (_insights.length > 4)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                '还有 ${_insights.length - 4} 条…',
                style: TextStyle(fontSize: 12, color: AppColors.text2),
              ),
            ),
        ],
      ),
    );
  }

  Widget _insightCard(AiInsight ins) {
    Color borderColor;
    Color bgColor;
    switch (ins.severity) {
      case 'critical':
        borderColor = Colors.red.shade300;
        bgColor = Colors.red.shade50;
        break;
      case 'warning':
        borderColor = Colors.orange.shade300;
        bgColor = Colors.orange.shade50;
        break;
      default:
        borderColor = Colors.blue.shade200;
        bgColor = Colors.blue.shade50;
    }
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.fromLTRB(14, 12, 6, 12),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: borderColor, width: 0.6),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  ins.title,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                if (ins.body.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(
                    ins.body,
                    style: TextStyle(fontSize: 12.5, color: AppColors.text2),
                  ),
                ],
                if (ins.actions.isNotEmpty) ...[
                  const SizedBox(height: 6),
                  Wrap(
                    spacing: 6,
                    children: [
                      for (final a in ins.actions)
                        TextButton(
                          onPressed: () => _handleInsightAction(ins, a),
                          style: TextButton.styleFrom(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 2,
                            ),
                            minimumSize: Size.zero,
                            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                          ),
                          child: Text(a.label),
                        ),
                    ],
                  ),
                ],
              ],
            ),
          ),
          IconButton(
            tooltip: '忽略',
            icon: Icon(Icons.close, size: 18, color: AppColors.text2),
            onPressed: () => _dismissInsight(ins),
          ),
        ],
      ),
    );
  }

  Future<void> _dismissInsight(AiInsight ins) async {
    setState(() => _insights.remove(ins));
    try {
      await ApiService.aiDismissInsight(type: ins.type, target: ins.target);
    } catch (_) {
      // 失败也不还原，下次刷新会再出
    }
  }

  Future<void> _handleInsightAction(AiInsight ins, InsightAction a) async {
    if (a.intent == 'createBillFromRecurring' ||
        ins.type == 'recurring_due') {
      // 跳到周期账单页让用户处理
      await Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => const RecurringScreen()),
      );
      if (mounted) _load();
    }
  }

  Widget _summaryCard() {
    final now     = DateTime.now();
    final balance = _income - _expense;
    final fg      = AppColors.onPrimaryGradient;
    return Container(
      margin: const EdgeInsets.only(top: 8, bottom: 4),
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: AppColors.primaryGradient,
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(20),
        boxShadow: AppTheme.ambientShadow(
          opacity: 0.18,
          blur: 36,
          offset: const Offset(0, 16),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('${now.year}年${now.month}月结余',
              style: TextStyle(color: fg.withOpacity(0.7), fontSize: 13)),
          const SizedBox(height: 6),
          Text(fmtMoney(balance),
              style: TextStyle(
                  color: fg, fontSize: 34,
                  fontWeight: FontWeight.bold, letterSpacing: -1)),
          const SizedBox(height: 18),
          Row(children: [
            Expanded(child: _summaryItem('收入', _income)),
            Container(width: 1, height: 36, color: fg.withOpacity(0.2)),
            Expanded(child: _summaryItem('支出', _expense)),
          ]),
        ],
      ),
    );
  }

  Widget _summaryItem(String label, double amt) {
    final fg = AppColors.onPrimaryGradient;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: TextStyle(color: fg.withOpacity(0.7), fontSize: 12)),
          const SizedBox(height: 4),
          Text(fmtMoney(amt),
              style: TextStyle(
                  color: fg, fontSize: 16, fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }

  Widget _accountsList() {
    final mine   = _accounts.where((a) => !a.isShared).toList();
    final shared = _accounts.where((a) => a.isShared).toList();
    final hasShared = shared.isNotEmpty;
    final hasOthers = _othersTotal.abs() > 0.01;

    // 多人账本（共享账户 或 别人有私人账户）才显示 tab 切换
    final showTabs = (hasShared || hasOthers) &&
        _currentLedger != null &&
        _currentLedger!.memberCount > 1;

    // 当前 tab 下展示的"我可见"账户列表
    List<Account> visibleList;
    if (!showTabs) {
      visibleList = _accounts;
    } else if (_assetTab == 0) {
      visibleList = mine;
    } else if (_assetTab == 1) {
      visibleList = shared;
    } else {
      visibleList = _accounts; // "全部" tab: 仍然只能展示自己可见的，其他成员合并成占位卡
    }

    // 标题数字：
    // - "全部" tab → 家庭总额（含别人私人）
    // - 其他 → 当前 list 之和
    final headerTotal = (showTabs && _assetTab == 2)
        ? _familyTotal
        : visibleList.fold<double>(0.0, (s, a) => s + a.balance);

    final showOthersCard = showTabs && _assetTab == 2 && hasOthers;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: EdgeInsets.fromLTRB(20, 0, 20, showTabs ? 8 : 10),
          child: Row(children: [
            Text(showTabs ? _assetLabel() : '总资产  ',
                style: TextStyle(color: AppColors.text2, fontSize: 13)),
            const SizedBox(width: 4),
            Text(fmtMoney(headerTotal),
                style: TextStyle(
                    color: AppColors.text1,
                    fontSize: 13,
                    fontWeight: FontWeight.w600)),
          ]),
        ),
        if (showTabs)
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 10),
            child: _assetTabs(mine.length, shared.length, _accounts.length),
          ),
        SizedBox(
          height: 100,
          child: ListView.separated(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            scrollDirection: Axis.horizontal,
            itemCount: visibleList.length + (showOthersCard ? 1 : 0),
            separatorBuilder: (_, __) => const SizedBox(width: 12),
            itemBuilder: (_, i) {
              if (i < visibleList.length) {
                return _AccountCard(account: visibleList[i]);
              }
              // 占位卡：其他成员的私人账户总和（不暴露具体账户）
              return _OthersAccountCard(total: _othersTotal);
            },
          ),
        ),
      ],
    );
  }

  String _assetLabel() {
    if (_assetTab == 0) return '我的资产  ';
    if (_assetTab == 1) return '共享资产  ';
    return '家庭总资产  ';
  }

  Widget _assetTabs(int mineCount, int sharedCount, int allCount) {
    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: AppColors.surfaceAlt,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(children: [
        _assetTabItem(0, '我的', mineCount),
        _assetTabItem(1, '共享', sharedCount),
        _assetTabItem(2, '全部', allCount),
      ]),
    );
  }

  Widget _assetTabItem(int idx, String label, int count) {
    final sel = _assetTab == idx;
    return Expanded(
      child: GestureDetector(
        onTap: () => setState(() => _assetTab = idx),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 7),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: sel ? AppColors.surface : Colors.transparent,
            borderRadius: BorderRadius.circular(8),
            boxShadow: sel
                ? [
                    BoxShadow(
                        color: Colors.black.withOpacity(0.06),
                        blurRadius: 4,
                        offset: const Offset(0, 1))
                  ]
                : null,
          ),
          child: Text('$label · $count',
              style: TextStyle(
                  fontSize: 12,
                  fontWeight: sel ? FontWeight.w600 : FontWeight.w500,
                  color: sel ? AppColors.text1 : AppColors.text2)),
        ),
      ),
    );
  }

  Widget _noAccount() => Padding(
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
        child: GestureDetector(
          onTap: () => Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const AccountsScreen()),
          ),
          child: Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
                color: AppColors.primaryLight,
                borderRadius: BorderRadius.circular(14)),
            child: Row(children: [
              Icon(Icons.add_circle_outline_rounded,
                  color: AppColors.primary),
              SizedBox(width: 10),
              Expanded(
                child: Text('点这里添加第一个账户',
                    style: TextStyle(
                        color: AppColors.primary,
                        fontWeight: FontWeight.w500)),
              ),
              Icon(Icons.chevron_right_rounded,
                  color: AppColors.primary),
            ]),
          ),
        ),
      );

  Widget _emptyBills() => Padding(
        padding: EdgeInsets.symmetric(vertical: 40),
        child: Column(children: [
          Text('🧾', style: TextStyle(fontSize: 40)),
          SizedBox(height: 10),
          Text('还没有账单，点 + 开始记账',
              style: TextStyle(color: AppColors.text2, fontSize: 14)),
        ]),
      );

  SliverToBoxAdapter _sectionTitle(String t) => SliverToBoxAdapter(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 10),
          child: Text(t,
              style: TextStyle(
                  fontSize: 15, fontWeight: FontWeight.w600, color: AppColors.text1)),
        ),
      );

  SliverToBoxAdapter _sectionTitleWithAction(
          String t, String actionText, VoidCallback onTap) =>
      SliverToBoxAdapter(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 10),
          child: Row(children: [
            Text(t,
                style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: AppColors.text1)),
            const Spacer(),
            GestureDetector(
              onTap: onTap,
              child: Row(children: [
                Text(actionText,
                    style: TextStyle(
                        fontSize: 13, color: AppColors.primary)),
                Icon(Icons.chevron_right_rounded,
                    size: 16, color: AppColors.primary),
              ]),
            ),
          ]),
        ),
      );

  // ── 预算汇总（点进 BudgetsScreen）──
  // 优先显示月度；若月度完全为空但年度有，回退到年度

  List<Budget> _categoryBudgetsOf(String period) => _budgets
      .where((b) => b.period == period && b.categoryId != null)
      .toList();

  Budget? _manualTotalOf(String period) {
    for (final b in _budgets) {
      if (b.period == period && b.categoryId == null) return b;
    }
    return null;
  }

  bool _hasBudgetOf(String period) =>
      _manualTotalOf(period) != null ||
      _categoryBudgetsOf(period).isNotEmpty;

  /// 卡片实际显示的周期：有月度优先月度，否则年度，再否则 null
  String? get _shownBudgetPeriod {
    if (_hasBudgetOf('MONTHLY')) return 'MONTHLY';
    if (_hasBudgetOf('YEARLY')) return 'YEARLY';
    return null;
  }

  /// 是否有任何预算（手填总预算 或 分类预算）
  bool get _hasAnyBudget => _shownBudgetPeriod != null;

  /// 首页只显示这一个卡片，点击进 BudgetsScreen
  Widget _budgetTotalCard() {
    final period = _shownBudgetPeriod ?? 'MONTHLY';
    final isYearly = period == 'YEARLY';
    final cats = _categoryBudgetsOf(period);
    final manualTarget = _manualTotalOf(period)?.amount ?? 0.0;
    final sumCats = cats.fold<double>(0.0, (s, b) => s + b.amount);
    final total = sumCats > manualTarget ? sumCats : manualTarget;
    final spent = cats.fold<double>(0.0, (s, b) => s + b.spent);
    final remaining = total - spent;
    final progress = total > 0 ? spent / total : 0.0;
    final over = spent > total && total > 0;
    final color = over
        ? AppColors.expense
        : (progress > 0.8 ? AppColors.warning : AppColors.primary);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: GlassCard(
        radius: 16,
        padding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const BudgetsScreen()),
        ),
        child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(children: [
                  Container(
                    width: 34,
                    height: 34,
                    decoration: BoxDecoration(
                      color: color.withOpacity(0.12),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Center(
                      child: Text('💼',
                          style: const TextStyle(fontSize: 17)),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(isYearly ? '年度预算' : '月度预算',
                            style: TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w600,
                                color: AppColors.text1)),
                        const SizedBox(height: 1),
                        Text(
                          cats.isEmpty
                              ? '只设了总预算上限'
                              : '${cats.length} 个分类预算',
                          style: TextStyle(
                              fontSize: 11, color: AppColors.text3),
                        ),
                      ],
                    ),
                  ),
                  Text(
                    '${(progress * 100).toStringAsFixed(0)}%',
                    style: TextStyle(
                        fontSize: 14,
                        color: color,
                        fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(width: 6),
                  Icon(Icons.chevron_right_rounded,
                      color: AppColors.text3, size: 18),
                ]),
                const SizedBox(height: 10),
                ClipRRect(
                  borderRadius: BorderRadius.circular(3),
                  child: LinearProgressIndicator(
                    value: progress.clamp(0.0, 1.0),
                    minHeight: 6,
                    backgroundColor: color.withOpacity(0.10),
                    valueColor: AlwaysStoppedAnimation<Color>(color),
                  ),
                ),
                const SizedBox(height: 8),
                Row(children: [
                  Text(
                    '已用 ${fmtMoneyInt(spent)}',
                    style: TextStyle(
                        fontSize: 12,
                        color: color,
                        fontWeight: FontWeight.w600),
                  ),
                  Text(' / ${fmtMoneyInt(total)}',
                      style: TextStyle(
                          fontSize: 12, color: AppColors.text3)),
                  const Spacer(),
                  Text(
                    over
                        ? '超支 ${fmtMoneyInt(-remaining)}'
                        : '剩 ${fmtMoneyInt(remaining)}',
                    style: TextStyle(
                      fontSize: 12,
                      color: over
                          ? AppColors.expense
                          : AppColors.text2,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ]),
              ],
            ),
      ),
    );
  }
}

// ── 账户卡片 ──────────────────────────────────────────────────
class _AccountCard extends StatelessWidget {
  const _AccountCard({required this.account});
  final Account account;
  @override
  Widget build(BuildContext context) => Material(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: () => Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) =>
                  AccountDetailScreen(accountId: account.id),
            ),
          ),
          child: Container(
            width: 148,
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: AppColors.border),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(children: [
                  Text(account.typeEmoji,
                      style: const TextStyle(fontSize: 18)),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(account.name,
                        style: TextStyle(
                            fontSize: 12,
                            color: AppColors.text2,
                            fontWeight: FontWeight.w500),
                        overflow: TextOverflow.ellipsis),
                  ),
                ]),
                Text(fmtMoney(account.balance),
                    style: TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.bold,
                        color: AppColors.text1,
                        letterSpacing: -0.5)),
              ],
            ),
          ),
        ),
      );
}

/// 占位卡：聚合显示其他成员的私人账户总额（不暴露具体账户）
class _OthersAccountCard extends StatelessWidget {
  const _OthersAccountCard({required this.total});
  final double total;
  @override
  Widget build(BuildContext context) => Container(
        width: 148,
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: AppColors.surfaceAlt,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppColors.border),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Row(children: [
              const Text('👥', style: TextStyle(fontSize: 18)),
              const SizedBox(width: 6),
              Expanded(
                child: Text('其他成员',
                    style: TextStyle(
                        fontSize: 12,
                        color: AppColors.text2,
                        fontWeight: FontWeight.w500),
                    overflow: TextOverflow.ellipsis),
              ),
            ]),
            Text(fmtMoney(total),
                style: TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.bold,
                    color: AppColors.text1,
                    letterSpacing: -0.5)),
          ],
        ),
      );
}

// ── 账单行 ────────────────────────────────────────────────────
class _BillRow extends StatelessWidget {
  const _BillRow({required this.bill, this.showRecorder = false});
  final Bill bill;
  final bool showRecorder;
  @override
  Widget build(BuildContext context) => Container(
        margin: const EdgeInsets.fromLTRB(20, 0, 20, 8),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppColors.border),
        ),
        child: Row(children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: bill.isIncome ? AppColors.incomeLight : AppColors.expenseLight,
              borderRadius: BorderRadius.circular(11),
            ),
            child: Center(
              child: Text(bill.category.icon ?? (bill.isIncome ? '💰' : '💸'),
                  style: const TextStyle(fontSize: 19)),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Flexible(
                  child: Text(bill.category.name,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w500,
                          color: AppColors.text1)),
                ),
                if (showRecorder && bill.recorderName != null) ...[
                  const SizedBox(width: 6),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
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
              const SizedBox(height: 2),
              Text(bill.account.nameOf(bill.ledgerId),
                  style: TextStyle(fontSize: 12, color: AppColors.text2)),
            ]),
          ),
          Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
            Text(bill.amountText,
                style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: bill.isIncome ? AppColors.income : AppColors.expense)),
            const SizedBox(height: 2),
            Text(DateFormat('MM/dd').format(bill.date),
                style: TextStyle(fontSize: 11, color: AppColors.text2)),
          ]),
        ]),
      );
}

// ── 账本快速切换 sheet ──────────────────────────────────────
class _LedgerSwitcherSheet extends StatelessWidget {
  const _LedgerSwitcherSheet({
    required this.ledgers,
    required this.currentId,
    required this.onSwitched,
    required this.onManage,
  });
  final List<Ledger> ledgers;
  final String? currentId;
  final void Function(Ledger) onSwitched;
  final VoidCallback onManage;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.bg,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      ),
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 28),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
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
          const SizedBox(height: 16),
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 4),
            child: Text('切换账本',
                style: TextStyle(
                    fontSize: 16, fontWeight: FontWeight.bold)),
          ),
          const SizedBox(height: 12),
          ConstrainedBox(
            constraints: BoxConstraints(
              maxHeight: MediaQuery.of(context).size.height * 0.5,
            ),
            child: ListView.builder(
              shrinkWrap: true,
              itemCount: ledgers.length,
              itemBuilder: (_, i) {
                final l = ledgers[i];
                final isCurrent = l.id == currentId;
                return Container(
                  margin: const EdgeInsets.only(bottom: 8),
                  decoration: BoxDecoration(
                    color: isCurrent
                        ? AppColors.primaryLight
                        : AppColors.surface,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: isCurrent
                          ? AppColors.primary
                          : AppColors.border,
                      width: isCurrent ? 1.5 : 1,
                    ),
                  ),
                  child: ListTile(
                    onTap: () {
                      Navigator.pop(context);
                      if (!isCurrent) onSwitched(l);
                    },
                    leading: Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        color: AppColors.surfaceAlt,
                        borderRadius: BorderRadius.circular(11),
                      ),
                      child: Center(
                        child: Text(l.displayIcon,
                            style: const TextStyle(fontSize: 20)),
                      ),
                    ),
                    title: Row(children: [
                      Flexible(
                        child: Text(
                          l.name,
                          style: TextStyle(
                              fontSize: 15, fontWeight: FontWeight.w600,
                              color: AppColors.text1),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      if (l.isShared) ...[
                        const SizedBox(width: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 5, vertical: 1),
                          decoration: BoxDecoration(
                            color: AppColors.primary,
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            '${l.memberCount}人',
                            style: TextStyle(
                              fontSize: 10,
                              color: AppColors.onPrimary,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ],
                    ]),
                    subtitle: Text(
                      [
                        if (l.isPersonal) '个人账本',
                        if (!l.isPersonal && l.isOwner) '我创建的',
                        if (!l.isPersonal && !l.isOwner)
                          '${l.ownerDisplayName} 创建',
                        '${l.billCount} 笔账',
                      ].join(' · '),
                      style: TextStyle(
                          fontSize: 12, color: AppColors.text2),
                    ),
                    trailing: isCurrent
                        ? Icon(Icons.check_circle_rounded,
                            color: AppColors.primary, size: 22)
                        : Icon(Icons.chevron_right_rounded,
                            color: AppColors.text2),
                  ),
                );
              },
            ),
          ),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            onPressed: () {
              Navigator.pop(context);
              onManage();
            },
            icon: Icon(Icons.settings_outlined,
                size: 18, color: AppColors.primary),
            label: Text('账本管理 · 新建 / 邀请 / 加入',
                style: TextStyle(color: AppColors.primary)),
            style: OutlinedButton.styleFrom(
              minimumSize: const Size(double.infinity, 46),
              side: BorderSide(color: AppColors.primary),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12)),
            ),
          ),
        ],
      ),
    );
  }
}
