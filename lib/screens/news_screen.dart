import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../core/theme.dart';
import '../widgets/glass.dart';
import '../models/news_article.dart';
import '../services/api_service.dart';
import 'news_detail_screen.dart';

/// 财经资讯：后端每日聚合的全球财经新闻，LLM 中文摘要 + 重要性排序。
class NewsScreen extends StatefulWidget {
  const NewsScreen({super.key});

  @override
  State<NewsScreen> createState() => _NewsScreenState();
}

class _NewsScreenState extends State<NewsScreen> {
  List<NewsArticle> _articles = [];
  bool _loading = true;
  String? _error;
  String _filter = '全部';

  @override
  void initState() {
    super.initState();
    _load();
  }

  /// [silent] 为 true 时不切全屏 loading（下拉刷新用，列表保留、只显示下拉转圈）
  Future<void> _load({bool silent = false}) async {
    if (!silent) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }
    try {
      final res = await ApiService.getNews(limit: 100);
      _apply(res);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        if (!silent) _error = '加载失败，请检查网络';
        _loading = false;
      });
    }
  }

  void _apply(Map<String, dynamic> res) {
    if (!mounted) return;
    final list = (res['articles'] as List? ?? [])
        .map((e) => NewsArticle.fromJson(e as Map<String, dynamic>))
        .toList();
    setState(() {
      _articles = list;
      _loading = false;
    });
  }

  /// 优先排在前面的分类顺序（政治/政策 · 股市 · 加密 · 科技 · AI），其余跟后面
  static const _priority = ['政治', '政策', '股市', '加密', '科技', 'AI'];

  List<String> get _categories {
    final present = <String>{};
    for (final a in _articles) {
      if ((a.category ?? '').isNotEmpty) present.add(a.category!);
    }
    final ordered = <String>[];
    // 先按优先级放
    for (final c in _priority) {
      if (present.remove(c)) ordered.add(c);
    }
    // 其余按出现顺序补在后面
    ordered.addAll(present);
    return ['全部', ...ordered];
  }

  List<NewsArticle> get _filtered => _filter == '全部'
      ? _articles
      : _articles.where((a) => a.category == _filter).toList();

  void _open(NewsArticle a) {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => NewsDetailScreen(preview: a)),
    );
  }

  String _relTime(DateTime d) {
    final now = DateTime.now();
    final diff = now.difference(d);
    if (diff.inMinutes < 1) return '刚刚';
    if (diff.inMinutes < 60) return '${diff.inMinutes}分钟前';
    if (diff.inHours < 24) return '${diff.inHours}小时前';
    if (diff.inDays == 1) return '昨天';
    if (diff.inDays < 7) return '${diff.inDays}天前';
    return DateFormat('M月d日').format(d);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: const AuraAppBar(title: '财经资讯'),
      body: AuraBackground(
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : _error != null
                ? _errorView()
                : RefreshIndicator(
                    color: AppColors.primary,
                    // 仅重新读取后端已有列表，不强制后端抓取（抓取时机由后端控制）
                    onRefresh: () => _load(silent: true),
                    child: Column(
                      children: [
                        if (_categories.length > 1) _filterBar(),
                        Expanded(child: _list()),
                      ],
                    ),
                  ),
      ),
    );
  }

  Widget _errorView() => Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.cloud_off_rounded, color: AppColors.text3, size: 40),
            const SizedBox(height: 12),
            Text(_error!, style: TextStyle(color: AppColors.text2)),
            const SizedBox(height: 12),
            OutlinedButton(onPressed: _load, child: const Text('重试')),
          ],
        ),
      );

  Widget _filterBar() {
    final cats = _categories;
    return SizedBox(
      height: 44,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.fromLTRB(16, 6, 16, 6),
        itemCount: cats.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (_, i) {
          final c = cats[i];
          final sel = _filter == c;
          return GestureDetector(
            onTap: () => setState(() => _filter = c),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14),
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: sel ? AppColors.primary : AppColors.surfaceAlt,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                    color: sel ? AppColors.primary : AppColors.border,
                    width: 0.6),
              ),
              child: Text(c,
                  style: TextStyle(
                      fontSize: 13,
                      fontWeight: sel ? FontWeight.w600 : FontWeight.w500,
                      color: sel ? AppColors.onPrimary : AppColors.text2)),
            ),
          );
        },
      ),
    );
  }

  Widget _list() {
    final items = _filtered;
    if (items.isEmpty) {
      return ListView(
        children: [
          const SizedBox(height: 120),
          Center(
            child: Column(
              children: [
                const Text('📰', style: TextStyle(fontSize: 40)),
                const SizedBox(height: 10),
                Text('暂无资讯，下拉刷新试试',
                    style: TextStyle(color: AppColors.text2)),
              ],
            ),
          ),
        ],
      );
    }
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(16, 6, 16, 100),
      itemCount: items.length,
      itemBuilder: (_, i) => _card(items[i]),
    );
  }

  Color _sentColor(String? s) {
    switch (s) {
      case 'positive':
        return AppColors.income;
      case 'negative':
        return AppColors.expense;
      default:
        return AppColors.text3;
    }
  }

  Widget _card(NewsArticle a) {
    final hasSummary = (a.summary ?? '').trim().isNotEmpty;
    return GlassCard(
      margin: const EdgeInsets.only(bottom: 10),
      radius: 16,
      padding: const EdgeInsets.fromLTRB(16, 14, 14, 14),
      onTap: () => _open(a),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 顶部：分类 + 情绪点 + 重要性
          Row(children: [
            if ((a.category ?? '').isNotEmpty)
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: AppColors.primary.withOpacity(0.10),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(a.category!,
                    style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: AppColors.primary)),
              ),
            const SizedBox(width: 8),
            Container(
              width: 7,
              height: 7,
              decoration: BoxDecoration(
                color: _sentColor(a.sentiment),
                shape: BoxShape.circle,
              ),
            ),
            const Spacer(),
            if (a.importance >= 70)
              Row(children: [
                Icon(Icons.local_fire_department_rounded,
                    size: 14, color: AppColors.warning),
                const SizedBox(width: 2),
                Text('重要',
                    style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: AppColors.warning)),
              ]),
          ]),
          const SizedBox(height: 8),
          // 中文标题做大标题
          Text(
            a.displayTitle,
            style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w600,
                height: 1.4,
                color: AppColors.text1),
          ),
          // 中文摘要做描述
          if (hasSummary) ...[
            const SizedBox(height: 4),
            Text(
              a.summary!,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                  fontSize: 12.5, height: 1.45, color: AppColors.text2),
            ),
          ],
          const SizedBox(height: 10),
          Row(children: [
            Text(a.source,
                style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                    color: AppColors.text2)),
            Text('  ·  ${_relTime(a.publishedAt)}',
                style: TextStyle(fontSize: 12, color: AppColors.text3)),
            const Spacer(),
            Icon(Icons.open_in_new_rounded,
                size: 15, color: AppColors.text3),
          ]),
        ],
      ),
    );
  }
}
