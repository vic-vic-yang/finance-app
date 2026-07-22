import 'dart:async';
import 'dart:convert';
import 'dart:io' show HttpClient;
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:http/http.dart' as http;
import 'package:http/io_client.dart';
import 'auth_service.dart';
import 'llm_config_service.dart';

/// 后端返回非 2xx 状态码时抛出，让既有的 try/catch 能感知真实错误
/// （此前 helper 只是 jsonDecode(body)，4xx/5xx 错误体被当成功返回）
class ApiException implements Exception {
  final int statusCode;
  final String message;
  ApiException(this.statusCode, this.message);
  @override
  String toString() => message;
}

class ApiService {
  // ─── 后端地址配置 ─────────────────────────────────────────
  // 公网：通过 Cloudflare Tunnel 暴露，无需开端口、无需公网 IP
  //   架构：手机 -> finance.equitick.top (CF 边缘) -> Tunnel -> 你电脑 :3000
  // 本机调试 Web 时仍用 localhost
  static const String _publicHost = 'https://finance.equitick.top/api';

  static const String baseUrl = kIsWeb
      ? 'http://localhost:3000/api'
      : _publicHost;

  /// 单例 HTTP Client —— 连接保活 + TLS 复用，消除每次请求 1.5+ 秒的 TLS 握手
  ///
  /// 原因：`http.post()` 顶层方法内部 new Client + 发请求 + close()，
  ///       每次都要重新 TCP+TLS。改用长存 Client 后，第一次请求建好 TLS，
  ///       之后所有请求共用同一个 connection（最长 idle 由 maxConnectionsPerHost 控制）。
  static final http.Client _client = () {
    if (kIsWeb) return http.Client(); // Web 平台没 dart:io
    final inner = HttpClient()
      ..connectionTimeout = const Duration(seconds: 8)
      ..idleTimeout = const Duration(seconds: 60)
      ..maxConnectionsPerHost = 6;
    return IOClient(inner);
  }();

  /// 所有请求超时：避免后端卡死时 spinner 转到天荒地老
  static const _kRequestTimeout = Duration(seconds: 20);

  /// 解码响应；非 2xx 抛 [ApiException]。2xx 时返回解析后的 body（可能为 null）。
  static dynamic _decode(http.Response res) {
    dynamic body;
    try {
      body = res.body.isEmpty ? null : jsonDecode(res.body);
    } catch (_) {
      body = null;
    }
    if (res.statusCode >= 200 && res.statusCode < 300) return body;
    String msg = '请求失败 (${res.statusCode})';
    if (body is Map) {
      final m = body['message'];
      if (m is String && m.trim().isNotEmpty) {
        msg = m;
      } else if (m is List && m.isNotEmpty) {
        msg = m.join('，');
      }
    }
    throw ApiException(res.statusCode, msg);
  }

  static Future<Map<String, String>> _headers() async {
    final token = await AuthService.getToken();
    return {
      'Content-Type': 'application/json',
      if (token != null) 'Authorization': 'Bearer $token',
      // BYOK：配置了个人模型则所有请求带上（服务端仅 AI 接口读取，过手不落库）
      ...LlmConfigService.instance.headers(),
    };
  }

  static Future<Map<String, dynamic>> _get(
    String path, {
    Map<String, String>? params,
  }) async {
    final uri =
        Uri.parse('$baseUrl$path').replace(queryParameters: params);
    final res =
        await _client.get(uri, headers: await _headers()).timeout(_kRequestTimeout);
    final body = _decode(res);
    return (body is Map) ? body.cast<String, dynamic>() : <String, dynamic>{};
  }

  /// 像 [_get] 但不强制把响应转成 Map —— 用于返回 JSON 数组的端点
  /// （如 GET /cfo/proposals 直接返回一个 proposal 数组）。
  static Future<dynamic> _getRaw(
    String path, {
    Map<String, String>? params,
  }) async {
    final uri = Uri.parse('$baseUrl$path').replace(queryParameters: params);
    final res = await _client
        .get(uri, headers: await _headers())
        .timeout(_kRequestTimeout);
    return _decode(res);
  }

  static Future<Map<String, dynamic>> _post(
    String path,
    Map<String, dynamic> body, {
    Duration? timeout,
    Map<String, String>? extraHeaders,
  }) async {
    final res = await _client
        .post(
          Uri.parse('$baseUrl$path'),
          headers: {...await _headers(), ...?extraHeaders},
          body: jsonEncode(body),
        )
        .timeout(timeout ?? _kRequestTimeout);
    final decoded = _decode(res);
    return (decoded is Map) ? decoded.cast<String, dynamic>() : <String, dynamic>{};
  }

