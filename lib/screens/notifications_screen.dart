import 'package:flutter/material.dart';
import '../core/theme.dart';
import '../models/app_notification.dart';
import '../services/notification_service.dart';
import '../widgets/siku_ui.dart';

/// 通知列表数据源（可注入，便于测试）：分页，未读在前。
typedef NotificationListFetcher = Future<Map<String, dynamic>> Function({
  int page,
  int pageSize,
});

/// 单条已读操作（可注入，便于测试）。
typedef NotificationReadMarker = Future<void> Function(String id);

/// 通知中心：服务端主动推送（CFO 预警等）的用户级通知列表。
/// - 未读在前，点击单条标记已读，右上角「全部已读」
/// - 下拉刷新 + 滚动到底部分页加载
class NotificationsScreen extends StatefulWidget {
  const NotificationsScreen({
    super.key,
    this.listFetcher,
    this.readMarker,
    this.allReadMarker,
  });

  /// 数据源，默认走 [NotificationService]；测试时注入假实现。
  final NotificationListFetcher? listFetcher;
  final NotificationReadMarker? readMarker;

  /// 「全部已读」操作，默认 [NotificationService.markAllRead]。
  final Future<void> Function()? allReadMarker;

  @override
  State<NotificationsScreen> createState() => _NotificationsScreenState();
}

class _NotificationsScreenState extends State<NotificationsScreen> {
  static const _pageSize = 20;

  NotificationListFetcher get _fetch => widget.listFetcher ?? NotificationService.list;
  NotificationReadMarker get _markReadApi => widget.readMarker ?? NotificationService.markRead;
  Future<void> Function() get _markAllReadApi => widget.allReadMarker ?? NotificationService.markAllRead;

  final _scroll = ScrollController();
  List<AppNotification> _items = [];
  bool _loading = true;
  bool _loadingMore = false;
  bool _hasMore = false;
  int _page = 1;

