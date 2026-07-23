import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;
import 'package:pointycastle/digests/md5.dart';

/// WebDAV 备份上传配置（存本机安全存储，按账号隔离）。
class WebDavConfig {
  /// 服务器地址，如 https://dav.jianguoyun.com/dav/ （结尾带不带 / 都行）
  final String url;
  final String username;
  final String password;
  /// 远端目录（相对 url），如 司库备份 或 backups/siku
  final String directory;

  const WebDavConfig({
    required this.url,
    required this.username,
    required this.password,
    this.directory = '司库备份',
  });

  bool get isComplete => url.trim().isNotEmpty;

  Map<String, dynamic> toJson() => {
        'url': url,
        'username': username,
        'password': password,
        'directory': directory,
      };

  factory WebDavConfig.fromJson(Map<String, dynamic> j) => WebDavConfig(
        url: (j['url'] as String?) ?? '',
        username: (j['username'] as String?) ?? '',
        password: (j['password'] as String?) ?? '',
        directory: (j['directory'] as String?)?.isNotEmpty == true
            ? j['directory'] as String
            : '司库备份',
      );
}

/// WebDAV 上传：HTTP PUT，Basic / Digest 认证都支持。
///
/// 上传的内容永远是 .sikubak 密文文件——明文永不出设备，
/// WebDAV 服务器只是「存了一个它读不懂的 blob」。
class WebDavService {
  WebDavService._();
  static final WebDavService instance = WebDavService._();

  static const _kPrefix = 'webdav_config@'; // + userId，按账号隔离
  static const _storage = FlutterSecureStorage(
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
  );

  Future<WebDavConfig?> load(String userId) async {
    try {
      final raw = await _storage.read(key: '$_kPrefix$userId');
      if (raw == null) return null;
      final cfg = WebDavConfig.fromJson(
          (jsonDecode(raw) as Map).cast<String, dynamic>());
      return cfg.isComplete ? cfg : null;
    } catch (_) {
      return null;
    }
  }

  Future<void> save(String userId, WebDavConfig cfg) =>
      _storage.write(key: '$_kPrefix$userId', value: jsonEncode(cfg.toJson()));

  Future<void> clear(String userId) =>
      _storage.delete(key: '$_kPrefix$userId');

  // ── 上传 ─────────────────────────────────────────────────

  /// 上传 [bytes] 到 {url}{directory}/{filename}。
  /// 先逐级 MKCOL 建目录（已存在则忽略），再 PUT。
  /// 抛 [WebDavException]（含状态码与摘要，UI 直接展示）。
  Future<void> upload(
    WebDavConfig cfg,
    String filename,
    Uint8List bytes,
  ) async {
    final base = _normalizeBase(cfg.url);
    final dir = cfg.directory.trim().replaceAll(RegExp(r'^/+|/+$'), '');
    final segments =
        dir.isEmpty ? <String>[] : dir.split('/').where((s) => s.isNotEmpty);

    // 先无认证试一次，拿到 401 挑战后按 Digest / Basic 重试
    final auth = _AuthSession(cfg);

    // 逐级建目录（409/405 = 已存在，忽略）
    var current = base;
    for (final seg in segments) {
      current = '$current${Uri.encodeComponent(seg)}/';
      final code = await auth.send('MKCOL', Uri.parse(current));
      if (code == 401) throw const WebDavException(401, '认证失败：用户名或密码错误');
      // 201 创建成功 / 200 / 204 / 301 / 405 / 409 都视为可继续
      if (code >= 400 && code != 405 && code != 409) {
        throw WebDavException(code, '创建远端目录失败');
      }
    }

    final fileUri = Uri.parse('$current${Uri.encodeComponent(filename)}');
    final code = await auth.send('PUT', fileUri, body: bytes);
    if (code == 401) throw const WebDavException(401, '认证失败：用户名或密码错误');
    if (code < 200 || code >= 300) {
      throw WebDavException(code, '上传失败');
    }
  }

  /// 测试连通性：对根地址发一次 PROPFIND（等价于列目录）
  Future<void> testConnection(WebDavConfig cfg) async {
    final base = _normalizeBase(cfg.url);
    final auth = _AuthSession(cfg);
    final code = await auth.send('PROPFIND', Uri.parse(base),
        headers: {'Depth': '0'});
    if (code == 401) throw const WebDavException(401, '认证失败：用户名或密码错误');
    if (code == 404) throw const WebDavException(404, '地址不存在（404）');
    if (code >= 400) throw WebDavException(code, '连接失败');
    // 200/207 Multi-Status 都算通
  }

