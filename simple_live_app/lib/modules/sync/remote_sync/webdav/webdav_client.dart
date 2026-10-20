import 'dart:async';
import 'dart:typed_data';

import 'package:webdav_client/webdav_client.dart';

class DAVClient {
  late Client client;
  Completer<bool> pingCompleter = Completer();

  DAVClient(
      String webDAVUri,
      String webDAVUser,
      String webDAVPassword,
      ) {
    client = newClient(
      webDAVUri,
      user: webDAVUser,
      password: webDAVPassword,
    );
    // 服务器同时返回 Digest 与 Basic 两种 WWW-Authenticate 时，
    // webdav_client 会优先选择 Digest；但它的 Digest 计算使用的是未拼接 baseUrl 的
    // 原始 path（如 "/"），当 WebDAV 地址带路径前缀（如 /server.php/）时必然校验失败。
    // 这里固定使用 Basic 鉴权，兼容性最好。
    client.auth = BasicAuth(user: webDAVUser, pwd: webDAVPassword);
    client.setHeaders(
      {
        'accept-charset': 'utf-8',
        'Content-Type': 'text/xml',
      },
    );
    client.setConnectTimeout(8000);
    client.setSendTimeout(8000);
    client.setReceiveTimeout(8000);
    pingCompleter.complete(_ping());
  }

  Future<bool> _ping() async {
    try {
      await client.ping();
      return true;
    } catch (_) {
      return false;
    }
  }
  // 强制统一
  get root => "/simple_live_app";

  get backupFile => "$root/backup.zip";

  backup(Uint8List data) async {
    await client.mkdir("$root");
    await client.write("$backupFile", data);
    return true;
  }

  Future<List<int>> recovery() async {
    await client.mkdir("$root");
    final data = await client.read(backupFile);
    return data;
  }
}