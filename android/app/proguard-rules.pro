# ─────────────────────────────────────────────────────────────
# 财记 · Flutter Android Release ProGuard / R8 规则
# ─────────────────────────────────────────────────────────────

# ── Google ML Kit 文字识别 ────────────────────────────────────
# 我们只使用中文（已在 build.gradle 引入 text-recognition-chinese）。
# 日文 / 韩文 / 天城文未引入对应 native 依赖，
# 这里告诉 R8 不要为这些缺失类报错。
-dontwarn com.google.mlkit.vision.text.japanese.**
-dontwarn com.google.mlkit.vision.text.korean.**
-dontwarn com.google.mlkit.vision.text.devanagari.**

# 保留 ML Kit 公共接口（被 Flutter 插件通过 MethodChannel 反射调用）
-keep class com.google.mlkit.** { *; }
-keep class com.google.android.gms.internal.mlkit_vision_text_common.** { *; }

# ── flutter_secure_storage (Tink / BouncyCastle) ─────────────
-keep class com.google.crypto.tink.** { *; }
-dontwarn com.google.crypto.tink.**

# ── Flutter / Plugin 公共 keep ────────────────────────────────
-keep class io.flutter.plugin.** { *; }
-keep class io.flutter.plugins.** { *; }