  static Future<Map<String, dynamic>> _put(
    String path,
    Map<String, dynamic> body,
  ) async {
    final res = await _client
        .put(
          Uri.parse('$baseUrl$path'),
          headers: await _headers(),
          body: jsonEncode(body),
        )
        .timeout(_kRequestTimeout);
    final decoded = _decode(res);
    return (decoded is Map) ? decoded.cast<String, dynamic>() : <String, dynamic>{};
  }

  static Future<Map<String, dynamic>> _patch(
    String path,
    Map<String, dynamic> body,
  ) async {
    final res = await _client
        .patch(
          Uri.parse('$baseUrl$path'),
          headers: await _headers(),
          body: jsonEncode(body),
        )
        .timeout(_kRequestTimeout);
    final decoded = _decode(res);
    return (decoded is Map) ? decoded.cast<String, dynamic>() : <String, dynamic>{};
  }

  static Future<Map<String, dynamic>> _delete(String path) async {
    final res = await _client
        .delete(Uri.parse('$baseUrl$path'), headers: await _headers())
        .timeout(_kRequestTimeout);
    final body = _decode(res);
    return (body is Map) ? body.cast<String, dynamic>() : <String, dynamic>{};
  }

  /// 应用启动后调一次：预热 TLS 连接，让用户后续登录第一次请求就走快路
  /// 失败静默（说明后端暂时不可达，登录时会再报错）
  static Future<void> prewarm() async {
    if (kIsWeb) return;
    try {
      await _client
          .get(Uri.parse('$baseUrl/auth/me'))
          .timeout(const Duration(seconds: 6));
    } catch (_) {/* 静默 */}
  }

  // ── BYOK：账本共享 LLM 配置 ────────────────────────────────
  /// 当前账本共享配置视图（不含 Key）+ 是否允许用服务端默认
  static Future<Map<String, dynamic>> getLlmConfig() => _get('/ai/llm-config');

  /// 保存/更新账本共享配置（apiKey 不传=保留服务器上现有的）
  static Future<Map<String, dynamic>> putLlmConfig({
    required String provider,
    required String baseUrl,
    required String modelId,
    String? visionModelId,
    String? apiKey,
  }) =>
      _post('/ai/llm-config', {
        'provider': provider,
        'baseUrl': baseUrl,
        'modelId': modelId,
        if (visionModelId != null) 'visionModelId': visionModelId,
        if (apiKey != null && apiKey.isNotEmpty) 'apiKey': apiKey,
      });

  static Future<Map<String, dynamic>> deleteLlmConfig() =>
      _delete('/ai/llm-config');

  /// 按 ①个人 ②账本 ③服务端 顺序解析并发一条微请求验证连通性。
  /// 传 [override] 则用这套（未保存的）表单配置直接测，不影响已保存的配置。
  static Future<Map<String, dynamic>> testLlm({PersonalLlmConfig? override}) =>
      _post('/ai/llm-config/test', {},
          timeout: const Duration(seconds: 30),
          extraHeaders:
              override != null ? LlmConfigService.headersOf(override) : null);

  // ── Auth ──────────────────────────────────────────────────
  static Future<Map<String, dynamic>> login(
      String username, String password) async {
    final data = await _post('/auth/login',
        {'username': username, 'password': password});
    if (data['token'] != null) {
      await AuthService.saveAuth(data['token'], data['user']);
    }
    return data;
  }

  /// 注册：客户端必须已经预生成密钥包（参见 lib/crypto/crypto_bootstrap.dart）
  static Future<Map<String, dynamic>> register({
    required String username,
    required String password,
    required String sm2PubKey,
    required String sm2PrivByPwd,
    required String sm2PrivByRecovery,
    required String kdfSalt,
    required String recoveryHash,
    required String personalLedgerDekWrapped,
  }) async {
    final data = await _post('/auth/register', {
      'username': username,
      'password': password,
      'sm2PubKey': sm2PubKey,
      'sm2PrivByPwd': sm2PrivByPwd,
      'sm2PrivByRecovery': sm2PrivByRecovery,
      'kdfSalt': kdfSalt,
      'recoveryHash': recoveryHash,
      'personalLedgerDekWrapped': personalLedgerDekWrapped,
    });
    if (data['token'] != null) {
      await AuthService.saveAuth(data['token'], data['user']);
    }
    return data;
  }

