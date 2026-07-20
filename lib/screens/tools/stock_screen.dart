import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:intl/intl.dart';
import '../../core/theme.dart';
import '../../widgets/siku_ui.dart';
import '../../services/api_service.dart';
import 'stock_detail_screen.dart';

/// 我的持仓：只展示自己持有的股票，自动算市值/盈亏、每日结算进净资产。
class StockScreen extends StatefulWidget {
  const StockScreen({super.key});

  @override
  State<StockScreen> createState() => _StockScreenState();
}

class _StockScreenState extends State<StockScreen> {
  List<Map<String, dynamic>> _list = [];
  List<Map<String, dynamic>> _pnlDaily = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  List<Map<String, dynamic>> get _holdings =>
      _list.where((s) => s['held'] == true).toList();

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final res = await ApiService.getStocks();
      if (!mounted) return;
      setState(() {
        _list = res.map((e) => (e as Map).cast<String, dynamic>()).toList();
        _loading = false;
      });
      // 每日盈亏曲线（best-effort，不阻塞列表）
      ApiService.getHoldingPnlDaily(days: 30).then((pnl) {
        if (!mounted) return;
        setState(() => _pnlDaily =
            pnl.map((e) => (e as Map).cast<String, dynamic>()).toList());
      }).catchError((_) {});
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _openDetail({String? symbol, String? query, String? title}) async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => StockDetailScreen(
          symbol: symbol,
          query: query,
          title: title,
        ),
      ),
    );
    if (mounted) _load(); // 返回后刷新列表（新查询/更新会改动）
  }

  Future<void> _search() async {
    final q = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (_) => const _SearchSheet(),
    );
    if (q != null && q.trim().isNotEmpty) {
      _openDetail(query: q.trim(), title: q.trim());
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: AuraAppBar(
        title: '我的持仓',
        actions: [
          HeaderAddButton(tooltip: '添加持仓', onPressed: _search),
        ],
      ),
      body: AuraBackground(
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : _tabList(_holdings, holding: true),
      ),
    );
  }

  Widget _tabList(List<Map<String, dynamic>> list, {required bool holding}) {
    return RefreshIndicator(
      color: AppColors.primary,
      onRefresh: _load,
      child: list.isEmpty
          ? _empty(holding: holding)
          : ListView.builder(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 90),
              itemCount: list.length + (holding ? 1 : 0),
              itemBuilder: (_, i) {
                if (holding && i == 0) return _portfolioSummary(list);
                final idx = holding ? i - 1 : i;
                return _row(list[idx], holding: holding);
              },
            ),
    );
  }

  Widget _empty({required bool holding}) => ListView(
        children: const [
          EmptyState(
            emoji: '💼',
            title: '还没有持仓',
            hint: '点右上 + 添加持仓，填买入价和数量，市值和每日盈亏都会自动算。',
          ),
        ],
      );

  Widget _row(Map<String, dynamic> s, {bool holding = false}) {
    final name = ((s['nameZh'] ?? '').toString().trim().isNotEmpty)
        ? s['nameZh'].toString()
        : (s['name'] ?? s['symbol']).toString();
    final price = (s['price'] is num) ? (s['price'] as num).toDouble() : null;
    final chgPct =
        (s['changePercent'] is num) ? (s['changePercent'] as num).toDouble() : null;
    final up = (chgPct ?? 0) >= 0;
    final color = up ? AppColors.income : AppColors.expense;
    final cur = (s['currency'] ?? '').toString();
    return GlassCard(
      margin: const EdgeInsets.only(bottom: 10),
      radius: 16,
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      onTap: () => _openDetail(
          symbol: (s['symbol'] ?? '').toString(), title: name),
      child: Row(children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(children: [
                Flexible(
                  child: Text(name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                          color: AppColors.text1)),
                ),
                const SizedBox(width: 6),
                Text('${s['symbol']}',
                    style: TextStyle(fontSize: 11, color: AppColors.text3)),
                if ((s['rating'] ?? '').toString().isNotEmpty) ...[
                  const SizedBox(width: 6),
                  _ratingChip(s['rating'].toString()),
                ],
              ]),
              const SizedBox(height: 3),
              if (holding)
                _holdingLine(s, price)
              else
                Text('更新于 ${_fmtTime((s['updatedAt'] ?? '').toString())}',
                    style: TextStyle(fontSize: 11.5, color: AppColors.text3)),
            ],
          ),
        ),
        const SizedBox(width: 10),
        Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text(price == null ? '—' : price.toStringAsFixed(3),
                style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: AppColors.text1)),
            const SizedBox(height: 2),
            Text(
              chgPct == null
                  ? (cur.isEmpty ? '' : cur)
                  : '${up ? '+' : ''}${chgPct.toStringAsFixed(2)}%',
              style: TextStyle(
                  fontSize: 12.5, fontWeight: FontWeight.w600, color: color),
            ),
          ],
        ),
        const SizedBox(width: 6),
        Icon(Icons.chevron_right_rounded, color: AppColors.text3),
      ]),
    );
  }

  /// 持仓总览：今日总盈亏 + 总市值/成本/总盈亏（客户端按实时价聚合所有持仓）
  /// 持仓收益口径说人话
  void _showPnlExplain() {
    Widget bullet(String title, String desc) => Padding(
          padding: const EdgeInsets.only(bottom: 13),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title,
                  style: TextStyle(
                      fontSize: 13.5,
                      fontWeight: FontWeight.w700,
                      color: AppColors.text1)),
              const SizedBox(height: 3),
              Text(desc,
                  style: TextStyle(
                      fontSize: 12, color: AppColors.text2, height: 1.45)),
            ],
          ),
        );
    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => Padding(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 28),
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
            Text('持仓收益怎么算',
                style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: AppColors.text1)),
            const SizedBox(height: 16),
            bullet('今日盈亏', '按最新价，今日每股涨跌 × 持股数（和券商「今日」口径一致）。'),
            bullet('总盈亏', '（现价 − 成本价）× 持股数。'),
            bullet('自动结算', '每个交易日 15:30 收盘后自动把当日盈亏记进关联账户，账户余额 ≈ 最新市值、计入净资产。'),
            bullet('和券商对不上？',
                '多半是分红 / 除权：除权日价格会跌掉派息，但你拿到了现金，而价差口径不含分红。可到账户详情用「校准余额」按券商实际市值修正。'),
          ],
        ),
      ),
    );
  }

  Widget _portfolioSummary(List<Map<String, dynamic>> holdings) {
    double cost = 0, mv = 0, todayPnl = 0;
    bool hasToday = false;
    int counted = 0;
    for (final s in holdings) {
      final bp = (s['buyPrice'] is num) ? (s['buyPrice'] as num).toDouble() : null;
      final sh = (s['shares'] is num) ? (s['shares'] as num).toDouble() : null;
      final pr = (s['price'] is num) ? (s['price'] as num).toDouble() : null;
      if (bp == null || sh == null || pr == null || bp <= 0 || sh <= 0) continue;
      counted++;
      cost += bp * sh;
      mv += pr * sh;
      final ch = (s['change'] is num) ? (s['change'] as num).toDouble() : null;
      if (ch != null) {
        todayPnl += ch * sh;
        hasToday = true;
      }
    }
    if (cost <= 0) return const SizedBox.shrink();
    final pl = mv - cost;
    final plPct = cost > 0 ? pl / cost * 100 : 0.0;
    final todayColor = todayPnl >= 0 ? AppColors.income : AppColors.expense;
    final plColor = pl >= 0 ? AppColors.income : AppColors.expense;

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
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
            Text('今日盈亏',
                style: TextStyle(fontSize: 12, color: AppColors.text2)),
            const SizedBox(width: 5),
            GestureDetector(
              onTap: _showPnlExplain,
              behavior: HitTestBehavior.opaque,
              child: Icon(Icons.help_outline_rounded,
                  size: 14, color: AppColors.text3),
            ),
            const Spacer(),
            Text('$counted 只持仓',
                style: TextStyle(fontSize: 11, color: AppColors.text3)),
          ]),
          const SizedBox(height: 3),
          Text(
            hasToday
                ? '${todayPnl >= 0 ? '+' : ''}¥${todayPnl.toStringAsFixed(2)}'
                : '— 待更新',
            style: TextStyle(
                fontSize: 26,
                fontWeight: FontWeight.bold,
                letterSpacing: -0.5,
                color: hasToday ? todayColor : AppColors.text3),
          ),
          const Divider(height: 20),
          Row(children: [
            Expanded(child: _sumKv('总市值', '¥${_money0(mv)}')),
            Expanded(child: _sumKv('持仓成本', '¥${_money0(cost)}')),
            Expanded(
              child: _sumKv(
                '总盈亏',
                '${pl >= 0 ? '+' : ''}¥${_money0(pl)}',
                sub: '${pl >= 0 ? '+' : ''}${plPct.toStringAsFixed(1)}%',
                color: plColor,
              ),
            ),
          ]),
          _pnlChart(),
          const SizedBox(height: 12),
          // AI 持仓解读：只做数据解读+风险提示（不含操作建议，合规安全线）
          GestureDetector(
            onTap: _showAiInsight,
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 9),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(20),
                border:
                    Border.all(color: AppColors.primary.withValues(alpha: 0.45)),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.auto_awesome_rounded,
                      size: 14, color: AppColors.primary),
                  const SizedBox(width: 6),
                  Text('AI 持仓解读',
                      style: TextStyle(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w600,
                          color: AppColors.primary)),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// AI 持仓解读弹层：markdown 渲染 + 免责声明
  void _showAiInsight() {
    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.surface,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.62,
        maxChildSize: 0.9,
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
              padding: const EdgeInsets.fromLTRB(20, 14, 20, 4),
              child: Row(children: [
                Icon(Icons.auto_awesome_rounded,
                    size: 16, color: AppColors.primary),
                const SizedBox(width: 8),
                Text('AI 持仓解读',
                    style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: AppColors.text1)),
              ]),
            ),
            Expanded(
              child: FutureBuilder<Map<String, dynamic>>(
                future: ApiService.getHoldingsInsight(),
                builder: (_, snap) {
                  if (snap.connectionState != ConnectionState.done) {
                    return const Center(child: CircularProgressIndicator());
                  }
                  if (snap.hasError) {
                    return Center(
                      child: Padding(
                        padding: const EdgeInsets.all(24),
                        child: Text('生成失败：${snap.error}',
                            style: TextStyle(
                                fontSize: 13, color: AppColors.text2)),
                      ),
                    );
                  }
                  final text = (snap.data?['text'] as String?) ?? '';
                  return ListView(
                    controller: controller,
                    padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
                    children: [
                      MarkdownBody(
                        data: text,
                        selectable: true,
                        styleSheet: MarkdownStyleSheet(
                          p: TextStyle(
                              fontSize: 13.5,
                              height: 1.6,
                              color: AppColors.text1),
                          strong: const TextStyle(fontWeight: FontWeight.w700),
                          listBullet: TextStyle(
                              fontSize: 13.5, color: AppColors.text1),
                          em: TextStyle(
                              fontSize: 11.5,
                              fontStyle: FontStyle.italic,
                              color: AppColors.text3),
                        ),
                      ),
                    ],
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// 组合每日总盈亏曲线（柱状：盈=红，亏=绿，与全局金额配色一致）
  Widget _pnlChart() {
    final data = _pnlDaily
        .where((e) => e['pnl'] is num)
        .toList(); // [{date, pnl}]，按日升序
    if (data.length < 2) return const SizedBox.shrink();
    final vals = data.map((e) => (e['pnl'] as num).toDouble()).toList();
    final maxV =
        vals.map((v) => v.abs()).fold<double>(0, (a, b) => a > b ? a : b);
    if (maxV <= 0) return const SizedBox.shrink();

    final groups = <BarChartGroupData>[];
    for (var i = 0; i < vals.length; i++) {
      final v = vals[i];
      groups.add(BarChartGroupData(x: i, barRods: [
        BarChartRodData(
          toY: v == 0 ? maxV * 0.005 : v,
          width: vals.length > 22 ? 5 : 7,
          borderRadius: BorderRadius.circular(2),
          color: v >= 0 ? AppColors.income : AppColors.expense,
        ),
      ]));
    }
    final first = data.first['date']?.toString() ?? '';
    final last = data.last['date']?.toString() ?? '';
    String mmdd(String d) => d.length >= 10 ? d.substring(5) : d;

    return Padding(
      padding: const EdgeInsets.only(top: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Text('每日盈亏',
                style: TextStyle(fontSize: 11, color: AppColors.text3)),
            const Spacer(),
            Text('${mmdd(first)} ~ ${mmdd(last)}',
                style: TextStyle(fontSize: 10.5, color: AppColors.text3)),
          ]),
          const SizedBox(height: 10),
          SizedBox(
            height: 78,
            child: BarChart(BarChartData(
              alignment: BarChartAlignment.spaceBetween,
              maxY: maxV * 1.18,
              minY: -maxV * 1.18,
              barGroups: groups,
              gridData: const FlGridData(show: false),
              borderData: FlBorderData(show: false),
              titlesData: const FlTitlesData(show: false),
              barTouchData: BarTouchData(enabled: false),
              extraLinesData: ExtraLinesData(horizontalLines: [
                HorizontalLine(
                  y: 0,
                  color: AppColors.border,
                  strokeWidth: 1,
                ),
              ]),
            )),
          ),
        ],
      ),
    );
  }

  String _money0(double v) => v.abs() >= 10000
      ? '${(v / 10000).toStringAsFixed(2)}万'
      : v.toStringAsFixed(0);

  Widget _sumKv(String label, String value, {String? sub, Color? color}) =>
      Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: TextStyle(fontSize: 11, color: AppColors.text3)),
          const SizedBox(height: 3),
          Text(value,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: color ?? AppColors.text1)),
          if (sub != null)
            Text(sub,
                style: TextStyle(fontSize: 10.5, color: color ?? AppColors.text3)),
        ],
      );

  /// 持仓行的盈亏摘要：成本 / 股数 / 总盈亏
  Widget _holdingLine(Map<String, dynamic> s, double? price) {
    final buyPrice =
        (s['buyPrice'] is num) ? (s['buyPrice'] as num).toDouble() : null;
    final shares =
        (s['shares'] is num) ? (s['shares'] as num).toDouble() : null;
    if (buyPrice == null || shares == null || buyPrice <= 0 || shares <= 0) {
      return Text('持仓', style: TextStyle(fontSize: 11.5, color: AppColors.text3));
    }
    final shareStr =
        shares == shares.truncateToDouble() ? shares.toInt().toString() : shares.toString();
    if (price == null) {
      return Text('$shareStr股 · 成本${buyPrice.toStringAsFixed(3)}',
          style: TextStyle(fontSize: 11.5, color: AppColors.text3));
    }
    final pl = (price - buyPrice) * shares;
    final plPct = buyPrice > 0 ? (price - buyPrice) / buyPrice * 100 : 0.0;
    final c = pl >= 0 ? AppColors.income : AppColors.expense;
    return Row(children: [
      Flexible(
        child: Text('$shareStr股·成本${buyPrice.toStringAsFixed(3)}',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(fontSize: 11.5, color: AppColors.text3)),
      ),
      const SizedBox(width: 8),
      Text(
          '${pl >= 0 ? '+' : ''}¥${pl.abs() < 1e7 ? pl.toStringAsFixed(2) : pl.toStringAsFixed(0)} (${pl >= 0 ? '+' : ''}${plPct.toStringAsFixed(2)}%)',
          style:
              TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600, color: c)),
    ]);
  }

  Widget _ratingChip(String r) {
    Color c;
    if (r.contains('买入') || r.contains('增持')) {
      c = AppColors.income;
    } else if (r.contains('卖出') || r.contains('减持') || r.contains('回避')) {
      c = AppColors.expense;
    } else if (r.contains('中性') || r.contains('持有')) {
      c = AppColors.warning;
    } else {
      c = AppColors.primary;
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
      decoration: BoxDecoration(
        color: c.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(5),
      ),
      child: Text(r,
          style:
              TextStyle(fontSize: 10.5, fontWeight: FontWeight.w700, color: c)),
    );
  }

  String _fmtTime(String iso) {
    final d = DateTime.tryParse(iso);
    if (d == null) return '';
    final diff = DateTime.now().difference(d.toLocal());
    if (diff.inMinutes < 60) return '${diff.inMinutes.clamp(1, 59)}分钟前';
    if (diff.inHours < 24) return '${diff.inHours}小时前';
    if (diff.inDays < 7) return '${diff.inDays}天前';
    return DateFormat('M月d日 HH:mm').format(d.toLocal());
  }
}

