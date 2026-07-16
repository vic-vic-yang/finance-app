import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../core/theme.dart';
import '../../widgets/glass.dart';
import '../../services/api_service.dart';
import '../../models/account.dart';
import '../add_bill_screen.dart' show AccountPickerSheet;
import 'tools_common.dart';

/// 股票详情：展示保存的分析（或新查询结果），可「更新最新分析」。
/// 传 [query] = 新查询（名称/代码，会拉取并保存）；或 [symbol] = 看已保存的。
class StockDetailScreen extends StatefulWidget {
  const StockDetailScreen({super.key, this.query, this.symbol, this.title});
  final String? query;
  final String? symbol;
  final String? title;

  @override
  State<StockDetailScreen> createState() => _StockDetailScreenState();
}

class _StockDetailScreenState extends State<StockDetailScreen> {
  bool _loading = true;
  bool _updating = false;
  String? _error;
  Map<String, dynamic>? _quote;
  Map<String, dynamic>? _live; // 进详情时取的最新价
  Map<String, dynamic>? _holding; // 持仓 {buyPrice, shares}
  List<Map<String, dynamic>> _history = [];
  String? _updatedAt;

  @override
  void initState() {
    super.initState();
    if (widget.query != null) {
      _fetch(widget.query!);
    } else {
      _loadSaved();
    }
  }