  /// 修改密码（登录态）
  /// 客户端必须先把 sm2PrivByPwd 用新密码 KDF 重新加密
  static Future<Map<String, dynamic>> changePassword({
    required String oldPassword,
    required String newPassword,
    required String sm2PrivByPwd,
  }) =>
      _post('/auth/change-password', {
        'oldPassword': oldPassword,
        'newPassword': newPassword,
        'sm2PrivByPwd': sm2PrivByPwd,
      });

  /// 忘密码第一步：服务端返回 salt + 恢复码加密的 privKey 密文
  static Future<Map<String, dynamic>> recoverStart(String username) =>
      _post('/auth/recover/start', {'username': username});

  /// 忘密码第二步：服务端验证恢复码 → 改 bcrypt → 自动登录
  static Future<Map<String, dynamic>> recoverFinish({
    required String username,
    required String recoveryCode,
    required String newPassword,
    required String sm2PrivByPwd,
  }) async {
    final data = await _post('/auth/recover/finish', {
      'username': username,
      'recoveryCode': recoveryCode,
      'newPassword': newPassword,
      'sm2PrivByPwd': sm2PrivByPwd,
    });
    if (data['token'] != null) {
      await AuthService.saveAuth(data['token'], data['user']);
    }
    return data;
  }

  /// 拉取当前用户资料（含昵称）
  static Future<Map<String, dynamic>> getMe() => _get('/auth/me');

  /// VIP 状态查询
  static Future<Map<String, dynamic>> getVipStatus() => _get('/auth/vip-status');

  /// 修改昵称（传空串/null 都视为清除）
  static Future<Map<String, dynamic>> updateProfile({String? nickname}) async {
    final data = await _patch('/auth/me', {
      if (nickname != null) 'nickname': nickname,
    });
    if (data['user'] is Map<String, dynamic>) {
      // 同步本地缓存
      final cur = await AuthService.getUser() ?? {};
      cur['nickname'] = data['user']['nickname'];
      cur['username'] = data['user']['username'];
      cur['id'] = data['user']['id'];
      await AuthService.saveUser(cur);
    }
    return data;
  }

  // ── Accounts ──────────────────────────────────────────────
  /// 列出当前账本下的账户。
  /// - 默认 scope=null：只返回当前用户可用的账户（共享 + 自己的私人）
  /// - scope='all'：返回账本下全部账户（含其他成员私人账户，余额不可见），
  ///                用于转账目的地选择
  static Future<Map<String, dynamic>> getAccounts({String? scope}) =>
      _get('/accounts',
          params: scope == null ? null : {'scope': scope});

  static Future<Map<String, dynamic>> createAccount({
    required String nameCipher,
    required int nameDekVer,
    required String type,
    double initialBalance = 0,
    bool isShared = false,
    int? statementDay,
    int? dueDay,
    double? creditLimit,
    double? interestRate,
    double? loanPrincipal,
    int? loanTermMonths,
    String? firstPaymentDate, // YYYY-MM-DD
    String? repaymentMethod,
    int? autoDepositDay,
    double? autoDepositAmount,
    String? autoDepositCategoryId,
  }) =>
      _post('/accounts', {
        'nameCipher': nameCipher,
        'nameDekVer': nameDekVer,
        'type': type,
        'initialBalance': initialBalance,
        'isShared': isShared,
        if (statementDay != null) 'statementDay': statementDay,
        if (dueDay != null) 'dueDay': dueDay,
        if (creditLimit != null) 'creditLimit': creditLimit,
        if (interestRate != null) 'interestRate': interestRate,
        if (loanPrincipal != null) 'loanPrincipal': loanPrincipal,
        if (loanTermMonths != null) 'loanTermMonths': loanTermMonths,
        if (firstPaymentDate != null)
          'firstPaymentDate': firstPaymentDate,
        if (repaymentMethod != null)
          'repaymentMethod': repaymentMethod,
        if (autoDepositDay != null) 'autoDepositDay': autoDepositDay,
        if (autoDepositAmount != null)
          'autoDepositAmount': autoDepositAmount,
        if (autoDepositCategoryId != null)
          'autoDepositCategoryId': autoDepositCategoryId,
      });

  static Future<Map<String, dynamic>> updateAccount(
          String id, Map<String, dynamic> data) =>
      _patch('/accounts/$id', data);

