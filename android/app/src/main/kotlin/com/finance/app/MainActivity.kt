package com.finance.app

import android.content.Intent
import android.provider.Settings
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {

    companion object {
        private const val METHOD_CHANNEL = "siku/auto_bookkeeping"
        private const val EVENT_CHANNEL = "siku/auto_bookkeeping/events"
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        // ── 端侧自动记账：权限查询 / 跳系统设置 ──
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, METHOD_CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "isListenerEnabled" ->
                        result.success(isNotificationListenerEnabled())
                    "openListenerSettings" ->
                        result.success(openNotificationListenerSettings())
                    else -> result.notImplemented()
                }
            }

        // ── 端侧自动记账：通知事件流（NotificationListenerService → Dart）──
        EventChannel(flutterEngine.dartExecutor.binaryMessenger, EVENT_CHANNEL)
            .setStreamHandler(object : EventChannel.StreamHandler {
                override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
                    AutoBookkeepingListenerService.eventSink = events
                }

                override fun onCancel(arguments: Any?) {
                    AutoBookkeepingListenerService.eventSink = null
                }
            })
    }

    /** 「通知使用权」是否已授予本应用（读取系统 enabled_notification_listeners 列表） */
    private fun isNotificationListenerEnabled(): Boolean {
        val enabled = Settings.Secure.getString(
            contentResolver,
            "enabled_notification_listeners",
        ) ?: return false
        return enabled.split(':').any { it.equals(packageName, ignoreCase = true) }
    }

    /** 跳系统「通知使用权」设置页，由用户手动授权 */
    private fun openNotificationListenerSettings(): Boolean {
        return try {
            startActivity(
                Intent(Settings.ACTION_NOTIFICATION_LISTENER_SETTINGS)
                    .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK),
            )
            true
        } catch (_: Exception) {
            false
        }
    }
}