/// 查询输入弹层
class _SearchSheet extends StatefulWidget {
  const _SearchSheet();
  @override
  State<_SearchSheet> createState() => _SearchSheetState();
}

class _SearchSheetState extends State<_SearchSheet> {
  final _ctrl = TextEditingController();

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  void _submit() {
    final q = _ctrl.text.trim();
    if (q.isNotEmpty) Navigator.pop(context, q);
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(
          20, 18, 20, MediaQuery.of(context).viewInsets.bottom + 20),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('查询股票',
              style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: AppColors.text1)),
          const SizedBox(height: 4),
          Text('输入名称或代码：苹果 / AAPL、腾讯 / 0700.HK、茅台 / 600519.SS',
              style: TextStyle(fontSize: 12, color: AppColors.text2)),
          const SizedBox(height: 14),
          TextField(
            controller: _ctrl,
            autofocus: true,
            textInputAction: TextInputAction.search,
            onSubmitted: (_) => _submit(),
            decoration: InputDecoration(
              hintText: '股票名称或代码',
              prefixIcon: const Icon(Icons.search_rounded, size: 20),
            ),
          ),
          const SizedBox(height: 16),
          SizedBox(
            height: 50,
            child: ElevatedButton(
              onPressed: _submit,
              child: const Text('查询'),
            ),
          ),
        ],
      ),
    );
  }
}
