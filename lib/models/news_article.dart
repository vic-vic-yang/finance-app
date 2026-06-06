/// 财经新闻条目（后端 RSS 聚合 + LLM 富化）
class NewsArticle {
  final String id;
  final String title;
  final String? titleZh;
  final String? summary;
  final String source;
  final String url;
  final String? imageUrl;
  final String? category;
  final int importance;
  final String? sentiment;
  final String? content;
  final String? analysis;
  final DateTime publishedAt;

  NewsArticle({
    required this.id,
    required this.title,
    this.titleZh,
    this.summary,
    required this.source,
    required this.url,
    this.imageUrl,
    this.category,
    this.importance = 0,
    this.sentiment,
    this.content,
    this.analysis,
    required this.publishedAt,
  });

  /// 展示标题：优先中文翻译，回退原标题
  String get displayTitle =>
      (titleZh ?? '').trim().isNotEmpty ? titleZh!.trim() : title;

  factory NewsArticle.fromJson(Map<String, dynamic> j) => NewsArticle(
        id: j['id'] as String? ?? '',
        title: j['title'] as String? ?? '',
        titleZh: j['titleZh'] as String?,
        summary: j['summary'] as String?,
        source: j['source'] as String? ?? '',
        url: j['url'] as String? ?? '',
        imageUrl: j['imageUrl'] as String?,
        category: j['category'] as String?,
        importance: (j['importance'] as num?)?.toInt() ?? 0,
        sentiment: j['sentiment'] as String?,
        content: j['content'] as String?,
        analysis: j['analysis'] as String?,
        publishedAt: DateTime.tryParse(j['publishedAt'] as String? ?? '') ??
            DateTime.now(),
      );
}
