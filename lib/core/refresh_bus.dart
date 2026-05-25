import 'package:flutter/foundation.dart';

/// 全局刷新总线
/// 添加 / 编辑 / 删除账单或账户后调用 [bumpRefresh] ，
/// 所有订阅了的列表页会自动重新拉数据。
final ValueNotifier<int> refreshBus = ValueNotifier<int>(0);

void bumpRefresh() => refreshBus.value++;