  @override
  void initState() {
    super.initState();
    _load();
    _scroll.addListener(_maybeLoadMore);
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  void _maybeLoadMore() {
    if (!_hasMore || _loading || _loadingMore) return;
    if (_scroll.position.pixels >=
        _scroll.position.maxScrollExtent - 200) {
      _loadMore();
    }
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final res = await _fetch(page: 1, pageSize: _pageSize);
      if (!mounted) return;
      setState(() {
        _items = _parse(res);
        _page = 1;
        _hasMore = res['hasMore'] == true;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _loading = false);
      _toast('加载失败：$e');
    }
  }

  Future<void> _loadMore() async {
    setState(() => _loadingMore = true);
    try {
      final res =
          await _fetch(page: _page + 1, pageSize: _pageSize);
      if (!mounted) return;
      setState(() {
        _items = [..._items, ..._parse(res)];
        _page += 1;
        _hasMore = res['hasMore'] == true;
        _loadingMore = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loadingMore = false);
    }
  }

  List<AppNotification> _parse(Map<String, dynamic> res) =>
      (res['items'] as List? ?? [])
          .map((e) => AppNotification.fromJson(e as Map<String, dynamic>))
          .toList();

  void _toast(String s) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(s)));
  }

  /// 点击单条：本地立即置已读（乐观更新），后台调 API
  Future<void> _markRead(AppNotification n) async {
    if (!n.isUnread) return;
    setState(() {
      _items = [
        for (final x in _items)
          x.id == n.id ? _copyRead(x) : x,
      ];
    });
    try {
      await _markReadApi(n.id);
    } catch (_) {
      /* 静默：下次进来还是未读，不打扰 */
    }
  }

  Future<void> _markAllRead() async {
    if (!_items.any((n) => n.isUnread)) return;
    setState(() {
      _items = [for (final x in _items) _copyRead(x)];
    });
    try {
      await _markAllReadApi();
    } catch (e) {
      _toast('操作失败：$e');
      _load(); // 失败回滚到服务端真实状态
    }
  }

  AppNotification _copyRead(AppNotification n) => AppNotification(
        id: n.id,
        type: n.type,
        title: n.title,
        body: n.body,
        ledgerId: n.ledgerId,
        payload: n.payload,
        readAt: DateTime.now(),
        createdAt: n.createdAt,
      );

  // 与洞察 / CFO 一致：critical=哑红、warning=琥珀、info=主题色
  Color _sevColor(AppNotification n) {
    final sev = n.severity;
    if (sev == 'critical') return AppColors.income;
    if (sev == 'warning') return AppColors.warning;
    return AppColors.primary;
  }

  IconData _typeIcon(AppNotification n) {
    if (n.type == 'cfo_proposal') {
      if (n.severity == 'critical') return Icons.error_outline_rounded;
      if (n.severity == 'warning') return Icons.warning_amber_rounded;
      return Icons.lightbulb_outline_rounded;
    }
    return Icons.notifications_none_rounded;
  }

  /// 相对时间：N分钟前 / N小时前 / N天前 / 日期
  String _relativeTime(DateTime dt) {
    final diff = DateTime.now().difference(dt.toLocal());
    if (diff.inMinutes < 1) return '刚刚';
    if (diff.inMinutes < 60) return '${diff.inMinutes}分钟前';
    if (diff.inHours < 24) return '${diff.inHours}小时前';
    if (diff.inDays < 7) return '${diff.inDays}天前';
    final l = dt.toLocal();
    return '${l.year}-${l.month.toString().padLeft(2, '0')}-${l.day.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final hasUnread = _items.any((n) => n.isUnread);
    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: AuraAppBar(
        title: '通知',
        actions: [
          if (hasUnread)
            Padding(
              padding: const EdgeInsets.only(right: 12),
              child: TextButton(
                onPressed: _markAllRead,
                child: Text('全部已读',
                    style: TextStyle(fontSize: 13, color: AppColors.primary)),
              ),
            ),
        ],
      ),
      body: AuraBackground(
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : RefreshIndicator(
                onRefresh: _load,
                child: _items.isEmpty
                    ? ListView(
                        physics: const AlwaysScrollableScrollPhysics(),
                        children: const [
                          EmptyState(
                            emoji: '🔔',
                            title: '暂无通知',
                            hint: '司库发现重要财务动向时，会第一时间通知你。',
                          ),
                        ],
                      )
                    : ListView.separated(
                        controller: _scroll,
                        physics: const AlwaysScrollableScrollPhysics(),
                        padding: const EdgeInsets.fromLTRB(20, 12, 20, 40),
                        itemCount: _items.length + (_loadingMore ? 1 : 0),
                        separatorBuilder: (_, __) => const SizedBox(height: 10),
                        itemBuilder: (_, i) {
                          if (i >= _items.length) {
                            return const Padding(
                              padding: EdgeInsets.symmetric(vertical: 16),
                              child: Center(
                                child: SizedBox(
                                  width: 20,
                                  height: 20,
                                  child:
                                      CircularProgressIndicator(strokeWidth: 2),
                                ),
                              ),
                            );
                          }
                          return _card(_items[i]);
                        },
                      ),
              ),
      ),
    );
  }

  Widget _card(AppNotification n) {
    final color = _sevColor(n);
    return GlassCard(
      radius: 16,
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 12),
      onTap: () => _markRead(n),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 类型图标（按严重级着色）
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: AppColors.surfaceAlt,
              shape: BoxShape.circle,
            ),
            child: Icon(_typeIcon(n), size: 20, color: color),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        n.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight:
                              n.isUnread ? FontWeight.w700 : FontWeight.w500,
                          color: AppColors.text1,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      _relativeTime(n.createdAt),
                      style: TextStyle(fontSize: 11, color: AppColors.text3),
                    ),
                  ],
                ),
                if (n.body.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(
                    n.body,
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 13,
                      height: 1.45,
                      color: AppColors.text2,
                    ),
                  ),
                ],
              ],
            ),
          ),
          // 未读圆点
          if (n.isUnread)
            Padding(
              padding: const EdgeInsets.only(left: 8, top: 4),
              child: Container(
                key: Key('unread-dot-${n.id}'),
                width: 8,
                height: 8,
                decoration: BoxDecoration(
                  color: color,
                  shape: BoxShape.circle,
                ),
              ),
            ),
        ],
      ),
    );
  }
}