  static Future<Map<String, dynamic>> deleteAccount(String id) =>
      _delete('/accounts/$id');

  static Future<Map<String, dynamic>> transfer({
    required String fromAccountId,
    required String toAccountId,
    required double amount,
    String? note,
    String? fromNoteCipher,
    String? toNoteCipher,
    int? noteDekVer,
  }) =>
      _post('/accounts/transfer', {
        'fromAccountId': fromAccountId,
        'toAccountId': toAccountId,
        'amount': amount,
        if (note != null && note.isNotEmpty) 'note': note,
        if (fromNoteCipher != null) 'fromNoteCipher': fromNoteCipher,
        if (toNoteCipher != null) 'toNoteCipher': toNoteCipher,
        if (noteDekVer != null) 'noteDekVer': noteDekVer,
      });

  static Future<Map<String, dynamic>> reconcileAccount({
    required String id,
    required double actualBalance,
    String? noteCipher,
    int? noteDekVer,
  }) =>
      _post('/accounts/$id/reconcile', {
        'actualBalance': actualBalance,
        if (noteCipher != null) 'noteCipher': noteCipher,
        if (noteDekVer != null) 'noteDekVer': noteDekVer,
      });

  // ── Categories ────────────────────────────────────────────
  static Future<Map<String, dynamic>> getCategories() => _get('/categories');

  /// 创建自建分类（仅在当前账本生效）。
  /// - parentId 为 null：一级分类
  /// - parentId 非空：二级分类，必须与父分类 type 相同
  static Future<Map<String, dynamic>> createCategory({
    required String name,
    required String type,
    String? icon,
    String? color,
    String? parentId,
  }) =>
      _post('/categories', {
        'name': name,
        'type': type,
        if (icon != null && icon.isNotEmpty) 'icon': icon,
        if (color != null && color.isNotEmpty) 'color': color,
        if (parentId != null) 'parentId': parentId,
      });

  static Future<Map<String, dynamic>> updateCategory(
    String id, {
    String? name,
    String? icon,
    String? color,
  }) =>
      _patch('/categories/$id', {
        if (name != null) 'name': name,
        if (icon != null) 'icon': icon,
        if (color != null) 'color': color,
      });

  static Future<Map<String, dynamic>> deleteCategory(String id) =>
      _delete('/categories/$id');

  /// 保存某同级分组的自定义排序（orderedIds 为按展示顺序排好的分类 id）
  static Future<Map<String, dynamic>> reorderCategories(
          List<String> orderedIds) =>
      _patch('/categories/reorder', {'orderedIds': orderedIds});

  // ── Bills ─────────────────────────────────────────────────
  static Future<Map<String, dynamic>> getBills({
    int page = 1,
    int limit = 20,
    String? type,
    String? categoryId,
    List<String>? categoryIds,
    String? accountId,
    List<String>? accountIds,
    String? userId,
    List<String>? userIds,
    String? startDate,
    String? endDate,
    double? minAmount,
    double? maxAmount,
    String? isTransfer,
    String? source,
    String? includeStock,
  }) =>
      _get('/bills', params: {
        'page': page.toString(),
        'limit': limit.toString(),
        if (type != null) 'type': type,
        if (categoryId != null) 'categoryId': categoryId,
        if (categoryIds != null && categoryIds.isNotEmpty)
          'categoryIds': categoryIds.join(','),
        if (accountId != null) 'accountId': accountId,
        if (accountIds != null && accountIds.isNotEmpty)
          'accountIds': accountIds.join(','),
        if (userId != null) 'userId': userId,
        if (userIds != null && userIds.isNotEmpty)
          'userIds': userIds.join(','),
        if (startDate != null) 'startDate': startDate,
        if (endDate != null) 'endDate': endDate,
        if (minAmount != null) 'minAmount': minAmount.toString(),
        if (maxAmount != null) 'maxAmount': maxAmount.toString(),
        if (isTransfer != null) 'isTransfer': isTransfer,
        if (source != null) 'source': source,
        if (includeStock != null) 'includeStock': includeStock,
      });

  static Future<Map<String, dynamic>> createBill({
    required String type,
    required double amount,
    required String categoryId,
    required String accountId,
    required String noteCipher,
    required int noteDekVer,
    DateTime? date,
  }) =>
      _post('/bills', {
        'type': type,
        'amount': amount,
        'categoryId': categoryId,
        'accountId': accountId,
        'noteCipher': noteCipher,
        'noteDekVer': noteDekVer,
        'date': (date ?? DateTime.now()).toIso8601String(),
      });