  Future<void> _loadSaved() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final res = await ApiService.getStockSaved(widget.symbol!);
      if (!mounted) return;
      setState(() {
        _apply(res);
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = '加载失败';
      });
    }
  }

  /// 查询/更新（拉最新 + 保存）
  Future<void> _fetch(String q) async {
    setState(() {
      if (_quote == null) _loading = true;
      _updating = true;
      _error = null;
    });
    try {
      final res = await ApiService.getStock(q);
      if (!mounted) return;
      setState(() {
        _apply(res);
        _loading = false;
        _updating = false;
        if (_quote == null) _error = '未找到该股票';
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _updating = false;
        if (_quote == null) {
          _error = _errMsg(e);
        } else {
          ScaffoldMessenger.of(context)
              .showSnackBar(const SnackBar(content: Text('更新失败，请稍后重试')));
        }
      });
    }
  }

  void _apply(Map<String, dynamic> res) {
    final q = (res['quote'] as Map?)?.cast<String, dynamic>();
    if (q != null) _quote = q;
    final live = res['live'];
    if (live is Map) _live = live.cast<String, dynamic>();
    if (res.containsKey('holding')) {
      final h = res['holding'];
      _holding = h is Map ? h.cast<String, dynamic>() : null;
    }
    _history = ((res['history'] as List?) ?? [])
        .map((e) => (e as Map).cast<String, dynamic>())
        .toList();
    _updatedAt = res['updatedAt'] as String? ?? _updatedAt;
  }

  String _errMsg(Object e) {
    final s = e.toString();
    if (s.contains('未找到') || s.contains('not found')) {
      return '未找到该股票，试试用代码（如 AAPL、0700.HK、600519.SS）';
    }
    return '查询失败，请稍后重试';
  }

  double? _d(dynamic v) =>
      v == null ? null : (v is num ? v.toDouble() : double.tryParse('$v'));

  String _displayName(Map<String, dynamic> q) {
    final zh = (q['nameZh'] ?? '').toString().trim();
    return zh.isNotEmpty ? zh : '${q['name']}';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: AuraAppBar(
        title: _quote != null ? _displayName(_quote!) : (widget.title ?? '股票'),
      ),
      body: AuraBackground(
        child: _loading
            ? _loadingView()
            : _error != null && _quote == null
                ? _errorView()
                : ListView(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 40),
                    children: [
                      _headerCard(),
                      const SizedBox(height: 12),
                      _updateBar(),
                      const SizedBox(height: 14),
                      _holdingCard(),
                      const SizedBox(height: 14),
                      _metricsCard(),
                      if (_history.length > 1) ...[
                        const SizedBox(height: 14),
                        _historyCard(),
                      ],
                    ],
                  ),
      ),
    );
  }

  Widget _loadingView() => Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const CircularProgressIndicator(),
            const SizedBox(height: 12),
            Text(widget.query != null ? '正在获取行情并分析…' : '加载中…',
                style: TextStyle(fontSize: 13, color: AppColors.text2)),
          ],
        ),
      );

  Widget _errorView() => Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.error_outline_rounded,
                  color: AppColors.expense, size: 40),
              const SizedBox(height: 12),
              Text(_error!,
                  textAlign: TextAlign.center,
                  style: TextStyle(color: AppColors.text2)),
            ],
          ),
        ),
      );

  Widget _updateBar() {
    final sym = (_quote?['symbol'] ?? '').toString();
    return Row(children: [
      Expanded(
        child: Text(
          _updatedAt == null ? '' : '更新于 ${_fmtUpdated(_updatedAt!)}',
          style: TextStyle(fontSize: 12, color: AppColors.text3),
        ),
      ),
      OutlinedButton.icon(
        onPressed: _updating || sym.isEmpty ? null : () => _fetch(sym),
        icon: _updating
            ? const SizedBox(
                width: 14,
                height: 14,
                child: CircularProgressIndicator(strokeWidth: 2))
            : const Icon(Icons.refresh_rounded, size: 18),
        label: Text(_updating ? '更新中…' : '更新行情'),
        style: OutlinedButton.styleFrom(
          foregroundColor: AppColors.primary,
          side: BorderSide(color: AppColors.primary.withOpacity(0.5)),
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        ),
      ),
    ]);
  }

  String _fmtUpdated(String iso) {
    final d = DateTime.tryParse(iso);
    if (d == null) return '';
    return DateFormat('M月d日 HH:mm').format(d.toLocal());
  }

  // 当前价/涨跌：优先用进详情拉到的最新价，回退快照
  double? get _curPrice => _d(_live?['price']) ?? _d(_quote?['price']);
  double? get _curChange => _d(_live?['change']) ?? _d(_quote?['change']);
  double? get _curChangePct =>
      _d(_live?['changePercent']) ?? _d(_quote?['changePercent']);

  // ── 头部 ──────────────────────────────────────────────────
  Widget _headerCard() {
    final q = _quote!;
    final price = _curPrice;
    final chg = _curChange;
    final chgPct = _curChangePct;
    final up = (chg ?? 0) >= 0;
    final color = up ? AppColors.income : AppColors.expense;
    final cur = (q['currency'] ?? '').toString();
    return GlassCard(
      radius: 18,
      padding: const EdgeInsets.fromLTRB(18, 16, 18, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Expanded(
              child: Text(_displayName(q),
                  style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                      color: AppColors.text1)),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: AppColors.surfaceAlt,
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text('${q['symbol']}',
                  style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: AppColors.text2)),
            ),
          ]),
          const SizedBox(height: 2),
          Text('${q['exchange']}',
              style: TextStyle(fontSize: 12, color: AppColors.text3)),
          const SizedBox(height: 12),
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Text(_fmtPrice(price),
                  style: TextStyle(
                      fontSize: 30,
                      fontWeight: FontWeight.w700,
                      letterSpacing: -0.5,
                      color: AppColors.text1)),
              const SizedBox(width: 6),
              Text(cur, style: TextStyle(fontSize: 13, color: AppColors.text3)),
              const Spacer(),
              if (chg != null)
                Text(
                  '${up ? '+' : ''}${chg.toStringAsFixed(3)}  ${up ? '+' : ''}${chgPct?.toStringAsFixed(2) ?? '—'}%',
                  style: TextStyle(
                      fontSize: 15, fontWeight: FontWeight.w700, color: color),
                ),
            ],
          ),
        ],
      ),
    );
  }

  // ── 指标网格 ──────────────────────────────────────────────
  Widget _metricsCard() {
    final q = _quote!;
    final cur = (q['currency'] ?? '').toString();
    final items = <List<String>>[
      ['市值', _fmtBig(_d(q['marketCap']), cur)],
      ['市盈率 TTM', _fmtNum(_d(q['pe']))],
      ['预期 PE', _fmtNum(_d(q['forwardPe']))],
      ['市净率 PB', _fmtNum(_d(q['pb']))],
      ['PEG', _fmtNum(_d(q['peg']))],
      ['每股收益 EPS', _fmtNum(_d(q['eps']))],
      ['股息率', _fmtPct(_d(q['dividendYield']))],
      ['Beta', _fmtNum(_d(q['beta']))],
      ['52周最高', _fmtNum(_d(q['high52']))],
      ['52周最低', _fmtNum(_d(q['low52']))],
      ['50日均价', _fmtNum(_d(q['ma50']))],
      ['200日均价', _fmtNum(_d(q['ma200']))],
      ['利润率', _fmtPct(_d(q['profitMargins']))],
      ['ROE', _fmtPct(_d(q['roe']))],
      ['营收增速', _fmtPct(_d(q['revenueGrowth']))],
      ['盈利增速', _fmtPct(_d(q['earningsGrowth']))],
    ];
    return GlassCard(
      radius: 18,
      padding: const EdgeInsets.fromLTRB(6, 8, 6, 8),
      child: Column(
        children: [
          for (int i = 0; i < items.length; i += 2)
            Row(children: [
              Expanded(child: _metric(items[i][0], items[i][1])),
              if (i + 1 < items.length)
                Expanded(child: _metric(items[i + 1][0], items[i + 1][1]))
              else
                const Expanded(child: SizedBox()),
            ]),
        ],
      ),
    );
  }

  Widget _metric(String label, String value) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label,
                style: TextStyle(fontSize: 11.5, color: AppColors.text3)),
            const SizedBox(height: 3),
            Text(value,
                style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: AppColors.text1)),
          ],
        ),
      );

  // ── 历史 ──────────────────────────────────────────────────
  Widget _historyCard() {
    return ToolResultCard(
      title: '查询历史',
      children: [
        for (int i = _history.length - 1; i >= 0; i--)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Row(children: [
              Text(_fmtUpdated((_history[i]['at'] ?? '').toString()),
                  style: TextStyle(fontSize: 13, color: AppColors.text2)),
              const Spacer(),
              Text('价 ${_fmtPrice(_d(_history[i]['price']))}',
                  style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: AppColors.text1)),
              const SizedBox(width: 14),
              Text('PE ${_fmtNum(_d(_history[i]['pe']))}',
                  style: TextStyle(fontSize: 13, color: AppColors.text2)),
            ]),
          ),
      ],
    );
  }

  Widget _holdingCard() {
    final cur = (_quote?['currency'] ?? _live?['currency'] ?? '').toString();
    final buyPrice = _d(_holding?['buyPrice']);
    final shares = _d(_holding?['shares']);
    final price = _curPrice;

    if (buyPrice == null || shares == null || buyPrice <= 0 || shares <= 0) {
      // 未设持仓
      return GlassCard(
        radius: 16,
        onTap: _editHolding,
        child: Row(children: [
          Icon(Icons.add_chart_rounded, color: AppColors.primary, size: 22),
          const SizedBox(width: 10),
          Expanded(
            child: Text('添加持仓，自动算总收益 / 当日收益',
                style: TextStyle(fontSize: 14, color: AppColors.text1)),
          ),
          Icon(Icons.chevron_right_rounded, color: AppColors.text3),
        ]),
      );
    }

    final cost = buyPrice * shares;
    final mktValue = (price ?? buyPrice) * shares;
    final totalPL = ((price ?? buyPrice) - buyPrice) * shares;
    final totalPLPct = buyPrice > 0 ? (totalPL / cost) * 100 : 0.0;
    final dayChange = _curChange;
    final dayPL = dayChange == null ? null : dayChange * shares;
    final plColor = totalPL >= 0 ? AppColors.income : AppColors.expense;

    String money(double v) =>
        '${v >= 0 ? '' : '-'}${v.abs().toStringAsFixed(2)}';

    return GlassCard(
      radius: 18,
      padding: const EdgeInsets.fromLTRB(18, 14, 18, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Icon(Icons.account_balance_wallet_rounded,
                size: 18, color: AppColors.primary),
            const SizedBox(width: 6),
            Text('我的持仓',
                style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: AppColors.text1)),
            if (_holding?['accountId'] != null) ...[
              const SizedBox(width: 8),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: AppColors.primary.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(5),
                ),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  Icon(Icons.autorenew_rounded,
                      size: 11, color: AppColors.primary),
                  const SizedBox(width: 2),
                  Text('每日自动结算',
                      style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w600,
                          color: AppColors.primary)),
                ]),
              ),
            ],
            const Spacer(),
            GestureDetector(
              onTap: _editHolding,
              child: Text('编辑',
                  style: TextStyle(fontSize: 13, color: AppColors.primary)),
            ),
          ]),
          const SizedBox(height: 12),
          // 总收益（大字）
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Text('${totalPL >= 0 ? '+' : ''}${money(totalPL)}',
                  style: TextStyle(
                      fontSize: 26,
                      fontWeight: FontWeight.w700,
                      letterSpacing: -0.5,
                      color: plColor)),
              const SizedBox(width: 6),
              Text(cur, style: TextStyle(fontSize: 12, color: AppColors.text3)),
              const SizedBox(width: 8),
              Text('${totalPL >= 0 ? '+' : ''}${totalPLPct.toStringAsFixed(2)}%',
                  style: TextStyle(
                      fontSize: 14, fontWeight: FontWeight.w600, color: plColor)),
            ],
          ),
          Text('总收益', style: TextStyle(fontSize: 12, color: AppColors.text3)),
          const Divider(height: 20),
          Row(children: [
            Expanded(
                child: _hItem(
                    '当日收益',
                    dayPL == null
                        ? '—'
                        : '${dayPL >= 0 ? '+' : ''}${money(dayPL)}',
                    dayPL == null
                        ? AppColors.text1
                        : (dayPL >= 0 ? AppColors.income : AppColors.expense))),
            Expanded(child: _hItem('持仓市值', mktValue.toStringAsFixed(2), AppColors.text1)),
          ]),
          const SizedBox(height: 8),
          Row(children: [
            Expanded(child: _hItem('成本价', _fmtPrice(buyPrice), AppColors.text2)),
            Expanded(
                child: _hItem(
                    '持有数量',
                    shares == shares.truncateToDouble()
                        ? shares.toInt().toString()
                        : shares.toString(),
                    AppColors.text2)),
          ]),
        ],
      ),
    );
  }

  Widget _hItem(String label, String value, Color color) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: TextStyle(fontSize: 11.5, color: AppColors.text3)),
          const SizedBox(height: 3),
          Text(value,
              style: TextStyle(
                  fontSize: 15, fontWeight: FontWeight.w600, color: color)),
        ],
      );

  Future<void> _editHolding() async {
    final sym = (_quote?['symbol'] ?? widget.symbol ?? '').toString();
    if (sym.isEmpty) return;
    final result = await showModalBottomSheet<Map<String, dynamic>?>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (_) => _HoldingSheet(
        initBuyPrice: _d(_holding?['buyPrice']),
        initShares: _d(_holding?['shares']),
        initAccountId: _holding?['accountId'] as String?,
      ),
    );
    if (result == null) return; // 取消
    final bp = (result['buyPrice'] as num?)?.toDouble() ?? 0;
    final sh = (result['shares'] as num?)?.toDouble() ?? 0;
    final accId = result['accountId'] as String?;
    try {
      final res = await ApiService.setStockHolding(sym,
          buyPrice: bp, shares: sh, accountId: accId);
      if (!mounted) return;
      final h = res['holding'];
      setState(() => _holding = h is Map ? h.cast<String, dynamic>() : null);
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('保存持仓失败')));
      }
    }
  }

  // ── 格式化 ────────────────────────────────────────────────
  /// 股价：保留 3 位小数（部分股票按 0.001 跳动，2 位会算错金额）
  String _fmtPrice(double? v) => v == null ? '—' : v.toStringAsFixed(3);

  String _fmtNum(double? v) => v == null
      ? '—'
      : (v == v.truncateToDouble() && v.abs() < 1000
          ? v.toStringAsFixed(0)
          : v.toStringAsFixed(2));

  String _fmtPct(double? v) =>
      v == null ? '—' : '${(v * 100).toStringAsFixed(1)}%';

  String _fmtBig(double? v, String cur) {
    if (v == null) return '—';
    final suffix = cur.isEmpty ? '' : ' $cur';
    if (v >= 1e12) return '${(v / 1e12).toStringAsFixed(2)}万亿$suffix';
    if (v >= 1e8) return '${(v / 1e8).toStringAsFixed(2)}亿$suffix';
    if (v >= 1e4) return '${(v / 1e4).toStringAsFixed(2)}万$suffix';
    return v.toStringAsFixed(0) + suffix;
  }
}

