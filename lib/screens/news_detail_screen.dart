import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';
import '../core/theme.dart';
import '../widgets/glass.dart';
import '../models/news_article.dart';
import '../services/api_service.dart';

/// 新闻详情：后端抓原文正文 + LLM 要点分析，直接在 App 内阅读。
class NewsDetailScreen extends StatefulWidget {
  const NewsDetailScreen({super.key, required this.preview});

  /// 列表传入的基础信息，详情加载完成前先用它渲染头部
  final NewsArticle preview;

  @override
  State<NewsDetailScreen> createState() => _NewsDetailScreenState();
}

class _NewsDetailScreenState extends State<NewsDetailScreen> {
  NewsArticle? _full;
  bool _loading = true;
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _failed = false;
    });
    try {
      final res = await ApiService.getNewsDetail(widget.preview.id);
      final raw = res['article'] as Map<String, dynamic>?;
      if (!mounted) return;
      setState(() {
        _full = raw != null ? NewsArticle.fromJson(raw) : null;
        _loading = false;
        _failed = raw == null;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _failed = true;
      });
    }
  }

  Future<void> _openOriginal() async {
    final uri = Uri.tryParse(widget.preview.url);
    if (uri == null) return;
    // 多种模式兜底，提升不同设备/浏览器的成功率
    for (final mode in [
      LaunchMode.externalApplication,
      LaunchMode.platformDefault,
      LaunchMode.inAppBrowserView,
    ]) {
      try {
        final ok = await launchUrl(uri, mode: mode);
        if (ok) return;
      } catch (_) {/* 试下一种 */}
    }
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('无法打开原文链接')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final a = widget.preview;
    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: AuraAppBar(
        title: a.source,
        actions: [
          IconButton(
            tooltip: '查看原文',
            icon: const Icon(Icons.open_in_new_rounded),
            onPressed: _openOriginal,
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: AuraBackground(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 40),
          children: [
            // 头部：分类 + 标题 + 来源时间
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
              if (a.importance >= 70) ...[
                const SizedBox(width: 8),
                Icon(Icons.local_fire_department_rounded,
                    size: 15, color: AppColors.warning),
                Text(' 重要',
                    style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: AppColors.warning)),
              ],
            ]),
            const SizedBox(height: 10),
            Text(a.displayTitle,
                style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w700,
                    height: 1.35,
                    color: AppColors.text1)),
            // 原英文标题做小字（若有中文翻译）
            if ((a.titleZh ?? '').trim().isNotEmpty) ...[
              const SizedBox(height: 6),
              Text(a.title,
                  style: TextStyle(
                      fontSize: 12.5, height: 1.4, color: AppColors.text3)),
            ],
            const SizedBox(height: 8),
            Text('${a.source}  ·  ${DateFormat('M月d日 HH:mm').format(a.publishedAt)}',
                style: TextStyle(fontSize: 12, color: AppColors.text3)),
            const SizedBox(height: 16),

            // AI 要点分析
            _analysisCard(),
            const SizedBox(height: 14),

            // 正文
            _bodyCard(),
            const SizedBox(height: 16),

            // 查看原文
            OutlinedButton.icon(
              onPressed: _openOriginal,
              icon: const Icon(Icons.open_in_new_rounded, size: 18),
              label: const Text('查看原文'),
              style: OutlinedButton.styleFrom(
                minimumSize: const Size(double.infinity, 48),
                side: BorderSide(color: AppColors.border),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _analysisCard() {
    return GlassCard(
      radius: 18,
      padding: const EdgeInsets.fromLTRB(18, 16, 18, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Icon(Icons.auto_awesome_rounded,
                size: 18, color: AppColors.primary),
            const SizedBox(width: 6),
            Text('AI 要点分析',
                style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: AppColors.text1)),
          ]),
          const SizedBox(height: 12),
          if (_loading)
            Row(children: [
              const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2)),
              const SizedBox(width: 12),
              Expanded(
                child: Text('AI 正在阅读全文并提炼要点…',
                    style: TextStyle(fontSize: 13, color: AppColors.text2)),
              ),
            ])
          else if ((_full?.analysis ?? '').trim().isNotEmpty)
            Text(_full!.analysis!.trim(),
                style: TextStyle(
                    fontSize: 14, height: 1.65, color: AppColors.text1))
          else
            Text(
              _failed
                  ? '分析获取失败，可下方查看原文。'
                  : (widget.preview.summary ?? '暂无分析，可查看原文。'),
              style: TextStyle(fontSize: 14, height: 1.6, color: AppColors.text2),
            ),
        ],
      ),
    );
  }

  Widget _bodyCard() {
    final body = (_full?.content ?? '').trim();
    if (_loading) {
      return const SizedBox.shrink();
    }
    if (body.isEmpty) {
      return GlassCard(
        radius: 18,
        child: Row(children: [
          Icon(Icons.article_outlined, color: AppColors.text3, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Text('该来源未能抓到全文，请点「查看原文」阅读。',
                style: TextStyle(fontSize: 13, color: AppColors.text2)),
          ),
        ]),
      );
    }
    return GlassCard(
      radius: 18,
      padding: const EdgeInsets.fromLTRB(18, 16, 18, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('正文',
              style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: AppColors.text2)),
          const SizedBox(height: 10),
          SelectableText(body,
              style: TextStyle(
                  fontSize: 15, height: 1.7, color: AppColors.text1)),
        ],
      ),
    );
  }
}
