import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../core/theme.dart';
import '../../widgets/glass.dart';
import '../../services/api_service.dart';
import 'stock_detail_screen.dart';

/// 股票分析：我查询过的股票列表（按股票分），可查询新股票、进入看分析并更新。
class StockScreen extends StatefulWidget {
  const StockScreen({super.key});

  @override
  State<StockScreen> createState() => _StockScreenState();
}

class _StockScreenState extends State<StockScreen> {
  List<Map<String, dynamic>> _list = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final res = await ApiService.getStocks();
      if (!mounted) return;
      setState(() {
        _list = res.map((e) => (e as Map).cast<String, dynamic>()).toList();
        _loading = false;
      });
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
        title: '股票分析',
        actions: [
          IconButton(
            tooltip: '查询股票',
            icon: const Icon(Icons.search_rounded),
            onPressed: _search,
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: AuraBackground(
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : RefreshIndicator(
                color: AppColors.primary,
                onRefresh: _load,
                child: _list.isEmpty ? _empty() : _listView(),
              ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _search,
        icon: const Icon(Icons.add_rounded),
        label: const Text('查询股票'),
        // 覆盖主题里 FAB 的 CircleBorder，否则带文字的扩展 FAB 会被挤成圆形
        shape: const StadiumBorder(),
        extendedPadding: const EdgeInsets.symmetric(horizontal: 20),
      ),
    );
  }

  Widget _empty() => ListView(
        children: [
          const SizedBox(height: 100),
          Center(
            child: Column(
              children: [
                const Text('📈', style: TextStyle(fontSize: 44)),
                const SizedBox(height: 12),
                Text('还没有查询过股票',
                    style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        color: AppColors.text1)),
                const SizedBox(height: 6),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 40),
                  child: Text(
                    '点右下角「查询股票」，输入名称或代码（苹果 / AAPL / 600519）。'
                    '查过的会存在这里，方便随时回看和更新分析。',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                        fontSize: 13, color: AppColors.text2, height: 1.6),
                  ),
                ),
              ],
            ),
          ),
        ],
      );

  Widget _listView() {
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 90),
      itemCount: _list.length,
      itemBuilder: (_, i) => _row(_list[i]),
    );
  }

  Widget _row(Map<String, dynamic> s) {
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
              Text('更新于 ${_fmtTime((s['updatedAt'] ?? '').toString())}',
                  style: TextStyle(fontSize: 11.5, color: AppColors.text3)),
            ],
          ),
        ),
        const SizedBox(width: 10),
        Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text(price == null ? '—' : price.toStringAsFixed(2),
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
        color: c.withOpacity(0.14),
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