  static Future<Map<String, dynamic>> getBill(String id) => _get('/bills/$id');

  static Future<Map<String, dynamic>> updateBill(
    String id, {
    required String type,
    required double amount,
    required String categoryId,
    required String accountId,
    required String noteCipher,
    required int noteDekVer,
    DateTime? date,
    /// 仅编辑转账账单(isTransfer)时传：配对腿的目标账户 id
    String? toAccountId,
  }) =>
      _put('/bills/$id', {
        'type': type,
        'amount': amount,
        'categoryId': categoryId,
        'accountId': accountId,
        'noteCipher': noteCipher,
        'noteDekVer': noteDekVer,
        'date': (date ?? DateTime.now()).toIso8601String(),
        if (toAccountId != null) 'toAccountId': toAccountId,
      });

  static Future<Map<String, dynamic>> deleteBill(String id) =>
      _delete('/bills/$id');

  // ── Stats ─────────────────────────────────────────────────
  static Future<Map<String, dynamic>> getStats({
    String? startDate,
    String? endDate,
  }) =>
      _get('/stats', params: {
        if (startDate != null) 'startDate': startDate,
        if (endDate != null) 'endDate': endDate,
      });

  // ── Budgets ───────────────────────────────────────────────
  static Future<Map<String, dynamic>> getBudgets() => _get('/budgets');

  /// 历史执行：最近 [count] 个周期。period = MONTHLY / YEARLY
  static Future<Map<String, dynamic>> getBudgetHistory({
    String period = 'MONTHLY',
    int count = 12,
  }) =>
      _get('/budgets/history', params: {
        'period': period,
        'count': count.toString(),
      });

  static Future<Map<String, dynamic>> createBudget({
    String? categoryId,
    required double amount,
    required String period,
    required String startDate,
  }) =>
      _post('/budgets', {
        if (categoryId != null) 'categoryId': categoryId,
        'amount': amount,
        'period': period,
        'startDate': startDate,
      });

  static Future<Map<String, dynamic>> updateBudget(
    String id, {
    double? amount,
    String? period,
    String? categoryId,
  }) =>
      _patch('/budgets/$id', {
        if (amount != null) 'amount': amount,
        if (period != null) 'period': period,
        if (categoryId != null) 'categoryId': categoryId,
      });

  static Future<Map<String, dynamic>> deleteBudget(String id) =>
      _delete('/budgets/$id');

  // ── Ledgers ───────────────────────────────────────────────
  static Future<Map<String, dynamic>> getLedgers() => _get('/ledgers');

  static Future<Map<String, dynamic>> createLedger({
    required String name,
    required String dekWrapped,
    String? icon,
  }) =>
      _post('/ledgers', {
        'name': name,
        'dekWrapped': dekWrapped,
        if (icon != null) 'icon': icon,
      });

  /// 拉取我在所有账本里的 dekWrapped（登录后调一次）
  static Future<Map<String, dynamic>> getMyDeks() =>
      _get('/ledgers/keys/mine');

  /// 列出该账本里"还没拿到 DEK"的待授权成员
  static Future<Map<String, dynamic>> getPendingMembers(String ledgerId) =>
      _get('/ledgers/$ledgerId/pending-members');

  /// 把"给某成员包装好的 DEK"上传
  static Future<Map<String, dynamic>> attachDek(
    String ledgerId,
    String memberUserId, {
    required String dekWrapped,
    required int dekVersion,
  }) =>
      _post('/ledgers/$ledgerId/members/$memberUserId/dek', {
        'dekWrapped': dekWrapped,
        'dekVersion': dekVersion,
      });

  static Future<Map<String, dynamic>> switchLedger(String id) =>
      _post('/ledgers/switch/$id', {});

  static Future<Map<String, dynamic>> updateLedger(
    String id, {
    String? name,
    String? icon,
  }) =>
      _patch('/ledgers/$id', {
        if (name != null) 'name': name,
        if (icon != null) 'icon': icon,
      });

  static Future<Map<String, dynamic>> deleteLedger(String id) =>
      _delete('/ledgers/$id');

  static Future<Map<String, dynamic>> createInvite(String ledgerId) =>
      _post('/ledgers/$ledgerId/invite', {});

