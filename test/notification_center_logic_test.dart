import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:finance_app/models/app_notification.dart';
import 'package:finance_app/services/notification_center_logic.dart';

AppNotification _n(String id, {bool unread = true}) => AppNotification(
      id: id,
      type: 'cfo_proposal',
      title: '标题$id',
      body: '正文$id',
      payload: const {'severity': 'warning'},
      readAt: unread ? null : DateTime(2025, 1, 1),
      createdAt: DateTime(2025, 1, 2),
    );

void main() {
  group('unseenUnread 差集计算', () {
    test('已见集合为空 → 全部未读都算新', () {
      final fresh = unseenUnread([_n('a'), _n('b')], {});
      expect(fresh.map((n) => n.id), ['a', 'b']);
    });

    test('已在已见集合中的 id 被过滤', () {
      final fresh = unseenUnread([_n('a'), _n('b'), _n('c')], {'a', 'c'});
      expect(fresh.map((n) => n.id), ['b']);
    });

    test('全部见过 → 空差集（不重复推送）', () {
      final fresh = unseenUnread([_n('a')], {'a'});
      expect(fresh, isEmpty);
    });

    test('未读列表为空 → 空差集', () {
      expect(unseenUnread(const [], {'a'}), isEmpty);
    });
  });

  group('mergeSeenIds 合并与裁剪', () {
    test('合并当前未读 id 进已见集合', () {
      final merged = mergeSeenIds({'a', 'b'}, ['b', 'c']);
      expect(merged, {'a', 'b', 'c'});
    });

    test('超限时优先保留当前未读 id，淘汰最旧历史', () {
      // Set 迭代序 = 插入序：old1 最先插入，应最先被淘汰
      final merged = mergeSeenIds({'old1', 'old2'}, ['cur1'], cap: 2);
      expect(merged.length, 2);
      expect(merged.contains('cur1'), isTrue);
    });

    test('未超限时原样合并', () {
      final merged = mergeSeenIds({'a'}, ['b'], cap: 500);
      expect(merged, {'a', 'b'});
    });
  });

  group('SeenIdsStore（mock SharedPreferences）', () {
    test('首次运行 load 返回 null（区分「首次」与「空」）', () async {
      SharedPreferences.setMockInitialValues({});
      final store = SeenIdsStore();
      expect(await store.load(), isNull);
    });

    test('save 后 load 往返一致', () async {
      SharedPreferences.setMockInitialValues({});
      final store = SeenIdsStore();
      await store.save({'a', 'b'});
      expect(await store.load(), {'a', 'b'});
    });

    test('保存过空集合 → load 返回空集合而非 null', () async {
      SharedPreferences.setMockInitialValues({});
      final store = SeenIdsStore();
      await store.save({});
      final loaded = await store.load();
      expect(loaded, isNotNull);
      expect(loaded, isEmpty);
    });

    test('预置脏数据被覆盖', () async {
      SharedPreferences.setMockInitialValues({
        SeenIdsStore.key: ['stale'],
      });
      final store = SeenIdsStore();
      expect(await store.load(), {'stale'});
      await store.save(mergeSeenIds({'stale'}, ['new1']));
      expect(await store.load(), {'stale', 'new1'});
    });
  });
}
