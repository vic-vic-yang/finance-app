import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../services/api_service.dart';
import 'app_version.dart';
import 'theme.dart';

/// App 自助升级检查：比对后端 /app/version 的 buildNumber 与本地 [kAppBuildNumber]，
/// 有新版则弹更新提示，「立即更新」用浏览器下载安装包（自建服务器）。
class UpdateChecker {
  static bool _checkedThisLaunch = false;

  /// [manual] = true 为用户手动点「检查更新」（会提示"已是最新"），自动检查则静默。
  static Future<void> check(BuildContext context, {bool manual = false}) async {
    if (!manual && _checkedThisLaunch) return;
    _checkedThisLaunch = true;
    try {
      final res = await ApiService.getAppVersion();
      final serverBuild = (res['buildNumber'] as num?)?.toInt() ?? 0;
      final serverVersion = (res['version'] as String?) ?? '';
      final notes = (res['notes'] as String?) ?? '';
      final hasApk = res['apkFile'] != null;
      if (serverBuild > kAppBuildNumber && hasApk) {
        if (context.mounted) _showDialog(context, serverVersion, notes);
      } else if (manual && context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('已是最新版本')),
        );
      }
    } catch (_) {
      if (manual && context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('检查更新失败，请稍后再试')),
        );
      }
    }
  }

  static void _showDialog(BuildContext context, String version, String notes) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(children: [
          Icon(Icons.system_update_rounded, color: AppColors.primary, size: 22),
          const SizedBox(width: 8),
          Expanded(child: Text('发现新版本 v$version')),
        ]),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              notes.trim().isNotEmpty ? notes : '有新版本可用，建议更新到最新。',
              style: TextStyle(fontSize: 13, color: AppColors.text2, height: 1.55),
            ),
            const SizedBox(height: 10),
            Text('当前 v$kAppVersion  →  新版 v$version',
                style: TextStyle(fontSize: 12, color: AppColors.text3)),
            const SizedBox(height: 6),
            Text('点「立即更新」会用浏览器下载安装包，下载完点开安装即可。',
                style: TextStyle(fontSize: 11.5, color: AppColors.text3, height: 1.5)),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text('稍后', style: TextStyle(color: AppColors.text2)),
          ),
          TextButton(
            onPressed: () async {
              Navigator.pop(ctx);
              final uri = Uri.parse(ApiService.appDownloadUrl);
              for (final mode in [
                LaunchMode.externalApplication,
                LaunchMode.platformDefault,
              ]) {
                try {
                  if (await launchUrl(uri, mode: mode)) return;
                } catch (_) {/* 试下一种 */}
              }
            },
            child: Text('立即更新',
                style: TextStyle(
                    color: AppColors.primary, fontWeight: FontWeight.w700)),
          ),
        ],
      ),
    );
  }
}
