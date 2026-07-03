import 'package:flutter/material.dart';
import '../../core/theme.dart';
import '../../widgets/glass.dart';
import '../../services/api_service.dart';
import 'stock_detail_screen.dart';

/// 每日机会股：板块轮动 → 主板选股 → AI 精析出的 Top10（每交易日 00:30 生成）。
class DailyPicksScreen extends StatefulWidget {
  /// embedded=true 时只返回内容（不含 Scaffold/AppBar），用于嵌到股票页的 tab 里
  const DailyPicksScreen({super.key, this.embedded = false});
  final bool embedded;
  @override
  State<DailyPicksScreen> createState() => _DailyPicksScreenState();
}

class _DailyPicksScreenState extends State<DailyPicksScreen> {
  Map<String, dynamic>? _data;
  bool _loading = true;
  bool _running = false;
  bool _autoTried = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  String _todayStr() {
    final n = DateTime.now();
    String two(int x) => x.toString().padLeft(2, '0');
    return '${n.year}-${two(n.month)}-${two(n.day)}';
  }

  Future<void> _load() async {
    try {
      final d = await ApiService.getDailyPicks();
      if (!mounted) return;
      setState(() {
        _data = d;
        _loading = false;
      });
      // 榜单不是今天的（凌晨没跑成）→ 自动补算一次，前台显示"生成中"
      final td = (_data?['tradeDate'] ?? '').toString();
      if (!_autoTried && !_running && td != _todayStr()) {
        _autoTried = true;
        _run();
      }
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _run() async {
    setState(() => _running = true);
    try {
      final d = await ApiService.runDailyPicks();
      if (!mounted) return;
      setState(() {
        _data = d;
        _running = false;
      });
    } catch (_) {
      if (mounted) {
        setState(() => _running = false);
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('生成失败，请稍后重试')));
      }
    }
  }

  List get _picks => (_data?['picks'] as List?) ?? [];
  List get _boards => (_data?['boards'] as List?) ?? [];

