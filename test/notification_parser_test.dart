import 'package:flutter_test/flutter_test.dart';
import 'package:finance_app/services/notification_parser.dart';

void main() {
  const wechat = 'com.tencent.mm';
  const alipay = 'com.eg.android.AlipayGphone';
  const unionpay = 'com.unionpay';
  const cmb = 'com.cmbchina.ccd.pluto.cmbActivity'; // 招商银行
  const icbc = 'com.icbc'; // 工商银行
  const ccb = 'com.ccb.ccbhome'; // 建设银行
  const bocom = 'com.bankcomm.bankcomm'; // 交通银行
  const citic = 'com.ecitic.bank.mobile'; // 中信银行
  const pingan = 'com.pingan.paces.ccms'; // 平安银行

  final t0 = DateTime(2025, 1, 2, 12, 31); // 固定通知时间，保证测试可重复

  ParsedBillDraft? parse(String pkg, String title, String text,
          [DateTime? postTime]) =>
      NotificationParser.parse(
        packageName: pkg,
        title: title,
        text: text,
        postTime: postTime ?? t0,
      );

  group('微信支付模板', () {
    test('正例：付款凭证 → 支出 + 金额 + 收款方商户', () {
      final d = parse(wechat, '微信支付', '微信支付凭证\n付款金额 ¥35.00\n收款方 星巴克臻选店');
      expect(d, isNotNull);
      expect(d!.type, 'expense');
      expect(d.amount, 35.00);
      expect(d.merchant, '星巴克臻选店');
      expect(d.sourceApp, '微信支付');
      expect(d.time, t0); // 正文无时间 → 回退通知时间
    });

    test('正例：收款到账 → 收入', () {
      final d = parse(wechat, '微信收款助手', '收款到账 ¥12.50');
      expect(d, isNotNull);
      expect(d!.type, 'income');
      expect(d.amount, 12.50);
    });

    test('正例：转账收款到账 → 收入（不被「转账」误判为支出）', () {
      final d = parse(wechat, '微信支付', '转账收款到账通知\n收款金额 ¥200.00');
      expect(d, isNotNull);
      expect(d!.type, 'income');
      expect(d.amount, 200.00);
    });

    test('反例：积分营销通知 → null', () {
      expect(parse(wechat, '微信支付', '你的积分已到账，点击领取好礼'), isNull);
    });

    test('反例：红包待领取（无金额）→ null', () {
      expect(parse(wechat, '微信', '你有一个红包待领取'), isNull);
    });
  });

  group('支付宝模板', () {
    test('正例：付款成功 → 支出 + 交易对方', () {
      final d = parse(alipay, '支付宝', '付款成功 ¥128.00\n交易对方：物美超市');
      expect(d, isNotNull);
      expect(d!.type, 'expense');
      expect(d.amount, 128.00);
      expect(d.merchant, '物美超市');
    });

    test('正例：向商家付款（金额无 ¥ 符号）→ 支出', () {
      final d = parse(alipay, '支付宝', '你已成功向 星巴克 付款 35.00元');
      expect(d, isNotNull);
      expect(d!.type, 'expense');
      expect(d.amount, 35.00);
      expect(d.merchant, '星巴克');
    });

    test('正例：收到转账 → 收入', () {
      final d = parse(alipay, '支付宝', '你收到一笔转账 ¥66.00');
      expect(d, isNotNull);
      expect(d!.type, 'income');
      expect(d.amount, 66.00);
    });

    test('反例：蚂蚁森林能量 → null', () {
      expect(parse(alipay, '支付宝', '蚂蚁森林：你的绿色能量成熟了'), isNull);
    });

    test('反例：优惠券推送 → null', () {
      expect(parse(alipay, '支付宝', '送你 5 元优惠券，点击领取'), isNull);
    });
  });

  group('云闪付模板', () {
    test('正例：支付成功 → 支出 + 商户', () {
      final d = parse(unionpay, '云闪付', '支付成功，金额 ¥20.00，商户：家乐福');
      expect(d, isNotNull);
      expect(d!.type, 'expense');
      expect(d.amount, 20.00);
      expect(d.merchant, '家乐福');
    });

    test('反例：签到活动 → null', () {
      expect(parse(unionpay, '云闪付', '签到成功，连续签到领红包'), isNull);
    });

    test('反例：功能升级公告（无交易要素）→ null', () {
      expect(parse(unionpay, '云闪付', '银行卡管理功能已升级'), isNull);
    });
  });

  group('招商银行模板', () {
    test('正例：储蓄卡消费（含正文时间 + 余额干扰）→ 支出', () {
      final d = parse(
        cmb,
        '招商银行',
        '您尾号5476的储蓄卡01月02日12:30消费人民币35.50元，余额1,234.56元【招商银行】',
      );
      expect(d, isNotNull);
      expect(d!.type, 'expense');
      expect(d.amount, 35.50); // 取交易金额而非余额
      expect(d.time, DateTime(2025, 1, 2, 12, 30)); // 正文时间优先
    });

    test('正例：卡退款 → 收入', () {
      final d = parse(cmb, '招商银行', '您尾号5476卡退款人民币35.50元【招商银行】');
      expect(d, isNotNull);
      expect(d!.type, 'income');
      expect(d.amount, 35.50);
    });

    test('反例：额度调整（无交易）→ null', () {
      expect(parse(cmb, '招商银行', '您尾号5476卡当前可用额度已调整'), isNull);
    });

    test('反例：新客营销 → null', () {
      expect(parse(cmb, '招商银行', '新客专享福利，点击领取大礼包'), isNull);
    });
  });

  group('工商银行模板', () {
    test('正例：工资收入（千分位金额）→ 收入', () {
      final d = parse(
        icbc,
        '工商银行',
        '您尾号1234卡1月5日10:00工资收入人民币5,000.00元，余额8,000.00元。【工商银行】',
        DateTime(2025, 1, 5, 10, 5),
      );
      expect(d, isNotNull);
      expect(d!.type, 'income');
      expect(d.amount, 5000.00);
      expect(d.time, DateTime(2025, 1, 5, 10, 0));
    });

    test('反例：仅余额提醒（无方向词）→ null', () {
      expect(parse(icbc, '工商银行', '您尾号1234卡余额为8,000.00元'), isNull);
    });

    test('反例：积分过期营销 → null', () {
      expect(parse(icbc, '工商银行', '您的积分即将过期，点击领取好礼'), isNull);
    });
  });

  group('建设银行模板', () {
    test('正例：支出（X时X分时间格式）→ 支出', () {
      final d = parse(
        ccb,
        '建设银行',
        '您尾号8888的储蓄卡2月3日8时15分支出人民币99.00元【建设银行】',
        DateTime(2025, 2, 3, 8, 20),
      );
      expect(d, isNotNull);
      expect(d!.type, 'expense');
      expect(d.amount, 99.00);
      expect(d.time, DateTime(2025, 2, 3, 8, 15));
    });

    test('反例：验证码类通知 → null', () {
      expect(parse(ccb, '建设银行', '您尾号8888卡于2月3日动态密码验证成功'), isNull);
    });

    test('反例：抽奖活动 → null', () {
      expect(parse(ccb, '建设银行', '抽奖活动开始啦，快来参与'), isNull);
    });
  });

  group('交通银行模板', () {
    test('正例：在 XX 消费 → 支出 + 商户', () {
      final d = parse(
        bocom,
        '交通银行',
        '您尾号6666卡于01月10日在京东商城消费人民币1,299.00元',
      );
      expect(d, isNotNull);
      expect(d!.type, 'expense');
      expect(d.amount, 1299.00);
      expect(d.merchant, '京东商城');
    });

    test('反例：信用卡账单应还提醒 → null', () {
      expect(parse(bocom, '交通银行', '您的信用卡账单已出，本期应还 1,299.00 元'), isNull);
    });

    test('反例：提额邀请 → null', () {
      expect(parse(bocom, '交通银行', '提额邀请：您的额度可提升至50000元'), isNull);
    });
  });

  group('中信银行模板', () {
    test('正例：信用卡消费 → 支出', () {
      final d = parse(
        citic,
        '中信银行',
        '您尾号3333的信用卡于01月15日19:45消费人民币88.00元【中信银行】',
        DateTime(2025, 1, 15, 19, 50),
      );
      expect(d, isNotNull);
      expect(d!.type, 'expense');
      expect(d.amount, 88.00);
      expect(d.time, DateTime(2025, 1, 15, 19, 45));
    });

    test('反例：网点预约确认 → null', () {
      expect(parse(citic, '中信银行', '尊敬的客户，您预约的网点服务已确认'), isNull);
    });

    test('反例：立减金营销 → null', () {
      expect(parse(citic, '中信银行', '送你10元立减金，点击领取'), isNull);
    });
  });

  group('平安银行模板', () {
    test('正例：转入 → 收入', () {
      final d = parse(
        pingan,
        '平安银行',
        '您尾号9999卡1月20日12:00转入人民币2,000.00元，余额5,000.00元【平安银行】',
      );
      expect(d, isNotNull);
      expect(d!.type, 'income');
      expect(d.amount, 2000.00);
    });

    test('反例：到期提醒（无交易要素）→ null', () {
      expect(parse(pingan, '平安银行', '您尾号9999卡的保单服务即将到期'), isNull);
    });

    test('反例：金币商城营销 → null', () {
      expect(parse(pingan, '平安银行', '金币商城上新，点击领取'), isNull);
    });
  });

  group('通用行为', () {
    test('非白名单包名 → null（即使文案像账单）', () {
      expect(
        parse('com.foo.bar', '某应用', '付款成功 ¥35.00'),
        isNull,
      );
    });

    test('金额千分位 + ¥ 符号解析', () {
      final d = parse(wechat, '微信支付', '付款金额 ¥1,234.56\n收款方 某商场');
      expect(d, isNotNull);
      expect(d!.amount, 1234.56);
    });

    test('超大金额（卡号级数字）拒绝解析', () {
      expect(
        parse(cmb, '招商银行', '您尾号5476卡消费人民币12345678901234元'),
        isNull,
      );
    });

    test('指纹：包名+金额+分钟级时间，秒内抖动不重复、跨分钟可区分', () {
      final base = DateTime(2025, 1, 2, 12, 30, 10);
      final fp1 = NotificationParser.fingerprint(wechat, 35.0, base);
      final fpSameMinute =
          NotificationParser.fingerprint(wechat, 35.0, DateTime(2025, 1, 2, 12, 30, 45));
      final fpNextMinute =
          NotificationParser.fingerprint(wechat, 35.0, DateTime(2025, 1, 2, 12, 31, 0));
      final fpOtherAmount =
          NotificationParser.fingerprint(wechat, 36.0, base);
      expect(fp1, startsWith('com.tencent.mm|35.00|'));
      expect(fp1, fpSameMinute); // 同分钟 = 同一笔
      expect(fp1 == fpNextMinute, isFalse);
      expect(fp1 == fpOtherAmount, isFalse);
    });

    test('同一通知解析两次指纹一致（去重前提）', () {
      final a = parse(wechat, '微信支付', '付款金额 ¥35.00\n收款方 某店');
      final b = parse(wechat, '微信支付', '付款金额 ¥35.00\n收款方 某店');
      expect(a, isNotNull);
      expect(b, isNotNull);
      expect(a!.fingerprint, b!.fingerprint);
    });

    test('正文跨年：12月底的通知在1月收到 → 时间回退一年', () {
      final d = parse(
        cmb,
        '招商银行',
        '您尾号5476卡12月31日23:58消费人民币99.00元【招商银行】',
        DateTime(2025, 1, 1, 0, 5),
      );
      expect(d, isNotNull);
      expect(d!.time, DateTime(2024, 12, 31, 23, 58));
    });
  });

  group('分类智能默认', () {
    ParsedBillDraft draft(String merchant, String raw,
            {String type = 'expense'}) =>
        ParsedBillDraft(
          packageName: wechat,
          sourceApp: '微信支付',
          amount: 1,
          type: type,
          merchant: merchant,
          time: t0,
          rawText: raw,
          fingerprint: 'fp',
        );

    test('餐饮 / 购物 / 交通关键词', () {
      expect(NotificationParser.suggestCategory(draft('星巴克臻选店', '')), '餐饮');
      expect(NotificationParser.suggestCategory(draft('物美超市', '')), '购物');
      expect(NotificationParser.suggestCategory(draft('滴滴出行', '')), '交通');
    });

    test('转账 / 工资关键词', () {
      expect(NotificationParser.suggestCategory(draft('', '转账收款到账通知')), '转账');
      expect(
        NotificationParser.suggestCategory(draft('某某公司', '工资收入', type: 'income')),
        '工资',
      );
    });

    test('无关键词 → null', () {
      expect(NotificationParser.suggestCategory(draft('神秘商户甲乙丙', '收款到账')), isNull);
    });
  });

  group('草稿 JSON 序列化', () {
    test('toJson → fromJson 往返一致', () {
      final d = parse(wechat, '微信支付', '付款金额 ¥35.00\n收款方 星巴克臻选店')!;
      final restored = ParsedBillDraft.fromJson(d.toJson());
      expect(restored.packageName, d.packageName);
      expect(restored.sourceApp, d.sourceApp);
      expect(restored.amount, d.amount);
      expect(restored.type, d.type);
      expect(restored.merchant, d.merchant);
      expect(restored.time, d.time);
      expect(restored.rawText, d.rawText);
      expect(restored.fingerprint, d.fingerprint);
    });

    test('decodeList 对脏数据健壮', () {
      expect(ParsedBillDraft.decodeList(null), isEmpty);
      expect(ParsedBillDraft.decodeList(''), isEmpty);
      expect(ParsedBillDraft.decodeList('not json'), isEmpty);
      expect(ParsedBillDraft.decodeList('{"a":1}'), isEmpty);
      expect(ParsedBillDraft.decodeList('[{"bad":"data"}]'), isEmpty);
    });

    test('encodeList / decodeList 往返', () {
      final d = parse(wechat, '微信支付', '付款金额 ¥35.00\n收款方 星巴克臻选店')!;
      final list = ParsedBillDraft.decodeList(ParsedBillDraft.encodeList([d]));
      expect(list.length, 1);
      expect(list.first.fingerprint, d.fingerprint);
    });
  });
}