  static Future<Map<String, dynamic>> joinLedger(String code) =>
      _post('/ledgers/join', {'code': code});

  static Future<Map<String, dynamic>> getMembers(String ledgerId) =>
      _get('/ledgers/$ledgerId/members');

  static Future<Map<String, dynamic>> removeMember(
          String ledgerId, String userId) =>
      _delete('/ledgers/$ledgerId/members/$userId');

  // ── AI 智能导入 ────────────────────────────────────────────
  static Future<Map<String, dynamic>> aiListModels() =>
      _get('/ai/models');

  static Future<Map<String, dynamic>> aiListImports(String ledgerId) =>
      _get('/ai/imports', params: {'ledgerId': ledgerId});

  static Future<Map<String, dynamic>> aiGetImport(String id) =>
      _get('/ai/imports/$id');

  static Future<Map<String, dynamic>> aiDeleteImport(String id) =>
      _delete('/ai/imports/$id');

  /// 上传文件 → 立刻返回 importId，后端异步处理
  static Future<Map<String, dynamic>> aiUploadImport({
    required String ledgerId,
    required String accountId,
    required String filename,
    required List<int> bytes,
    String? modelName,
  }) async {
    final uri = Uri.parse('$baseUrl/ai/imports');
    final req = http.MultipartRequest('POST', uri);
    final token = await AuthService.getToken();
    if (token != null) req.headers['Authorization'] = 'Bearer $token';
    req.fields['ledgerId'] = ledgerId;
    req.fields['accountId'] = accountId;
    if (modelName != null) req.fields['modelName'] = modelName;
    req.files.add(http.MultipartFile.fromBytes(
      'file',
      bytes,
      filename: filename,
    ));
    final streamed =
        await _client.send(req).timeout(const Duration(seconds: 60));
    final res = await http.Response.fromStream(streamed);
    final body = _decode(res);
    return (body is Map) ? body.cast<String, dynamic>() : <String, dynamic>{};
  }

  /// 客户端把加密后的 bills 回填 → 后端入库 + 标记 done
  static Future<Map<String, dynamic>> aiApplyImport(
    String id,
    List<Map<String, dynamic>> bills, {
    List<Map<String, dynamic>> transfers = const [],
    List<Map<String, dynamic>> loans = const [],
  }) =>
      // 后端是逐条事务写入，账单多时耗时较长，给足超时（默认 20s 会卡住大批量）
      _post('/ai/imports/$id/apply', {
        'bills': bills,
        if (transfers.isNotEmpty) 'transfers': transfers,
        if (loans.isNotEmpty) 'loans': loans,
      }, timeout: const Duration(seconds: 120));

  // ─── 周期账单 / 订阅管家 ───────────────────────────────────
  /// 把一条普通账单转为借贷或账户间转账（原地重分类，不重复扣钱）
  static Future<Map<String, dynamic>> convertBill(
    String id, {
    required String to, // 'loan' | 'transfer'
    String? toAccountId,
    String? noteCipher,
    int? noteDekVer,
  }) =>
      _post('/bills/$id/convert', {
        'to': to,
        if (toAccountId != null) 'toAccountId': toAccountId,
        if (noteCipher != null) 'noteCipher': noteCipher,
        if (noteDekVer != null) 'noteDekVer': noteDekVer,
      });

  static Future<Map<String, dynamic>> recurringCandidates() =>
      _get('/recurring/candidates');

  static Future<Map<String, dynamic>> recurringList() => _get('/recurring');

  static Future<Map<String, dynamic>> createRecurring(
    Map<String, dynamic> body,
  ) =>
      _post('/recurring', body);

  static Future<Map<String, dynamic>> updateRecurring(
    String id,
    Map<String, dynamic> body,
  ) =>
      _patch('/recurring/$id', body);

  static Future<Map<String, dynamic>> deleteRecurring(String id) =>
      _delete('/recurring/$id');

  // ─── 储蓄目标 ──────────────────────────────────────────
  static Future<Map<String, dynamic>> getGoals() => _get('/goals');

  static Future<Map<String, dynamic>> createGoal(
    Map<String, dynamic> body,
  ) =>
      _post('/goals', body);

  static Future<Map<String, dynamic>> updateGoal(
    String id,
    Map<String, dynamic> body,
  ) =>
      _patch('/goals/$id', body);

  static Future<Map<String, dynamic>> deleteGoal(String id) =>
      _delete('/goals/$id');

