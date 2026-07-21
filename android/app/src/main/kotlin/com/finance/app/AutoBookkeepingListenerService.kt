package com.finance.app

import android.app.Notification
import android.os.Handler
import android.os.Looper
import android.service.notification.NotificationListenerService
import android.service.notification.StatusBarNotification
import io.flutter.plugin.common.EventChannel

/**
 * 端侧自动记账 · 通知监听器
 *
 * 用户手动在系统「通知使用权」设置页授权后，系统会绑定本服务并回调
 * [onNotificationPosted]。这里只抓取通知的 packageName / title / text /
 * postTime，通过 EventChannel 推给 Dart 侧做本地解析 —— 全程不联网、
 * 不上传任何通知原文，契合端到端隐私定位。
 */
class AutoBookkeepingListenerService : NotificationListenerService() {

    companion object {
        /** 由 MainActivity 的 EventChannel.StreamHandler 挂接/摘除 */
        @Volatile
        var eventSink: EventChannel.EventSink? = null

        private val mainHandler = Handler(Looper.getMainLooper())
    }

    override fun onNotificationPosted(sbn: StatusBarNotification) {
        val sink = eventSink ?: return
        // 不监听自己（避免记账成功提示被再次解析）
        if (sbn.packageName == packageName) return
        val n = sbn.notification ?: return
        // 跳过组摘要，避免与组内子通知重复计数
        if (n.flags and Notification.FLAG_GROUP_SUMMARY != 0) return
        // 跳过常驻/前台服务类通知（播放器、下载进度等，永远不会是账单）
        if (n.flags and Notification.FLAG_ONGOING_EVENT != 0) return

        val extras = n.extras
        val title = extras?.getCharSequence(Notification.EXTRA_TITLE)?.toString()
        val text = extras?.getCharSequence(Notification.EXTRA_TEXT)?.toString()
        // 展开后的完整文案优先（很多支付通知折叠态只有一行摘要）
        val bigText = extras?.getCharSequence(Notification.EXTRA_BIG_TEXT)?.toString()
        if (title.isNullOrBlank() && text.isNullOrBlank()) return

        val payload = hashMapOf<String, Any>(
            "packageName" to sbn.packageName,
            "title" to (title ?: ""),
            "text" to (bigText?.takeIf { it.isNotBlank() } ?: text ?: ""),
            "postTime" to sbn.postTime,
        )
        // EventChannel 必须在主线程回调
        mainHandler.post {
            try {
                sink.success(payload)
            } catch (_: Exception) {
                // Dart 侧已断开（页面销毁/引擎重建），静默丢弃
            }
        }
    }

    override fun onListenerDisconnected() {
        // 系统解绑（权限被收回等）：清掉 sink，等待重连
        eventSink = null
    }
}
