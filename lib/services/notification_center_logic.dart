import 'package:shared_preferences/shared_preferences.dart';

import '../models/app_notification.dart';

/// ======================================================================
/// 本地推送桥接 · 去重纯逻辑（无 Flutter UI / 插件依赖，便于单测）
/// ======================================================================
///
/// 背景：本地推送桥接在 App 启动 / 回到前台时拉一次未读通知，
/// 只对「上次检查之后新出现的未读」发系统本地通知。这里的「新」
/// 就是本文件维护的差集逻辑。

/// 从未读列表中挑出「没见过」的新通知（与已见 id 集合做差集）。
List<AppNotification> unseenUnread(
  List<AppNotification> unread,
  Set<String> seenIds,
) =>
    [for (final n in unread) if (!seenIds.contains(n.id)) n];

/// 合并已见 id 集合：加入当前页全部未读 id，并裁剪到 [cap] 条防无限增长。
/// 裁剪时优先保留当前未读 id（它们决定下一轮差集的正确性），
/// 其余按插入序从旧到新淘汰。
Set<String> mergeSeenIds(
  Set<String> seen,
  Iterable<String> currentUnreadIds, {
  int cap = 500,
}) {
  final cur = currentUnreadIds.toSet();
  final merged = <String>{...seen, ...cur};
  if (merged.length <= cap) return merged;
  var overflow = merged.length - cap;
  final result = <String>{};
  for (final id in merged) {
    if (overflow > 0 && !cur.contains(id)) {
      overflow--;
      continue; // 淘汰最旧的非当前未读 id
    }
    result.add(id);
  }
  return result;
}

/// 「已见通知 id」的本地持久化（SharedPreferences）。
///
/// 语义约定：
/// - `load()` 返回 null = 首次运行（从来没检查过）——调用方应只播种
///   当前未读 id 而不发推送，避免升级后首次启动把存量未读全弹一遍；
/// - 返回空集合 = 检查过但当时没有未读。
class SeenIdsStore {
  static const key = 'local_push_seen_notification_ids_v1';

  Future<Set<String>?> load() async {
    final sp = await SharedPreferences.getInstance();
    final list = sp.getStringList(key);
    return list?.toSet(); // null 保持 null，区分「首次」与「空」
  }

  Future<void> save(Set<String> ids) async {
    final sp = await SharedPreferences.getInstance();
    await sp.setStringList(key, ids.toList());
  }
}
