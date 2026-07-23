import 'package:flutter_test/flutter_test.dart';
import 'package:finance_app/core/refresh_bus.dart';

/// 刷新总线（refreshBus / bumpRefresh）联动测试。
/// 它是全局单例 ValueNotifier，每个用例先归零，避免相互污染。
void main() {
  setUp(() {
    refreshBus.value = 0;
  });

  test('bump 后监听者收到通知，且计数递增', () {
    var calls = 0;
    void listener() => calls++;
    refreshBus.addListener(listener);

    bumpRefresh();

    expect(calls, 1);
    expect(refreshBus.value, 1);

    refreshBus.removeListener(listener);
  });

  test('连续多次 bump 不丢：通知次数与值严格等于 bump 次数', () {
    var calls = 0;
    void listener() => calls++;
    refreshBus.addListener(listener);

    for (var i = 0; i < 5; i++) {
      bumpRefresh();
    }

    expect(calls, 5);
    expect(refreshBus.value, 5);

    refreshBus.removeListener(listener);
  });

  test('removeListener 之后 bump 不再触发', () {
    var calls = 0;
    void listener() => calls++;
    refreshBus.addListener(listener);

    bumpRefresh();
    expect(calls, 1);

    refreshBus.removeListener(listener);
    bumpRefresh();
    bumpRefresh();

    expect(calls, 1); // 没有新增
    expect(refreshBus.value, 3); // 值仍然递增（总线本身不受移除影响）
  });

  test('多个监听者都会收到同一次 bump', () {
    var callsA = 0;
    var callsB = 0;
    void listenerA() => callsA++;
    void listenerB() => callsB++;
    refreshBus
      ..addListener(listenerA)
      ..addListener(listenerB);

    bumpRefresh();

    expect(callsA, 1);
    expect(callsB, 1);

    refreshBus
      ..removeListener(listenerA)
      ..removeListener(listenerB);
  });

  test('移除一个监听者不影响其它监听者', () {
    var callsA = 0;
    var callsB = 0;
    void listenerA() => callsA++;
    void listenerB() => callsB++;
    refreshBus
      ..addListener(listenerA)
      ..addListener(listenerB);

    refreshBus.removeListener(listenerA);
    bumpRefresh();

    expect(callsA, 0);
    expect(callsB, 1);

    refreshBus.removeListener(listenerB);
  });
}
