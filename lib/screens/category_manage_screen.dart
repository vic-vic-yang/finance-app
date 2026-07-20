import 'package:flutter/material.dart';
import '../core/theme.dart';
import '../models/category.dart';
import '../services/api_service.dart';
import '../widgets/siku_ui.dart';
import 'add_bill_screen.dart' show promptCategoryEditor;

/// 分类管理：按 支出 / 收入 分组，一级分类可展开看二级。
/// - 系统分类：只读（不可改名、删除），但允许在其下新建自定义二级分类。
/// - 自建分类：可编辑（名称 / 图标）、可删除。
class CategoryManageScreen extends StatefulWidget {
  const CategoryManageScreen({super.key});

  @override
  State<CategoryManageScreen> createState() => _CategoryManageScreenState();
}

class _CategoryManageScreenState extends State<CategoryManageScreen> {
  bool _loading = true;
  List<Category> _cats = [];
  String _type = 'expense';
  final Set<String> _expanded = {};
  // 本地自定义顺序（id -> 次序）；未拖动过的组回落到后端返回顺序（_idx 兜底）
  final Map<String, int> _order = {};
  final Map<String, int> _idx = {};

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load({bool silent = false}) async {
    if (!silent) setState(() => _loading = true);
    try {
      final res = await ApiService.getCategories();
      final list = (res['categories'] as List? ?? [])
          .map((e) => Category.fromJson(e as Map<String, dynamic>))
          .toList();
      if (!mounted) return;
      _idx
        ..clear()
        ..addEntries(
            [for (var i = 0; i < list.length; i++) MapEntry(list[i].id, i)]);
      setState(() {
        _cats = list;
        _loading = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  int _cmp(Category a, Category b) {
    final ao = _order[a.id], bo = _order[b.id];
    if (ao != null && bo != null) return ao.compareTo(bo);
    if (ao != null) return -1;
    if (bo != null) return 1;
    return (_idx[a.id] ?? 0).compareTo(_idx[b.id] ?? 0);
  }

  List<Category> get _roots =>
      _cats.where((c) => c.isRoot && c.type == _type).toList()..sort(_cmp);

  List<Category> _childrenOf(String rootId) =>
      _cats.where((c) => c.parentId == rootId).toList()..sort(_cmp);

  /// 拖拽后：按新顺序写本地 _order 并持久化（后台保存，失败静默）
  void _persistOrder(List<Category> ordered) {
    for (var i = 0; i < ordered.length; i++) {
      _order[ordered[i].id] = i;
    }
    ApiService.reorderCategories(ordered.map((c) => c.id).toList())
        .catchError((_) => <String, dynamic>{});
  }

  void _reorderRoots(int oldIndex, int newIndex) {
    final list = _roots;
    if (newIndex > oldIndex) newIndex -= 1;
    final item = list.removeAt(oldIndex);
    list.insert(newIndex, item);
    setState(() => _persistOrder(list));
  }

  void _reorderChildren(String rootId, int oldIndex, int newIndex) {
    final list = _childrenOf(rootId);
    if (newIndex > oldIndex) newIndex -= 1;
    final item = list.removeAt(oldIndex);
    list.insert(newIndex, item);
    setState(() => _persistOrder(list));
  }

  Future<void> _createParent() async {
    final created = await promptCategoryEditor(
      context: context,
      title: '新建一级分类',
      hint: '比如：装修、副业、宠物用品',
      type: _type,
      parentId: null,
      parentName: null,
    );
    if (created != null) {
      _expanded.add(created.id);
      await _load(silent: true);
    }
  }

  Future<void> _createChild(Category parent) async {
    final created = await promptCategoryEditor(
      context: context,
      title: '在「${parent.name}」下新建二级分类',
      hint: '比如：早茶、机油、保养',
      type: _type,
      parentId: parent.id,
      parentName: parent.name,
    );
    if (created != null) {
      _expanded.add(parent.id);
      await _load(silent: true);
    }
  }

  Future<void> _edit(Category cat) async {
    final updated = await promptCategoryEditor(
      context: context,
      title: cat.isChild ? '编辑二级分类' : '编辑一级分类',
      hint: '分类名称',
      type: cat.type,
      parentId: cat.parentId,
      parentName: cat.parentName,
      existing: cat,
    );
    if (updated != null) await _load(silent: true);
  }

  Future<void> _delete(Category cat) async {
    final childCount = cat.isRoot ? _childrenOf(cat.id).length : 0;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text('删除「${cat.name}」？', style: const TextStyle(fontSize: 16)),
        content: Text(
          childCount > 0
              ? '该分类下有 $childCount 个二级分类，需先删除或移走二级分类后才能删除。'
              : '删除后，已记在此分类的账单会变为「未分类」。此操作不可撤销。',
          style: TextStyle(fontSize: 13, color: AppColors.text2, height: 1.4),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('取消')),
          TextButton(
            onPressed:
                childCount > 0 ? null : () => Navigator.pop(ctx, true),
            child: Text('删除',
                style: TextStyle(
                    color: childCount > 0
                        ? AppColors.text3
                        : AppColors.danger)),
          ),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await ApiService.deleteCategory(cat.id);
      await _load(silent: true);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('删除失败：可能仍有账单使用该分类')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final roots = _roots;
    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: AuraAppBar(
        title: '分类管理',
        actions: [
          HeaderAddButton(tooltip: '新建分类', onPressed: _createParent),
        ],
      ),
      body: AuraBackground(
        child: Column(
          children: [
            _typeToggle(),
            Expanded(
              child: _loading
                  ? const Center(child: CircularProgressIndicator())
                  : roots.isEmpty
                      ? Center(
                          child: EmptyState(
                            emoji: '🏷️',
                            title:
                                '还没有${_type == 'expense' ? '支出' : '收入'}分类',
                            hint: '点右上 + 新建分类',
                            top: 0,
                          ),
                        )
                      : ReorderableListView.builder(
                          padding: const EdgeInsets.fromLTRB(16, 4, 16, 100),
                          buildDefaultDragHandles: false,
                          itemCount: roots.length,
                          onReorder: _reorderRoots,
                          itemBuilder: (_, i) => _rootTile(roots[i], i),
                        ),
            ),
          ],
        ),
      ),
    );
  }

  // ── 支出 / 收入 切换 ───────────────────────────────────────
  Widget _typeToggle() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
      child: AuraSegmented<String>(
        variant: AuraSegmentedVariant.float,
        options: const [
          (value: 'expense', label: '支出'),
          (value: 'income', label: '收入'),
        ],
        selected: _type,
        onChanged: (v) => setState(() => _type = v),
      ),
    );
  }

  // ── 一级分类卡（可展开） ────────────────────────────────────
  Widget _rootTile(Category root, int index) {
    final children = _childrenOf(root.id);
    final open = _expanded.contains(root.id);
    return Container(
      key: ValueKey(root.id),
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        children: [
          InkWell(
            borderRadius: BorderRadius.circular(14),
            onTap: () => setState(() =>
                open ? _expanded.remove(root.id) : _expanded.add(root.id)),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(6, 10, 6, 10),
              child: Row(
                children: [
                  _dragHandle(index),
                  _iconBox(root.displayIcon),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Row(children: [
                      Flexible(
                        child: Text(root.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                                fontSize: 15, fontWeight: FontWeight.w600)),
                      ),
                      if (root.isSystem) ...[
                        const SizedBox(width: 6),
                        _sysBadge(),
                      ],
                    ]),
                  ),
                  if (children.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(right: 2),
                      child: Text('${children.length}',
                          style: TextStyle(
                              fontSize: 12, color: AppColors.text3)),
                    ),
                  _rowMenu(root),
                  AnimatedRotation(
                    turns: open ? 0.5 : 0,
                    duration: const Duration(milliseconds: 160),
                    child: Icon(Icons.keyboard_arrow_down_rounded,
                        color: AppColors.text3),
                  ),
                ],
              ),
            ),
          ),
          if (open) ...[
            Divider(height: 1, color: AppColors.border),
            if (children.isNotEmpty)
              ReorderableListView(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                buildDefaultDragHandles: false,
                onReorder: (o, n) => _reorderChildren(root.id, o, n),
                children: [
                  for (var i = 0; i < children.length; i++)
                    _childRow(children[i], i),
                ],
              ),
            _addChildRow(root),
          ],
        ],
      ),
    );
  }

  Widget _childRow(Category c, int index) => Padding(
        key: ValueKey(c.id),
        padding: const EdgeInsets.fromLTRB(14, 0, 6, 0),
        child: Row(
          children: [
            _dragHandle(index, small: true),
            Text(c.displayIcon, style: const TextStyle(fontSize: 16)),
            const SizedBox(width: 10),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 10),
                child: Text(c.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style:
                        TextStyle(fontSize: 14, color: AppColors.text1)),
              ),
            ),
            if (c.isSystem) _sysBadge(),
            _rowMenu(c),
          ],
        ),
      );

  Widget _addChildRow(Category root) => InkWell(
        onTap: () => _createChild(root),
        borderRadius:
            const BorderRadius.vertical(bottom: Radius.circular(14)),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 9, 12, 11),
          child: Row(children: [
            const SizedBox(width: 8),
            Icon(Icons.add_rounded, size: 18, color: AppColors.primary),
            const SizedBox(width: 8),
            Text('添加二级分类',
                style: TextStyle(fontSize: 13, color: AppColors.primary)),
          ]),
        ),
      );

  /// 自建分类才显示「编辑 / 删除」菜单；系统分类返回占位空白（保持对齐）
  Widget _rowMenu(Category cat) {
    if (cat.isSystem) return const SizedBox(width: 8);
    return PopupMenuButton<String>(
      icon: Icon(Icons.more_vert_rounded, size: 18, color: AppColors.text3),
      padding: EdgeInsets.zero,
      splashRadius: 18,
      onSelected: (v) {
        if (v == 'edit') _edit(cat);
        if (v == 'delete') _delete(cat);
      },
      itemBuilder: (_) => [
        const PopupMenuItem(value: 'edit', child: Text('编辑')),
        PopupMenuItem(
            value: 'delete',
            child: Text('删除', style: TextStyle(color: AppColors.danger))),
      ],
    );
  }

  /// 拖拽手柄：按住它才能拖动排序（避免和点击展开/菜单冲突）
  Widget _dragHandle(int index, {bool small = false}) =>
      ReorderableDragStartListener(
        index: index,
        child: Padding(
          padding: EdgeInsets.symmetric(horizontal: small ? 6 : 8),
          child: Icon(Icons.drag_indicator_rounded,
              size: small ? 18 : 20, color: AppColors.text3),
        ),
      );

  Widget _iconBox(String icon) => Container(
        width: 38,
        height: 38,
        decoration: BoxDecoration(
          color: AppColors.surfaceAlt,
          borderRadius: BorderRadius.circular(11),
        ),
        child: Center(child: Text(icon, style: const TextStyle(fontSize: 19))),
      );

  Widget _sysBadge() => Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
        decoration: BoxDecoration(
          color: AppColors.surfaceAlt,
          borderRadius: BorderRadius.circular(5),
        ),
        child: Text('系统',
            style: TextStyle(fontSize: 10, color: AppColors.text3)),
      );
}