  // ─── AI 月报 ───────────────────────────────────────────
  static Future<Map<String, dynamic>> aiMonthlyReport({
    required String ledgerId,
    required int year,
    required int month,
    required Map<String, dynamic> aggregates,
  }) =>
      _post('/ai/monthly-report', {
        'ledgerId': ledgerId,
        'period': {'year': year, 'month': month},
        'aggregates': aggregates,
      });

  // ─── AI 对话查询 ──────────────────────────────────────────
  static Future<Map<String, dynamic>> aiChat({
    required String ledgerId,
    required String message,
    List<Map<String, String>>? history,
  }) =>
      _post('/ai/chat', {
        'ledgerId': ledgerId,
        'message': message,
        if (history != null) 'history': history,
      });

  // ─── AI 自然语言解析（NL 一句话记账）────────────────────
  static Future<Map<String, dynamic>> aiParseText({
    required String ledgerId,
    required String text,
    String? accountId,
    Map<String, dynamic>? prevDraft,
  }) =>
      _post('/ai/parse-text', {
        'ledgerId': ledgerId,
        'text': text,
        if (accountId != null) 'accountId': accountId,
        if (prevDraft != null) 'prevDraft': prevDraft,
      });

  // ─── AI 洞察 ──────────────────────────────────────────────
  static Future<Map<String, dynamic>> aiInsights() => _get('/ai/insights');

  static Future<Map<String, dynamic>> aiDismissInsight({
    required String type,
    required String target,
  }) =>
      _post('/ai/insights/dismiss', {'type': type, 'target': target});

  // ─── CFO 复盘简报 ─────────────────────────────────────────
  /// 拉取（惰性生成）当前账本的 pending 建议。
  /// 后端直接返回一个 JSON 数组，故用 [_getRaw] 拿到 List；
  /// 极端情况下若被包成 Map（{proposals|data: [...]}），调用方做兜底解析。
  static Future<dynamic> cfoProposals() => _getRaw('/cfo/proposals');

  /// 对某条建议做决定：approve | dismiss | snooze | resolve
  static Future<Map<String, dynamic>> cfoDecide(String id, String action) =>
      _post('/cfo/proposals/$id/decide', {'action': action});

  /// CFO 自动执行规则：后端返回 [{actionType, enabled}]（白名单动作）
  static Future<dynamic> cfoAutoRules() => _getRaw('/cfo/auto-rules');

  /// 开关某动作类型的自动执行（仅白名单内动作；高危动作后端 400 拒绝）
  static Future<Map<String, dynamic>> cfoSetAutoRule(
          String actionType, bool enabled) =>
      _put('/cfo/auto-rules/$actionType', {'enabled': enabled});

  // ─── 借贷往来 ─────────────────────────────────────────────
  static Future<List<dynamic>> getLoans() async {
    final res = await _getRaw('/loans');
    return (res is List) ? res : <dynamic>[];
  }

  static Future<Map<String, dynamic>> getLoanSummary() =>
      _get('/loans/summary');

  static Future<Map<String, dynamic>> createLoan({
    required String direction, // lend | borrow
    required double amount,
    String? accountId,
    String? noteCipher,
    int? noteDekVer,
    String? voucherKey,
    DateTime? date,
  }) =>
      _post('/loans', {
        'direction': direction,
        'amount': amount,
        if (accountId != null) 'accountId': accountId,
        if (noteCipher != null) 'noteCipher': noteCipher,
        if (noteDekVer != null) 'noteDekVer': noteDekVer,
        if (voucherKey != null) 'voucherKey': voucherKey,
        if (date != null) 'date': date.toIso8601String(),
      });

  static Future<Map<String, dynamic>> repayLoan(
    String id, {
    required double amount,
    String? accountId,
    String? noteCipher,
    int? noteDekVer,
  }) =>
      _post('/loans/$id/repay', {
        'amount': amount,
        if (accountId != null) 'accountId': accountId,
        if (noteCipher != null) 'noteCipher': noteCipher,
        if (noteDekVer != null) 'noteDekVer': noteDekVer,
      });

  static Future<Map<String, dynamic>> updateLoan(
    String id, {
    double? amount,
    String? noteCipher,
    int? noteDekVer,
    String? voucherKey,
    DateTime? date,
  }) =>
      _patch('/loans/$id', {
        if (amount != null) 'amount': amount,
        if (noteCipher != null) 'noteCipher': noteCipher,
        if (noteDekVer != null) 'noteDekVer': noteDekVer,
        if (voucherKey != null) 'voucherKey': voucherKey,
        if (date != null) 'date': date.toIso8601String(),
      });

