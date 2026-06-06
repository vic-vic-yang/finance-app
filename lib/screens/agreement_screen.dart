import 'package:flutter/material.dart';
import '../core/theme.dart';
import '../widgets/glass.dart';

/// 弹出/进入 协议页面。[privacy]=true 看隐私政策，否则服务协议。
void showAgreement(BuildContext context, {required bool privacy}) {
  Navigator.push(
    context,
    MaterialPageRoute(builder: (_) => AgreementScreen(privacy: privacy)),
  );
}

/// 服务协议 / 隐私政策 阅读页。
class AgreementScreen extends StatelessWidget {
  const AgreementScreen({super.key, required this.privacy});
  final bool privacy;

  @override
  Widget build(BuildContext context) {
    final sections = privacy ? _privacy : _terms;
    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: AuraAppBar(title: privacy ? '隐私政策' : '服务协议'),
      body: AuraBackground(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 40),
          children: [
            Text(privacy ? '司库 · 隐私政策' : '司库 · 服务协议',
                style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w700,
                    color: AppColors.text1)),
            const SizedBox(height: 4),
            Text('更新日期：2026-06-06',
                style: TextStyle(fontSize: 12, color: AppColors.text3)),
            const SizedBox(height: 18),
            for (final s in sections) ...[
              Text(s[0],
                  style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      color: AppColors.text1)),
              const SizedBox(height: 6),
              Text(s[1],
                  style: TextStyle(
                      fontSize: 13.5,
                      height: 1.75,
                      color: AppColors.text2)),
              const SizedBox(height: 18),
            ],
          ],
        ),
      ),
    );
  }
}

const List<List<String>> _terms = [
  [
    '一、协议的接受',
    '欢迎使用「司库」（以下简称"本应用"）。本协议是您与本应用之间就使用本应用各项服务所订立的协议。'
        '当您注册、登录或使用本应用时，即表示您已阅读、理解并同意本协议的全部内容。若不同意，请停止使用。',
  ],
  [
    '二、服务内容',
    '本应用为个人 / 家庭提供记账、账户与预算管理、储蓄目标、AI 智能导入、财务统计与洞察、'
        '私人 CFO 建议、财经资讯、股票信息查询与财务计算器等工具。具体功能可能随版本更新而调整。',
  ],
  [
    '三、账号与密钥',
    '您应妥善保管账号、密码与注册时生成的恢复码。由于本应用对敏感数据采用端到端加密，'
        '加密密钥由您的密码 / 恢复码派生，我们不掌握。一旦密码与恢复码同时遗失，您的加密数据将无法找回，'
        '请务必离线安全保存恢复码。',
  ],
  [
    '四、用户行为规范',
    '您承诺合法、正当地使用本应用，不得利用本应用从事任何违法违规活动，'
        '不得干扰、破坏服务的正常运行或他人的正常使用。',
  ],
  [
    '五、免责声明',
    '本应用提供的财务统计、AI 分析与建议、股票行情与基本面、分析师评级、买入建议、财经资讯等内容，'
        '均仅供您个人参考，不构成任何投资建议或专业的财务、税务、法律意见，也不保证准确、完整或及时。'
        '行情与资讯数据来自第三方公开来源，可能存在延迟或误差。您据此作出的任何决策与操作，风险由您自行承担。',
  ],
  [
    '六、服务的变更与中断',
    '本应用为自建部署，可用性取决于部署方（通常为您本人）的服务器与网络。'
        '我们不对因服务器关闭、网络中断、不可抗力等导致的服务暂停或数据丢失承担责任。',
  ],
  [
    '七、协议的更新',
    '我们可能根据功能调整不时更新本协议。更新后于应用内公布即生效，继续使用即视为接受。',
  ],
];

const List<List<String>> _privacy = [
  [
    '一、我们的隐私原则',
    '我们高度重视您的隐私。本应用在设计上即以"服务端尽量不掌握您的明文财务数据"为原则，'
        '通过端到端加密技术保护您最敏感的信息。',
  ],
  [
    '二、端到端加密',
    '您的账单备注、账户名称等敏感信息，会在您的设备本地用国密 SM 系列算法加密后才上传，'
        '服务端仅存储密文。加密所用的数据密钥由您的密码 / 恢复码派生并以信封加密方式分发，'
        '服务端与运维者均无法读取这些信息的明文。',
  ],
  [
    '三、我们处理的信息',
    '为实现记账与统计功能，本应用会存储：您的账号信息；加密后的账本、账户、账单数据；'
        '以及为完成统计 / 预算计算所必需的金额、日期、分类等字段。我们不会收集与服务无关的个人信息。',
  ],
  [
    '四、数据的存放位置',
    '本应用为自建部署，您的数据存储在您本人或管理者自有的服务器上（通常经由内网穿透对外访问），'
        '而非任何第三方商业云账户。',
  ],
  [
    '五、AI 功能与第三方模型',
    '当您使用 AI 智能导入、财务分析、对话助手、资讯富化、股票分析等功能时，相关内容会发送给'
        '所配置的大模型服务以生成结果。其中涉及您加密内容的，仅在本地解密、聚合为脱敏数据后发送，'
        '或由您主动输入的文本；我们不会将可识别您身份的明文财务数据直接交给第三方。',
  ],
  [
    '六、第三方数据来源',
    '财经资讯、股票行情与新闻来自公开的第三方来源（如 RSS、行情接口）。我们不会将您的个人财务数据'
        '出售、出租或共享给第三方用于营销目的。',
  ],
  [
    '七、您的控制权',
    '您可以随时在应用内增删改您的账单、账户与账本数据；退出登录时，本地缓存的私钥与数据密钥会被清除。'
        '您对自己的数据拥有完全的控制权。',
  ],
  [
    '八、政策更新',
    '我们可能不时更新本隐私政策，更新后于应用内公布即生效。',
  ],
];

/// 协议页脚：可点击的《服务协议》《隐私政策》。用于欢迎 / 登录 / 注册页。
class AgreementFooter extends StatelessWidget {
  const AgreementFooter({super.key, this.prefix = '继续即代表您已阅读并同意'});
  final String prefix;

  @override
  Widget build(BuildContext context) {
    final linkStyle = TextStyle(
      fontSize: 12,
      color: AppColors.primary,
      fontWeight: FontWeight.w600,
    );
    final normal = TextStyle(fontSize: 12, color: AppColors.text3, height: 1.5);
    return Wrap(
      alignment: WrapAlignment.center,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        Text(prefix, style: normal),
        GestureDetector(
          onTap: () => showAgreement(context, privacy: false),
          child: Text('《服务协议》', style: linkStyle),
        ),
        Text('和', style: normal),
        GestureDetector(
          onTap: () => showAgreement(context, privacy: true),
          child: Text('《隐私政策》', style: linkStyle),
        ),
      ],
    );
  }
}