  static String _normalizeBase(String url) {
    var u = url.trim();
    if (!u.startsWith('http://') && !u.startsWith('https://')) {
      u = 'https://$u';
    }
    return u.endsWith('/') ? u : '$u/';
  }
}

class WebDavException implements Exception {
  final int statusCode;
  final String message;
  const WebDavException(this.statusCode, this.message);
  @override
  String toString() => '$message（HTTP $statusCode）';
}

/// 一次上传会话的认证状态：第一次 401 后记住挑战，后续请求直接带认证头。
class _AuthSession {
  final WebDavConfig cfg;
  String? _authHeader;

  _AuthSession(this.cfg);

  final http.Client _client = http.Client();

  /// 发请求；遇到 401 且还没认证过时，按服务端挑战（Digest 优先，其次 Basic）
  /// 构造认证头重试一次。返回最终状态码。
  Future<int> send(
    String method,
    Uri uri, {
    Map<String, String>? headers,
    Uint8List? body,
  }) async {
    var res = await _raw(method, uri, headers: {
      ...?headers,
      if (_authHeader != null) 'Authorization': _authHeader!,
    }, body: body);
    if (res.statusCode != 401 || _authHeader != null) return res.statusCode;

    final challenge = res.headers['www-authenticate'] ?? '';
    _authHeader = _buildAuth(method, uri, challenge);
    if (_authHeader == null) return res.statusCode; // 无法识别的挑战，原样返回 401
    res = await _raw(method, uri, headers: {
      ...?headers,
      'Authorization': _authHeader!,
    }, body: body);
    return res.statusCode;
  }

  Future<http.Response> _raw(
    String method,
    Uri uri, {
    Map<String, String>? headers,
    Uint8List? body,
  }) {
    final req = http.Request(method, uri);
    if (headers != null) req.headers.addAll(headers);
    if (body != null) req.bodyBytes = body;
    return _client.send(req).then(http.Response.fromStream);
  }

  String? _buildAuth(String method, Uri uri, String challenge) {
    if (challenge.toLowerCase().contains('digest')) {
      return _digest(method, uri, challenge);
    }
    if (challenge.toLowerCase().contains('basic')) {
      return 'Basic ${base64.encode(utf8.encode('${cfg.username}:${cfg.password}'))}';
    }
    // 有的服务器 401 不带挑战头：用户名非空就按 Basic 试
    if (cfg.username.isNotEmpty) {
      return 'Basic ${base64.encode(utf8.encode('${cfg.username}:${cfg.password}'))}';
    }
    return null;
  }

  /// RFC 7616 Digest（MD5, qop=auth）——坚果云 / Nextcloud 等常见实现
  String? _digest(String method, Uri uri, String challenge) {
    final realm = _param(challenge, 'realm');
    final nonce = _param(challenge, 'nonce');
    if (realm == null || nonce == null) return null;
    final opaque = _param(challenge, 'opaque');
    final qopRaw = _param(challenge, 'qop') ?? '';
    final qop = qopRaw.split(',').map((s) => s.trim()).contains('auth')
        ? 'auth'
        : null;

    final path = uri.path.isEmpty ? '/' : uri.path;
    final uriStr = uri.hasQuery ? '$path?${uri.query}' : path;

    final ha1 = _md5('${cfg.username}:$realm:${cfg.password}');
    final ha2 = _md5('$method:$uriStr');
    const nc = '00000001';
    final cnonce = _md5('${DateTime.now().microsecondsSinceEpoch}')
        .substring(0, 16);
    final response = qop != null
        ? _md5('$ha1:$nonce:$nc:$cnonce:$qop:$ha2')
        : _md5('$ha1:$nonce:$ha2');

    final parts = <String>[
      'username="${cfg.username}"',
      'realm="$realm"',
      'nonce="$nonce"',
      'uri="$uriStr"',
      'response="$response"',
      if (opaque != null) 'opaque="$opaque"',
      if (qop != null) ...['qop=$qop', 'nc=$nc', 'cnonce="$cnonce"'],
      'algorithm=MD5',
    ];
    return 'Digest ${parts.join(', ')}';
  }

  static String? _param(String challenge, String key) {
    final m = RegExp('$key="?([^",]+)"?').firstMatch(challenge);
    return m?.group(1);
  }

  static String _md5(String s) {
    final digest = MD5Digest().process(Uint8List.fromList(utf8.encode(s)));
    return digest.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  }
}
