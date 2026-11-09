import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:pointycastle/digests/blake2b.dart';
import 'package:pointycastle/digests/sha3.dart';

/// 哔哩哔哩 App 端接口签名工具
///
/// - [appSign]：`appkey/ts` 体系，md5(urlencode(排序参数) + appsecret)
/// - [clientSign]：`client_sign` 字段，sha512→sha3_512→sha384→sha3_384→blake2b 链式哈希
class BiliAppSign {
  static const String appkey = "4409e2ce8ffd12b8";
  static const String appsecret = "59b43e04ad6965f34319062b478f83dd";
  static const String heartbeatSecretKey = "axoaadsffcazxksectbbb";

  static String _hex(List<int> bytes) =>
      bytes.map((e) => e.toRadixString(16).padLeft(2, '0')).join();

  static String _md5(String s) => _hex(md5.convert(utf8.encode(s)).bytes);
  static String _sha384(String s) =>
      _hex(sha384.convert(utf8.encode(s)).bytes);
  static String _sha512(String s) =>
      _hex(sha512.convert(utf8.encode(s)).bytes);

  static String _sha3(int bits, String s) {
    var digest = SHA3Digest(bits);
    return _hex(digest.process(Uint8List.fromList(utf8.encode(s))));
  }

  static String _blake2b(String s) {
    var digest = Blake2bDigest(digestSize: 64);
    return _hex(digest.process(Uint8List.fromList(utf8.encode(s))));
  }

  /// App 接口的 `sign` 字段
  static String appSign(Map<String, dynamic> data) {
    var keys = data.keys.toList()..sort();
    var query = keys
        .map((k) =>
            "${Uri.encodeQueryComponent(k)}=${Uri.encodeQueryComponent(data[k].toString())}")
        .join("&");
    return _md5(query + appsecret);
  }

  /// 心跳接口的 `client_sign` 字段
  ///
  /// 注意：参与计算的 map 必须与调用方最终提交时的字段**顺序一致**（json 保序）。
  static String clientSign(Map<String, dynamic> data) {
    var s = jsonEncode(data);
    s = _sha512(s);
    s = _sha3(512, s);
    s = _sha384(s);
    s = _sha3(384, s);
    s = _blake2b(s);
    return s;
  }
}
