import 'dart:async';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../core/refresh_bus.dart';
import '../core/motion.dart';
import '../core/theme.dart';
import '../crypto/key_chain.dart';
import '../models/bill.dart';
import '../models/account.dart';
import '../models/ledger.dart';
import '../models/insight.dart';
import '../models/proposal.dart';
import '../models/reconcile_report.dart';
import '../services/api_service.dart';
import '../services/auth_service.dart';
import '../services/discovery_triggers.dart';
import '../services/feature_discovery_service.dart';
import '../services/forecast_service.dart';
import '../services/merchant_analytics.dart';
import '../services/notification_service.dart';
import '../services/pending_dek_resolver.dart';
import '../widgets/chart_kit.dart';
import '../widgets/entrance.dart';
import '../widgets/feature_discovery_card.dart';
import '../widgets/siku_ui.dart';
import 'account_detail_screen.dart';
import 'chat_screen.dart';
import 'accounts_screen.dart';
import 'cfo_screen.dart';
import 'forecast_screen.dart';
import 'ledgers_screen.dart';
import 'notifications_screen.dart';
import 'recurring_screen.dart';
import 'smart_hub_screen.dart';

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

  /// 当月日终总资产序列（全局口径：与 assetSummary.total 同源，
  /// 后端以 familyTotal 为终点倒推，含其他成员聚合值但不泄露明细）。
  /// 取自 getStats 响应已有的 assetTrend 字段，无新增网络请求；
  /// hero 结余卡内净资产趋势 Sparkline 的数据源。
  List<double> _assetTrend = [];

  /// AI 洞察 feed
  List<AiInsight> _insights = [];

  /// CFO 复盘待处理建议数量
  int _cfoCount = 0;

  /// 通知中心未读数（铃铛角标；0 不显示）
  int _unreadCount = 0;

  /// 现金流预测：月末净资产预测值（静默拉取，失败为 null → 入口行不显示）
  double? _monthEndProjected;

  /// 是否存在 critical 级 CFO 待办（用于首页卡醒目化）
  bool _cfoHasCritical = false;

  /// 卡片 stagger 入场「只播一次」标志（State 生命周期内）：
  /// 首个内容帧渲染后置 true，之后 refreshBus / 下拉刷新重建时
  /// Entrance 以 play=false 直接呈现终态，不再重播。
  bool _entrancePlayed = false;

  /// hero 净资产大数字 count-up「只播一次」标志
  bool _heroCounted = false;

  /// hero 资产趋势 sparkline 首次描绘动画「只播一次」标志
  /// （与 count-up 同款 State 生命周期标志位模式）
  bool _trendDrawn = false;

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

  /// 首个内容帧后置「入场已播」标志。无需 setState：本帧 Entrance 已开演，
  /// 此后重建读到的新值自然生效。
  void _markEntrancePlayed() {
    if (_entrancePlayed) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _entrancePlayed = true;
    });
  }

  /// 包一层入场动画（fade + 上移 12px，stagger 40ms，只播一次）。
  /// 系统「减弱动效」时 Entrance 内部直接呈现终态。
  Widget _entrance(int index, Widget child) =>
      Entrance(index: index, play: !_entrancePlayed, child: child);

  /// hero 净资产大数字：首次拿到数据从 0 count-up（[Motion.emphasis] 600ms /
  /// easeOutExpo），只播一次；之后刷新直接显示新值。
  /// 系统「减弱动效」时直接显示目标值。
  Widget _heroAmount(double netWorth, Color fg) {
    if (_heroCounted || Motion.reduced(context)) {
      return AmountText(netWorth, size: AmountSize.hero, color: fg);
    }
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: netWorth),
      duration: Motion.emphasis,
      curve: Motion.emphasized,
      onEnd: () {
        if (mounted) setState(() => _heroCounted = true);
      },
      builder: (_, v, __) => AmountText(v, size: AmountSize.hero, color: fg),
    );
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
        _assetTrend = ((results[1]['assetTrend'] as List?) ?? [])
            .map((p) => ((p as Map)['balance'] as num?)?.toDouble() ?? 0.0)
            .toList();
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
    // 铃铛未读数 / 现金流预测：静默拉取，失败不影响首页其他数据
    _loadUnreadCount();
    _loadForecast();
    // 时机式功能发现：数据就绪后静默评估（内部已 try/catch，不阻塞首屏）
    unawaited(_evaluateDiscovery());
  }

  /// 时机式功能发现（每个场景一生只提示一次，静默失败）：
  ///   ① 连续记账 ≥7 天        → 推荐现金流预测
  ///   ② 近 30 天同一商户 ≥3 笔 → 推荐周期账单识别
  /// 两个场景都展示过后直接短路，不再多拉账单；一次最多出一张卡。
  Future<void> _evaluateDiscovery() async {
    final fd = FeatureDiscoveryService.instance;
    final streakShown =
        await fd.isShown(FeatureDiscoveryService.kStreakForecast);
    final merchantShown =
        await fd.isShown(FeatureDiscoveryService.kMerchantRecurring);
    if (streakShown && merchantShown) return;
    try {
      final now = DateTime.now();
      final start = now.subtract(const Duration(days: 30));
      final startStr =
          '${start.year}-${start.month.toString().padLeft(2, '0')}-${start.day.toString().padLeft(2, '0')}';
      // 现有 /bills 接口拉近 30 天账单（上限 200 条），streak 与同商户
      // 两个判断共用这一次请求，不为发现功能新增后端接口
      final res = await ApiService.getBills(limit: 200, startDate: startStr);
      final bills = (res['bills'] as List? ?? [])
          .whereType<Map<String, dynamic>>()
          .map(Bill.fromJson)
          .toList();
      if (!mounted) return;

      // ① 连续记账 7 天 → 现金流预测
      if (!streakShown &&
          bookkeepingStreak(bills.map((b) => b.date), now) >= 7) {
        final shown = await fd.maybeShow(
          context,
          FeatureDiscoveryService.kStreakForecast,
          const FeatureDiscoveryCardData(
            emoji: '📈',
            title: '已连续记账 7 天，试试现金流预测',
            message: '按当前节奏推算月末结余，超支早知道',
          ),
          onGo: () => Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const ForecastScreen()),
          ),
        );
        if (shown) return; // 一次只出一张卡，另一个场景下次再评
      }

      // ② 近 30 天同一商户 ≥3 笔 → 周期账单识别（备注明文本机解密，不出设备）
      if (!merchantShown) {
        final ledgerId = _currentLedger?.id ?? '';
        final entries = <({String merchant, DateTime date})>[
          for (final b in bills)
            if (b.type == 'expense' && !b.isTransfer && b.source != 'stock')
              (
                merchant: extractMerchant(
                  ReconcileItem.noteOf(ledgerId, b.noteCipher, b.noteDekVer),
                ),
                date: b.date,
              ),
        ];
        final hit = frequentMerchant(entries, now: now);
        if (hit != null && mounted) {
          await fd.maybeShow(
            context,
            FeatureDiscoveryService.kMerchantRecurring,
            FeatureDiscoveryCardData(
              emoji: '🔁',
              title: '「${hit.merchant}」近 30 天出现了 ${hit.count} 次',
              message: '周期账单能盯住这类固定支出，到期前提醒你',
            ),
            onGo: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const RecurringScreen()),
            ),
          );
        }
      }
    } catch (_) {/* 静默：发现失败不影响首页 */}
  }

  /// 通知未读数（角标数据源）。失败时保持原值，不清角标。
  Future<void> _loadUnreadCount() async {
    try {
      final res = await NotificationService.unreadCount();
      if (!mounted) return;
      setState(() => _unreadCount = (res['count'] as num?)?.toInt() ?? 0);
    } catch (_) {}
  }

  /// 月末结余预测（结余卡下方小字链接）。失败 → null，入口行不显示。
  Future<void> _loadForecast() async {
    try {
      final f = await ForecastService.getForecast();
      if (!mounted) return;
      setState(() => _monthEndProjected = f.monthEnd.projected);
    } catch (_) {
      if (mounted) setState(() => _monthEndProjected = null);
    }
  }

  /// 打开通知中心；返回后刷新角标
  Future<void> _openNotifications() async {
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const NotificationsScreen()),
    );
    if (mounted) _loadUnreadCount();
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final slivers = <Widget>[_appBar()];
    if (_loading) {
      slivers.add(SliverFillRemaining(
        child: Center(
            child: CircularProgressIndicator(color: AppColors.primary)),
      ));
    } else {
      // 首个内容帧后置「入场已播」标志：refreshBus / 下拉刷新重建时不再重播
      _markEntrancePlayed();
      var order = 0;
      slivers.add(SliverPadding(
        padding: const EdgeInsets.fromLTRB(20, 4, 20, 0),
        sliver: SliverToBoxAdapter(
          child: _entrance(
            order++,
            Column(
              children: [
                _summaryCard(),
                // 现金流预测入口：静默拉取，失败不显示
                if (_monthEndProjected != null) _forecastLink(),
              ],
            ),
          ),
        ),
      ));
      // 我的账户紧跟结余卡（净资产拆解已整合进统计页）
      if (_accounts.isNotEmpty) {
        slivers.add(_sectionTitleWithAction(
          '我的账户',
          '管理',
          () => Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const AccountsScreen()),
          ),
          entranceIndex: order++,
        ));
        slivers.add(
            SliverToBoxAdapter(child: _entrance(order++, _accountsList())));
      } else {
        slivers.add(
            SliverToBoxAdapter(child: _entrance(order++, _noAccount())));
      }
      // AI 管家：CFO 复盘 + 洞察合成一条流（都为空时整块不显示）
      if (_insights.isNotEmpty || _cfoCount > 0) {
        slivers.add(_sectionTitleWithAction(
          '🤖 AI 管家',
          '全部',
          () => Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const SmartHubScreen()),
          ),
          entranceIndex: order++,
        ));
        slivers.add(
            SliverToBoxAdapter(child: _entrance(order++, _insightsList())));
      }
      slivers.add(const SliverToBoxAdapter(child: SizedBox(height: 100)));
    }
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: RefreshIndicator(
        color: AppColors.primary,
        onRefresh: _load,
        child: CustomScrollView(slivers: slivers),
      ),
    );
  }

  Widget _appBar() {
    final h = DateTime.now().hour;
    final greeting = h < 12 ? '早上好' : h < 18 ? '下午好' : '晚上好';
    final l = _currentLedger;
    return AuraSliverAppBar(
      actions: [
        // 通知中心铃铛（未读小红点角标）+ 司库助手（裸 icon，命中区放大）
        Padding(
          padding: const EdgeInsets.only(right: 4),
          child: GestureDetector(
            onTap: _openNotifications,
            behavior: HitTestBehavior.opaque,
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Stack(clipBehavior: Clip.none, children: [
                Icon(Icons.notifications_outlined,
                    size: 22, color: AppColors.text1),
                if (_unreadCount > 0)
                  Positioned(
                    right: -2,
                    top: -2,
                    child: Container(
                      width: 8,
                      height: 8,
                      decoration: BoxDecoration(
                        color: AppColors.danger,
                        shape: BoxShape.circle,
                      ),
                    ),
                  ),
              ]),
            ),
          ),
        ),
        if (_currentLedger != null && _currentLedger!.id.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: GestureDetector(
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => ChatScreen(ledgerId: _currentLedger!.id),
                ),
              ),
              behavior: HitTestBehavior.opaque,
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Icon(Icons.auto_awesome_rounded,
                    size: 22, color: AppColors.text1),
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
          // 只展示前 4 条，更多的从流底部入口进弹层看
          for (final ins in _insights.take(4)) _insightCard(ins),
          if (_insights.length > 4)
            GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: _showAllInsightsSheet,
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text('查看全部 ${_insights.length} 条洞察',
                        style:
                            TextStyle(fontSize: 12, color: AppColors.text3)),
                    Icon(Icons.chevron_right_rounded,
                        size: 14, color: AppColors.text3),
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
      // Stack + 左侧贴边色条：高度完全跟随内容，杜绝 IntrinsicHeight 的像素溢出
      child: Stack(
        children: [
          Positioned(
              left: 0, top: 0, bottom: 0,
              child: Container(width: 3, color: accent)),
          Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(width: 14),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
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
        ],
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
            border: Border.all(color: AppColors.primary.withValues(alpha: 0.45)),
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

  /// hero 卡「三位一体」同口径布局：
  ///   大数字 = 净资产存量（assetSummary.total，getStats 全局口径：
  ///   我的 + 共享 + 其他成员聚合，一次计算，不随账户区 tab 联动）
  ///   趋势   = assetTrend（后端以同一 total 为终点倒推，与数字严格同口径）
  ///   底部行 = 本月收入 / 支出（流量指标，与存量各司其职）
  Widget _summaryCard() {
    final netWorth = _familyTotal;
    final fg       = AppColors.onPrimaryGradient;
    return Container(
      margin: const EdgeInsets.only(top: 6, bottom: 4),
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 18),
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
          // 记一笔已移到底部导航中央「+」
          Text('净资产',
              style: TextStyle(color: fg.withValues(alpha: 0.7), fontSize: 12)),
          const SizedBox(height: 4),
          _heroAmount(netWorth, fg),
          // 净资产趋势 sparkline：与上方大数字同口径（assetTrend 终点即
          // assetSummary.total），数据取自已有的 getStats 响应，无新增请求。
          // 数据不足（< 2 点）时整条隐藏，上下间距自然回落、布局不塌陷。
          if (_assetTrend.length >= 2) ...[
            const SizedBox(height: 12),
            _heroSparkline(fg),
          ],
          const SizedBox(height: 12),
          Row(children: [
            Expanded(child: _summaryItem('本月收入', _income)),
            Container(width: 1, height: 28, color: fg.withValues(alpha: 0.2)),
            Expanded(child: _summaryItem('本月支出', _expense)),
          ]),
        ],
      ),
    );
  }

  /// hero 卡内净资产趋势 sparkline：颜色用 `onPrimaryGradient`（渐变卡上
  /// 不能用 primary 绿，会看不见），fill 同色 10% → 0 渐隐；宽度经
  /// LayoutBuilder 撑满卡内可用宽。首次拿到数据按 [Motion.emphasis]
  /// 描绘一次（progress 0→1，只播一次，与 count-up 同款标志位模式）；
  /// 系统「减弱动效」时直接呈现完整线条。
  Widget _heroSparkline(Color fg) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final w = constraints.maxWidth;
        if (_trendDrawn || Motion.reduced(context)) {
          return Sparkline(
            values: _assetTrend,
            height: 44,
            width: w,
            color: fg,
            fillOpacity: 0.10,
          );
        }
        return TweenAnimationBuilder<double>(
          tween: Tween(begin: 0, end: 1),
          duration: Motion.emphasis,
          curve: Motion.emphasized,
          onEnd: () {
            if (mounted) setState(() => _trendDrawn = true);
          },
          builder: (_, p, __) => Sparkline(
            values: _assetTrend,
            height: 44,
            width: w,
            color: fg,
            fillOpacity: 0.10,
            progress: p,
          ),
        );
      },
    );
  }

  Widget _summaryItem(String label, double amt) {
    final fg = AppColors.onPrimaryGradient;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: TextStyle(color: fg.withValues(alpha: 0.7), fontSize: 11.5)),
          const SizedBox(height: 3),
          AmountText(amt, size: AmountSize.card, color: fg),
        ],
      ),
    );
  }

  /// 结余卡下方：月末结余预测小字链接（数据静默拉取，失败不显示这行）
  Widget _forecastLink() {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => const ForecastScreen()),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(4, 2, 4, 4),
        child: Row(children: [
          Text('预计月末结余 ',
              style: TextStyle(fontSize: 12, color: AppColors.text2)),
          Text(fmtMoney(_monthEndProjected!),
              style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: AppColors.text2)),
          Text(' · 查看预测',
              style: TextStyle(fontSize: 12, color: AppColors.text2)),
          Icon(Icons.chevron_right_rounded,
              size: 14, color: AppColors.primary),
        ]),
      ),
    );
  }

  /// AI 管家区标题右侧：智能管家聚合页入口（克制的小字链接）
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
        child: Stack(
          children: [
            Positioned(
                left: 0, top: 0, bottom: 0,
                child: Container(width: 3, color: accent)),
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 12, 8, 12),
              child: Row(children: [
                Icon(Icons.fact_check_outlined, size: 16, color: accent),
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
                Icon(Icons.chevron_right_rounded,
                    size: 18, color: AppColors.text3),
              ]),
            ),
          ],
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

    // 合计金额已上移到 hero 卡「净资产」（全局口径），此处标题行只保留
    // 口径标签（我的 / 共享 / 家庭）+ 当前口径合计小字，避免一屏两个大数字；
    // 右侧入口由外层 section 标题的「我的账户 · 管理」承担。
    final showOthersCard = showTabs && _assetTab == 2 && hasOthers;
    final tabTotal = visibleList.fold<double>(0, (s, a) => s + a.balance) +
        (showOthersCard ? _othersTotal : 0);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: EdgeInsets.fromLTRB(20, 0, 20, showTabs ? 8 : 10),
          child: Row(children: [
            Text(showTabs ? _assetLabel() : '总资产',
                style: TextStyle(color: AppColors.text2, fontSize: 13)),
            const SizedBox(width: 8),
            Text(fmtMoney(tabTotal),
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
    if (_assetTab == 0) return '我的资产';
    if (_assetTab == 1) return '共享资产';
    return '家庭总资产';
  }

  Widget _assetTabs(int mineCount, int sharedCount, int allCount) {
    return AuraSegmented<int>(
      variant: AuraSegmentedVariant.float,
      options: [
        (value: 0, label: '我的 · $mineCount'),
        (value: 1, label: '共享 · $sharedCount'),
        (value: 2, label: '全部 · $allCount'),
      ],
      selected: _assetTab,
      onChanged: (i) => setState(() => _assetTab = i),
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
    String t,
    String actionText,
    VoidCallback onTap, {
    Widget? trailing,
    int? entranceIndex,
  }) {
    final child = SectionHeader(
      title: t,
      actionLabel: actionText,
      onTap: onTap,
      trailing: trailing,
      top: 20,
      bottom: 10,
    );
    return SliverToBoxAdapter(
      child: entranceIndex == null ? child : _entrance(entranceIndex, child),
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