/// 持仓编辑弹层：买入价 + 持有数量 + 可选关联账户。清空价/量并保存可移除持仓。
class _HoldingSheet extends StatefulWidget {
  const _HoldingSheet(
      {this.initBuyPrice, this.initShares, this.initAccountId});
  final double? initBuyPrice;
  final double? initShares;
  final String? initAccountId;

  @override
  State<_HoldingSheet> createState() => _HoldingSheetState();
}

class _HoldingSheetState extends State<_HoldingSheet> {
  late final TextEditingController _priceCtrl;
  late final TextEditingController _sharesCtrl;
  List<Account> _accounts = [];
  Account? _account;

  @override
  void initState() {
    super.initState();
    String f(double? v) => v == null || v <= 0
        ? ''
        : (v == v.truncateToDouble() ? v.toInt().toString() : v.toString());
    _priceCtrl = TextEditingController(text: f(widget.initBuyPrice));
    _sharesCtrl = TextEditingController(text: f(widget.initShares));
    _loadAccounts();
  }

  Future<void> _loadAccounts() async {
    try {
      final res = await ApiService.getAccounts();
      final list = (res['accounts'] as List? ?? [])
          .map((a) => Account.fromJson(a as Map<String, dynamic>))
          .toList();
      if (!mounted) return;
      setState(() {
        _accounts = list;
        if (widget.initAccountId != null) {
          for (final a in list) {
            if (a.id == widget.initAccountId) _account = a;
          }
        }
      });
    } catch (_) {}
  }