  @override
  Widget build(BuildContext context) {
    final body = _loading
        ? const Center(child: CircularProgressIndicator())
        : RefreshIndicator(
            color: AppColors.primary,
            onRefresh: _load,
            child: _picks.isEmpty
                ? _empty()
                : ListView(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 40),
                    children: [
                      if (_running) _generatingBanner(),
                      _headerCard(),
                      _memoryCard(),
                      const SizedBox(height: 14),
                      for (int i = 0; i < _picks.length; i++)
                        _pickCard((_picks[i] as Map).cast<String, dynamic>()),
                      const SizedBox(height: 14),
                      _disclaimer(),
                    ],
                  ),
          );
    // 嵌入模式：外层股票页已提供 Scaffold + AuraBackground，这里只给内容
    if (widget.embedded) return body;
    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: const AuraAppBar(title: '每日机会股'),
      body: AuraBackground(child: body),
    );
  }

  Widget _generatingBanner() => Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
        decoration: BoxDecoration(
          color: AppColors.primaryLight,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppColors.border),
        ),
        child: Row(children: [
          const SizedBox(
            width: 15,
            height: 15,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text('正在生成今日榜单…（约 30–60 秒，下方先显示上一交易日）',
                style: TextStyle(fontSize: 12.5, color: AppColors.text2)),
          ),
        ]),
      );

  Widget _disclaimer() => Text(
        (_data?['disclaimer'] ?? '⚠️ 数据分析与参考信息，不构成投资建议，据此操作风险自负。')
            .toString(),
        textAlign: TextAlign.center,
        style: TextStyle(fontSize: 11, color: AppColors.text3, height: 1.5),
      );

  Widget _empty() => ListView(
        children: [
          const SizedBox(height: 90),
          Center(
            child: Column(children: [
              const Text('🎯', style: TextStyle(fontSize: 48)),
              const SizedBox(height: 14),
              Text('还没有今日榜单',
                  style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: AppColors.text1)),
              const SizedBox(height: 8),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 44),
                child: Text(
                    '每个交易日凌晨 00:30 自动生成：从强势板块里精选主板机会股。也可以现在手动生成。',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                        fontSize: 13, color: AppColors.text2, height: 1.6)),
              ),
              const SizedBox(height: 24),
              SizedBox(
                width: 220,
                height: 48,
                child: ElevatedButton.icon(
                  onPressed: _running ? null : _run,
                  icon: _running
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: Colors.white))
                      : const Icon(Icons.auto_awesome_rounded, size: 18),
                  label: Text(_running ? '分析中，约10-30秒…' : '立即生成'),
                ),
              ),
            ]),
          ),
        ],
      );

  /// 学习记忆：历史战绩 + 自我进化的策略备忘
  Widget _memoryCard() {
    final mem = (_data?['memory'] as Map?)?.cast<String, dynamic>();
    if (mem == null) return const SizedBox.shrink();
    final playbook = (mem['playbook'] ?? '').toString().trim();
    final stats = (mem['stats'] as Map?)?.cast<String, dynamic>();
    final sample = (stats?['sample'] as num?)?.toInt() ?? 0;
    if (playbook.isEmpty && sample < 5) return const SizedBox.shrink();
    final hit = (stats?['hitRate'] as num?)?.toDouble();
    final avg = (stats?['avgReturn'] as num?)?.toDouble();
    return Container(
      margin: const EdgeInsets.only(top: 12),
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 13),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Icon(Icons.psychology_rounded, size: 16, color: AppColors.primary),
            const SizedBox(width: 6),
            Text('策略记忆 · 自我进化',
                style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: AppColors.text1)),
            const Spacer(),
            if (sample >= 5 && hit != null)
              Text('近$sample次 胜率${hit.toStringAsFixed(0)}%',
                  style: TextStyle(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w600,
                      color: hit >= 50 ? AppColors.income : AppColors.text2)),
          ]),
          if (sample >= 5 && avg != null) ...[
            const SizedBox(height: 6),
            Text('平均收益 ${avg >= 0 ? '+' : ''}${avg.toStringAsFixed(2)}%（自推荐以来回测）',
                style: TextStyle(fontSize: 11.5, color: AppColors.text3)),
          ],
          if (playbook.isNotEmpty) ...[
            const SizedBox(height: 10),
            Text('🧠 当前策略备忘',
                style: TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w600,
                    color: AppColors.text2)),
            const SizedBox(height: 4),
            Text(playbook,
                style: TextStyle(
                    fontSize: 12, height: 1.55, color: AppColors.text2)),
          ],
        ],
      ),
    );
  }

  Widget _headerCard() {
    final fg = AppColors.onPrimaryGradient;
    final date = (_data?['tradeDate'] ?? '').toString();
    final comment = (_data?['comment'] ?? '').toString();
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: AppColors.primaryGradient,
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(18),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Text('🎯 今日机会股',
                style: TextStyle(
                    color: fg, fontSize: 16, fontWeight: FontWeight.w700)),
            const Spacer(),
            if (date.isNotEmpty)
              Text(date,
                  style: TextStyle(color: fg.withOpacity(0.6), fontSize: 12)),
          ]),
          if (comment.isNotEmpty) ...[
            const SizedBox(height: 10),
            Text(comment,
                style: TextStyle(
                    color: fg.withOpacity(0.9), fontSize: 13, height: 1.6)),
          ],
          if (_boards.isNotEmpty) ...[
            const SizedBox(height: 12),
            Text('强势板块',
                style: TextStyle(color: fg.withOpacity(0.6), fontSize: 11)),
            const SizedBox(height: 6),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final b in _boards)
                  _boardChip((b as Map).cast<String, dynamic>(), fg),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _boardChip(Map<String, dynamic> b, Color fg) {
    final name = (b['name'] ?? '').toString();
    final pct = (b['pct'] as num?)?.toDouble() ?? 0;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
      decoration: BoxDecoration(
        color: fg.withOpacity(0.14),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text('$name +${pct.toStringAsFixed(2)}%',
          style: TextStyle(
              color: fg, fontSize: 11.5, fontWeight: FontWeight.w600)),
    );
  }

  Widget _pickCard(Map<String, dynamic> p) {
    final rank = (p['rank'] as num?)?.toInt() ?? 0;
    final name = (p['name'] ?? '').toString();
    final code = (p['code'] ?? '').toString();
    final board = (p['boardName'] ?? '').toString();
    final price = (p['price'] as num?)?.toDouble();
    final chg = (p['changePercent'] as num?)?.toDouble() ?? 0;
    final pe = (p['pe'] as num?)?.toDouble();
    final score = (p['score'] as num?)?.toInt() ?? 0;
    final action = (p['action'] ?? '').toString();
    final reason = (p['reason'] ?? '').toString();
    final risk = (p['risk'] ?? '').toString();
    final ac = _actionColor(action);
    final chgColor = chg >= 0 ? AppColors.income : AppColors.expense;

    return GlassCard(
      margin: const EdgeInsets.only(bottom: 10),
      radius: 16,
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 13),
      onTap: () => Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => StockDetailScreen(query: code, title: name),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            // 排名
            Container(
              width: 24,
              height: 24,
              decoration: BoxDecoration(
                color: rank <= 3
                    ? AppColors.primary
                    : AppColors.surfaceAlt,
                borderRadius: BorderRadius.circular(7),
              ),
              child: Center(
                child: Text('$rank',
                    style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: rank <= 3
                            ? AppColors.onPrimary
                            : AppColors.text2)),
              ),
            ),
            const SizedBox(width: 10),
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
                              fontWeight: FontWeight.w700,
                              color: AppColors.text1)),
                    ),
                    const SizedBox(width: 6),
                    Text(code,
                        style:
                            TextStyle(fontSize: 11, color: AppColors.text3)),
                  ]),
                  const SizedBox(height: 2),
                  Text(board,
                      style:
                          TextStyle(fontSize: 11, color: AppColors.text3)),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                if (price != null)
                  Text(price.toStringAsFixed(2),
                      style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                          color: AppColors.text1)),
                Text('${chg >= 0 ? '+' : ''}${chg.toStringAsFixed(2)}%',
                    style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: chgColor)),
              ],
            ),
          ]),
          const SizedBox(height: 10),
          Row(children: [
            _badge('评分 $score', AppColors.primary),
            const SizedBox(width: 6),
            if (action.isNotEmpty) _badge(action, ac),
            const Spacer(),
            if (pe != null)
              Text('PE ${pe.toStringAsFixed(1)}',
                  style: TextStyle(fontSize: 11, color: AppColors.text3)),
          ]),
          if (reason.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(reason,
                style: TextStyle(
                    fontSize: 12.5, height: 1.5, color: AppColors.text2)),
          ],
          if (risk.isNotEmpty) ...[
            const SizedBox(height: 6),
            Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('风险 ',
                  style: TextStyle(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w600,
                      color: AppColors.warning)),
              Expanded(
                child: Text(risk,
                    style: TextStyle(
                        fontSize: 11.5, height: 1.5, color: AppColors.text3)),
              ),
            ]),
          ],
        ],
      ),
    );
  }

  Widget _badge(String t, Color c) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
        decoration: BoxDecoration(
          color: c.withOpacity(0.13),
          borderRadius: BorderRadius.circular(6),
        ),
        child: Text(t,
            style: TextStyle(
                fontSize: 11, fontWeight: FontWeight.w700, color: c)),
      );

  Color _actionColor(String a) {
    if (a.contains('重点')) return AppColors.income;
    if (a.contains('逢低')) return AppColors.primary;
    return AppColors.text2; // 观望
  }
}
