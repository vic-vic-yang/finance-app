import 'dart:async';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../core/refresh_bus.dart';
import '../core/theme.dart';
import '../crypto/key_chain.dart';
import '../models/bill.dart';
import '../models/account.dart';
import '../models/ledger.dart';
import '../models/insight.dart';
import '../models/proposal.dart';
import '../services/api_service.dart';
import '../services/auth_service.dart';
import '../services/pending_dek_resolver.dart';
import '../widgets/glass.dart';
import 'account_detail_screen.dart';
import 'ai_imports_screen.dart';
import 'chat_screen.dart';
import 'accounts_screen.dart';
import 'cfo_screen.dart';
import 'ledgers_screen.dart';
import 'recurring_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key, this.onSwitchTab});

  /// 由 MainScreen 注入:切换底部 tab(0=主页 1=统计 2=资讯 3=预算 4=目标)。
  /// 为空时各入口回退为 push 新页面。
  final void Function(int index)? onSwitchTab;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen>
    with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  List<Account> _accounts    = [];
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
  double _receivable = 0; // 债权：借出未收回
  double _payable = 0; // 负债：借入未还
  double _netWorth = 0; // 净资产 = 账户余额 + 债权 − 负债

  /// AI 洞察 feed
  List<AiInsight> _insights = [];

  /// CFO 复盘待处理建议数量
  int _cfoCount = 0;

  /// 是否存在 critical 级 CFO 待办（用于首页卡醒目化）
  bool _cfoHasCritical = false;

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

      // CFO 复盘建议数量：与主数据并行拉取，失败不影响首页其他数据
      final cfoFuture = ApiService.cfoProposals()
          .then((res) {
            final list = (res is List
                ? res
                : (res is Map
                    ? (res['proposals'] ?? res['data'] ?? const [])
                    : const [])) as List;
            return list
                .map((e) => Proposal.fromJson(e as Map<String, dynamic>))
                .toList();
          })
          .catchError((_) => <Proposal>[]);

      final results = await Future.wait([
        ApiService.getAccounts(),
        ApiService.getStats(startDate: start, endDate: end),
        ApiService.getLedgers(),
        // AI 洞察：实时算，失败不应影响首页其他数据
        ApiService.aiInsights().catchError(
          (_) => <String, dynamic>{'insights': []},
        ),
      ]);

      final cfoProps = await cfoFuture;

      if (!mounted) return;
      final ledgers = (results[2]['ledgers'] as List? ?? [])
          .map((l) => Ledger.fromJson(l as Map<String, dynamic>))
          .toList();
      final currentId = results[2]['currentLedgerId'] as String?;
      setState(() {
        _accounts = (results[0]['accounts'] as List? ?? [])
            .map((a) => Account.fromJson(a as Map<String, dynamic>)).toList();
        final sum = (results[1]['summary'] as Map?) ?? {};
        _income  = (sum['totalIncome']  as num?)?.toDouble() ?? 0;
        _expense = (sum['totalExpense'] as num?)?.toDouble() ?? 0;
        final asset = (results[1]['assetSummary'] as Map?) ?? {};
        _familyTotal = (asset['total']  as num?)?.toDouble() ?? 0;
        _othersTotal = (asset['others'] as num?)?.toDouble() ?? 0;
        _receivable  = (asset['receivable'] as num?)?.toDouble() ?? 0;
        _payable     = (asset['payable']    as num?)?.toDouble() ?? 0;
        _netWorth    = (asset['netWorth']   as num?)?.toDouble() ?? _familyTotal;
        _insights = (results[3]['insights'] as List? ?? [])
            .map((i) => AiInsight.fromJson(i as Map<String, dynamic>)).toList();
        _cfoCount = cfoProps.length;
        _cfoHasCritical = cfoProps.any((p) => p.severity == 'critical');
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
              // 有借贷往来时显示「净资产」拆解（含债权/负债），修正借出后资产缩水
              SliverToBoxAdapter(child: _netWorthCard()),
              // AI 管家：CFO 复盘 + 洞察合成一条流（都为空时整块不显示）
              if (_insights.isNotEmpty || _cfoCount > 0) ...[
                _sectionTitleWithAction(
                  '🤖 AI 管家',
                  '查看全部',
                  _showAllInsightsSheet,
                ),
                SliverToBoxAdapter(child: _insightsList()),
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
      // 头像点击切到底部「我的」tab（ProfileScreen 现在是 tab）
      avatarTap: () => widget.onSwitchTab?.call(3),
      actions: [
        if (_currentLedger != null && _currentLedger!.id.isNotEmpty)
          AiButton(
            tooltip: '导入流水',
            icon: Icons.file_upload_outlined,
            onTap: () async {
              await Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const AiImportsScreen()),
              );
              if (mounted) _load();
            },
          ),
        if (_currentLedger != null && _currentLedger!.id.isNotEmpty)
          const SizedBox(width: 10),
        if (_currentLedger != null && _currentLedger!.id.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(right: 16),
            child: AiButton(
              tooltip: '司库助手',
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

  // ── AI 管家流（CFO 复盘条 + 洞察卡） ─────────────────────
  Widget _insightsList() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
      child: Column(
        children: [
          if (_cfoCount > 0) _cfoStrip(),
          for (final ins in _insights.take(4)) _insightCard(ins),
          if (_insights.length > 4)
            GestureDetector(
              onTap: _showAllInsightsSheet,
              behavior: HitTestBehavior.opaque,
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      '查看其余 ${_insights.length - 4} 条',
                      style: TextStyle(
                          fontSize: 12.5,
                          color: AppColors.primary,
                          fontWeight: FontWeight.w600),
                    ),
                    Icon(Icons.keyboard_arrow_down_rounded,
                        size: 18, color: AppColors.primary),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }

  void _showAllInsightsSheet() {
    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.surface,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => StatefulBuilder(
        builder: (ctx, setSheet) => DraggableScrollableSheet(
          expand: false,
          initialChildSize: 0.7,
          maxChildSize: 0.92,
          minChildSize: 0.4,
          builder: (_, controller) => Column(
            children: [
              const SizedBox(height: 10),
              Container(
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                  color: AppColors.border,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 14, 20, 8),
                child: Row(
                  children: [
                    const Text('🤖 AI 管家',
                        style: TextStyle(
                            fontSize: 16, fontWeight: FontWeight.w700)),
                    const Spacer(),
                    Text('${_insights.length} 条',
                        style:
                            TextStyle(fontSize: 12, color: AppColors.text3)),
                  ],
                ),
              ),
              Expanded(
                child: _insights.isEmpty && _cfoCount == 0
                    ? Center(
                        child: Text('暂无洞察',
                            style: TextStyle(color: AppColors.text3)))
                    : ListView(
                        controller: controller,
                        padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
                        children: [
                          if (_cfoCount > 0) _cfoStrip(),
                          for (final ins in _insights)
                            _insightCard(ins,
                                onChanged: () => setSheet(() {})),
                        ],
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// 标题里的 emoji 前缀（🔴🟡…）去掉——严重度改用左侧色条表达，画面更安静
  String _cleanTitle(String t) =>
      t.replaceFirst(RegExp(r'^[\u{1F300}-\u{1FAFF}\u{2600}-\u{27BF}\u{FE0F}]+\s*', unicode: true), '');

  Color _severityColor(String severity) {
    switch (severity) {
      case 'critical':
        return AppColors.income; // 哑红
      case 'warning':
        return AppColors.warning; // 琥珀
      default:
        return AppColors.primary;
    }
  }

  Widget _insightCard(AiInsight ins, {VoidCallback? onChanged}) {
    final accent = _severityColor(ins.severity);
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.border),
      ),
      clipBehavior: Clip.antiAlias,
      child: IntrinsicHeight(
        child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // 左侧严重度色条：代替刺眼的整卡彩底
          Container(width: 3, color: accent),
          const SizedBox(width: 11),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    _cleanTitle(ins.title),
                    style: TextStyle(
                      fontSize: 13.5,
                      fontWeight: FontWeight.w600,
                      color: AppColors.text1,
                    ),
                  ),
                  if (ins.body.isNotEmpty) ...[
                    const SizedBox(height: 3),
                    Text(
                      ins.body,
                      style: TextStyle(
                          fontSize: 12, color: AppColors.text2, height: 1.35),
                    ),
                  ],
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      for (final a in ins.actions) ...[
                        _insightChip(a.label,
                            onTap: () => _handleInsightAction(ins, a)),
                        const SizedBox(width: 8),
                      ],
                      // 每条洞察都能一键抛给司库助手追问
                      _insightChip('问 AI',
                          icon: Icons.auto_awesome_rounded,
                          onTap: () => _askAiAboutInsight(ins)),
                    ],
                  ),
                ],
              ),
            ),
          ),
          GestureDetector(
            onTap: () {
              _dismissInsight(ins);
              onChanged?.call();
            },
            behavior: HitTestBehavior.opaque,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(10, 12, 12, 0),
              child: Icon(Icons.close_rounded,
                  size: 15, color: AppColors.text3),
            ),
          ),
        ],
        ),
      ),
    );
  }

  /// 洞察卡上的迷你操作（ghost chip）：主题色描边小胶囊，克制不喧宾
  Widget _insightChip(String label, {IconData? icon, VoidCallback? onTap}) =>
      GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: AppColors.primary.withOpacity(0.45)),
          ),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            if (icon != null) ...[
              Icon(icon, size: 11, color: AppColors.primary),
              const SizedBox(width: 4),
            ],
            Text(label,
                style: TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w600,
                    color: AppColors.primary)),
          ]),
        ),
      );

  /// 把一条洞察抛给司库助手追问（进入对话页并自动发出问题）
  Future<void> _askAiAboutInsight(AiInsight ins) async {
    final l = _currentLedger;
    if (l == null || l.id.isEmpty) return;
    final q = ins.body.isEmpty
        ? '帮我看看这条提醒：${ins.title}。是什么情况，我该怎么处理？'
        : '帮我看看这条提醒：${ins.title}（${ins.body}）。是什么情况，我该怎么处理？';
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ChatScreen(ledgerId: l.id, initialPrompt: q),
      ),
    );
    if (mounted) _load();
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
      return;
    }
    if (a.intent == 'openAccount') {
      // 信用卡还款提醒 → 跳账户详情（还款/校准都在里面）
      final accountId = (a.params?['accountId'] ?? '') as String;
      if (accountId.isEmpty) return;
      await Navigator.push(
        context,
        MaterialPageRoute(
            builder: (_) => AccountDetailScreen(accountId: accountId)),
      );
      if (mounted) _load();
    }
  }

  /// 打开记一笔，返回后刷新首页
  Future<void> _openAdd() async {
    final result = await Navigator.pushNamed(context, '/add');
    if (result == true && mounted) _load();
  }

  /// 净资产拆解卡：仅当有借贷往来（债权/负债）时显示。
  /// 净资产 = 可动用（账户余额）+ 债权（借出未收）− 负债（借入未还）。
  Widget _netWorthCard() {
    if (_receivable <= 0.009 && _payable <= 0.009) {
      return const SizedBox.shrink();
    }
    Widget row(String label, String value, {Color? color}) => Padding(
          padding: const EdgeInsets.only(top: 6),
          child: Row(children: [
            Text(label, style: TextStyle(fontSize: 12, color: AppColors.text3)),
            const Spacer(),
            Text(value,
                style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w600,
                    color: color ?? AppColors.text2)),
          ]),
        );
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 10, 20, 0),
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
            Text('净资产', style: TextStyle(fontSize: 12, color: AppColors.text2)),
            const SizedBox(height: 3),
            Text(fmtMoney(_netWorth),
                style: TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                    letterSpacing: -0.5,
                    color: AppColors.text1)),
            const Divider(height: 18),
            row('可动用（账户）', fmtMoney(_familyTotal)),
            if (_receivable > 0.009)
              row('债权（借出）', '+${fmtMoney(_receivable)}',
                  color: AppColors.income),
            if (_payable > 0.009)
              row('负债（借入）', '-${fmtMoney(_payable)}',
                  color: AppColors.expense),
          ],
        ),
      ),
    );
  }

  Widget _summaryCard() {
    final now     = DateTime.now();
    final balance = _income - _expense;
    final fg      = AppColors.onPrimaryGradient;
    return Container(
      margin: const EdgeInsets.only(top: 6, bottom: 4),
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: AppColors.primaryGradient,
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(18),
        boxShadow: AppTheme.ambientShadow(
          opacity: 0.18,
          blur: 30,
          offset: const Offset(0, 12),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Expanded(
              child: Text('${now.year}年${now.month}月结余',
                  style: TextStyle(color: fg.withOpacity(0.7), fontSize: 12)),
            ),
            // 记一笔入口
            _recordButton(fg),
          ]),
          const SizedBox(height: 4),
          Text(fmtMoney(balance),
              style: TextStyle(
                  color: fg, fontSize: 28,
                  fontWeight: FontWeight.bold, letterSpacing: -0.8)),
          const SizedBox(height: 12),
          Row(children: [
            Expanded(child: _summaryItem('收入', _income)),
            Container(width: 1, height: 28, color: fg.withOpacity(0.2)),
            Expanded(child: _summaryItem('支出', _expense)),
          ]),
        ],
      ),
    );
  }

  /// 结余卡上的「记一笔」按钮（半透明胶囊，落在渐变上）
  Widget _recordButton(Color fg) {
    return Material(
      color: fg.withOpacity(0.18),
      borderRadius: BorderRadius.circular(20),
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: _openAdd,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Icon(Icons.add_rounded, size: 17, color: fg),
            const SizedBox(width: 4),
            Text('记一笔',
                style: TextStyle(
                    color: fg, fontSize: 13, fontWeight: FontWeight.w600)),
          ]),
        ),
      ),
    );
  }

  Widget _summaryItem(String label, double amt) {
    final fg = AppColors.onPrimaryGradient;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: TextStyle(color: fg.withOpacity(0.7), fontSize: 11.5)),
          const SizedBox(height: 3),
          Text(fmtMoney(amt),
              style: TextStyle(
                  color: fg, fontSize: 15, fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }

  /// CFO 复盘条：并入 AI 管家流的第一条（同洞察卡语言：surface + 左色条）
  Widget _cfoStrip() {
    final accent =
        _cfoHasCritical ? AppColors.income : AppColors.primary;
    return GestureDetector(
      onTap: () async {
        await Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const CfoScreen()),
        );
        if (mounted) _load();
      },
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppColors.border),
        ),
        clipBehavior: Clip.antiAlias,
        child: IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Container(width: 3, color: accent),
              const SizedBox(width: 11),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  child: Row(children: [
                    Icon(Icons.fact_check_outlined,
                        size: 16, color: accent),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        _cfoHasCritical
                            ? 'CFO 复盘：$_cfoCount 件需要注意'
                            : 'CFO 复盘：$_cfoCount 条建议待处理',
                        style: TextStyle(
                            fontSize: 13.5,
                            fontWeight: FontWeight.w600,
                            color: AppColors.text1),
                      ),
                    ),
                  ]),
                ),
              ),
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: Center(
                  child: Icon(Icons.chevron_right_rounded,
                      size: 18, color: AppColors.text3),
                ),
              ),
            ],
          ),
        ),
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