  @override
  void dispose() {
    _priceCtrl.dispose();
    _sharesCtrl.dispose();
    super.dispose();
  }

  void _save() {
    final bp = double.tryParse(_priceCtrl.text.trim()) ?? 0;
    final sh = double.tryParse(_sharesCtrl.text.trim()) ?? 0;
    Navigator.pop(context, {
      'buyPrice': bp,
      'shares': sh,
      'accountId': _account?.id,
    });
  }

  Future<void> _pickAccount() async {
    final a = await showModalBottomSheet<Account>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) =>
          AccountPickerSheet(accounts: _accounts, selectedId: _account?.id),
    );
    if (a != null) setState(() => _account = a);
  }

  @override
  Widget build(BuildContext context) {
    final has = widget.initBuyPrice != null && (widget.initBuyPrice ?? 0) > 0;
    return Padding(
      padding: EdgeInsets.fromLTRB(
          20, 18, 20, MediaQuery.of(context).viewInsets.bottom + 20),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(has ? '编辑持仓' : '添加持仓',
              style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: AppColors.text1)),
          const SizedBox(height: 14),
          TextField(
            controller: _priceCtrl,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: const InputDecoration(
              labelText: '买入均价',
              prefixIcon: Icon(Icons.sell_outlined, size: 20),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _sharesCtrl,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: const InputDecoration(
              labelText: '持有数量（股）',
              prefixIcon: Icon(Icons.numbers_rounded, size: 20),
            ),
          ),
          const SizedBox(height: 12),
          // 关联账户（可选）
          InkWell(
            onTap: _pickAccount,
            borderRadius: BorderRadius.circular(12),
            child: Container(
              height: 56,
              padding: const EdgeInsets.symmetric(horizontal: 14),
              decoration: BoxDecoration(
                color: AppColors.surfaceAlt,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(children: [
                Icon(Icons.link_rounded, size: 20, color: AppColors.text2),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text('关联账户（自动结算）',
                          style:
                              TextStyle(fontSize: 11, color: AppColors.text3)),
                      const SizedBox(height: 2),
                      Text(
                          _account != null
                              ? '${_account!.typeEmoji} ${_account!.name}'
                              : '不关联',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w500,
                              color: AppColors.text1)),
                    ],
                  ),
                ),
                if (_account != null)
                  GestureDetector(
                    onTap: () => setState(() => _account = null),
                    child: Icon(Icons.close_rounded,
                        size: 18, color: AppColors.text3),
                  )
                else
                  Icon(Icons.unfold_more_rounded,
                      size: 18, color: AppColors.text3),
              ]),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            _account != null
                ? '每天 15:00 收盘后按最新价计算当日盈亏，自动更新该账户余额（流水可见、不计收支）。'
                : '关联一个账户后，可每天自动把当日盈亏记到账户、余额随行情更新。',
            style: TextStyle(fontSize: 11, color: AppColors.text3, height: 1.4),
          ),
          const SizedBox(height: 18),
          Row(children: [
            if (has)
              Expanded(
                child: OutlinedButton(
                  onPressed: () =>
                      Navigator.pop(context, {'buyPrice': 0.0, 'shares': 0.0}),
                  style: OutlinedButton.styleFrom(
                    minimumSize: const Size(0, 50),
                    foregroundColor: AppColors.expense,
                    side: BorderSide(color: AppColors.border),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14)),
                  ),
                  child: const Text('移除'),
                ),
              ),
            if (has) const SizedBox(width: 12),
            Expanded(
              flex: 2,
              child: SizedBox(
                height: 50,
                child: ElevatedButton(
                  onPressed: _save,
                  child: const Text('保存'),
                ),
              ),
            ),
          ]),
        ],
      ),
    );
  }
}
