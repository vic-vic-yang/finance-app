import 'package:flutter/material.dart';

import '../core/theme.dart';
import 'siku_ui.dart';

/// 时机式功能发现卡片的内容模型。
class FeatureDiscoveryCardData {
  const FeatureDiscoveryCardData({
    required this.emoji,
    required this.title,
    required this.message,
    this.goLabel = '去看看',
  });

  /// 前缀 emoji（一个字符，与智能管家入口同语言）
  final String emoji;

  /// 一句话价值主张（标题）
  final String title;

  /// 一句补充说明
  final String message;

  /// 「去看看」按钮文案
  final String goLabel;
}

/// 时机式功能发现的轻量底部卡片（由 FeatureDiscoveryService.maybeShow
/// 以 floating SnackBar 承载，非全屏、不阻塞操作）。
///
/// 视觉遵循 Aura：GlassCard 承载 + surfaceAlt emoji 容器 + primary 描边
/// 小胶囊「去看看」+ text3「知道了」；入场动画直接复用 SnackBar 自身的
/// 上滑，克制不另做。
class FeatureDiscoveryCard extends StatelessWidget {
  const FeatureDiscoveryCard({
    super.key,
    required this.data,
    this.onGo,
    this.onDismiss,
  });

  final FeatureDiscoveryCardData data;

  /// 「去看看」回调（service 已先关卡片，这里只做跳转）
  final VoidCallback? onGo;

  /// 「知道了」关闭回调
  final VoidCallback? onDismiss;

  @override
  Widget build(BuildContext context) {
    return GlassCard(
      radius: 16,
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  color: AppColors.surfaceAlt,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Center(
                  child: Text(data.emoji, style: const TextStyle(fontSize: 17)),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      data.title,
                      style: TextStyle(
                        fontSize: 13.5,
                        fontWeight: FontWeight.w600,
                        color: AppColors.text1,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      data.message,
                      style: TextStyle(
                        fontSize: 12,
                        color: AppColors.text2,
                        height: 1.35,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              GestureDetector(
                onTap: onDismiss,
                behavior: HitTestBehavior.opaque,
                child: Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  child: Text(
                    '知道了',
                    style: TextStyle(fontSize: 12, color: AppColors.text3),
                  ),
                ),
              ),
              if (onGo != null) ...[
                const SizedBox(width: 6),
                GestureDetector(
                  onTap: onGo,
                  behavior: HitTestBehavior.opaque,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 5),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(
                          color:
                              AppColors.primary.withValues(alpha: 0.45)),
                    ),
                    child: Text(
                      data.goLabel,
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: AppColors.primary,
                      ),
                    ),
                  ),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }
}