  static Future<Map<String, dynamic>> deleteLoan(String id) =>
      _delete('/loans/$id');

  /// 上传凭证图片，返回 { key }
  static Future<Map<String, dynamic>> uploadVoucher(
    List<int> bytes,
    String filename,
  ) async {
    final uri = Uri.parse('$baseUrl/uploads/voucher');
    final req = http.MultipartRequest('POST', uri);
    final token = await AuthService.getToken();
    if (token != null) req.headers['Authorization'] = 'Bearer $token';
    req.files.add(http.MultipartFile.fromBytes('file', bytes,
        filename: filename));
    final streamed =
        await _client.send(req).timeout(const Duration(seconds: 60));
    final res = await http.Response.fromStream(streamed);
    final body = _decode(res);
    return (body is Map) ? body.cast<String, dynamic>() : <String, dynamic>{};
  }

  /// 取凭证图片字节（带鉴权），用于 Image.memory 显示
  static Future<List<int>?> fetchVoucher(String key) async {
    try {
      final res = await _client
          .get(Uri.parse('$baseUrl/uploads/voucher/$key'),
              headers: await _headers())
          .timeout(const Duration(seconds: 30));
      if (res.statusCode == 200) return res.bodyBytes;
    } catch (_) {}
    return null;
  }

  // ─── App 自助升级 ─────────────────────────────────────────
  /// 查最新版本（公开接口，无需登录）。返回 { buildNumber, version, notes, apkFile }
  static Future<Map<String, dynamic>> getAppVersion() =>
      _get('/app/version');

  /// 最新 APK 下载地址（浏览器打开即下载安装）
  static String get appDownloadUrl => '$baseUrl/app/download';

  /// 查询/更新某只股票：取最新数据 + 分析并保存快照。q 可为名称或代码。
  /// 返回 { quote, analysis, news, updatedAt }。后端要解析+抓行情+分析，给足超时。
  static Future<Map<String, dynamic>> getStock(String q) async {
    final uri = Uri.parse('$baseUrl/tools/stock')
        .replace(queryParameters: {'q': q});
    final res = await _client
        .get(uri, headers: await _headers())
        .timeout(const Duration(seconds: 50));
    final body = _decode(res);
    return (body is Map) ? body.cast<String, dynamic>() : <String, dynamic>{};
  }

  /// 我查询过的股票列表（按 symbol 最新一条）
  static Future<List<dynamic>> getStocks() async {
    final res = await _getRaw('/tools/stocks');
    return (res is List) ? res : <dynamic>[];
  }

  /// 某股票保存的完整分析 + 历史（含最新价与持仓）
  static Future<Map<String, dynamic>> getStockSaved(String symbol) =>
      _get('/tools/stocks/$symbol');

  /// AI 持仓解读（数据解读+风险提示，无操作建议）。返回 { text, generatedAt }
  static Future<Map<String, dynamic>> getHoldingsInsight({bool force = false}) =>
      _get('/tools/holdings/insight', params: {if (force) 'force': '1'});

  /// 组合每日总盈亏曲线：返回 [{date, pnl}]（pnl 正=盈，负=亏）
  static Future<List<dynamic>> getHoldingPnlDaily({int days = 30}) async {
    final res = await _getRaw('/tools/holdings/pnl-daily?days=$days');
    return (res is List) ? res : <dynamic>[];
  }

  /// 设置/更新某股票持仓（买入价、数量；≤0 清空）。返回 { holding }
  static Future<Map<String, dynamic>> setStockHolding(
    String symbol, {
    required double buyPrice,
    required double shares,
    String? accountId, // 关联账户：传则开启每日自动结算当日盈亏
  }) =>
      _post('/tools/stocks/$symbol/holding', {
        'buyPrice': buyPrice,
        'shares': shares,
        'accountId': accountId,
      });


  // ─── 工具箱 · 汇率 ────────────────────────────────────────
  /// 获取以 [base] 为基准的最新汇率表（后端代理 + 缓存）。
  /// 返回 { base, updatedAt, rates: { USD: x, EUR: y, ... } }
  static Future<Map<String, dynamic>> getExchangeRates({
    String base = 'CNY',
  }) =>
      _get('/tools/exchange-rates', params: {'base': base});
}
