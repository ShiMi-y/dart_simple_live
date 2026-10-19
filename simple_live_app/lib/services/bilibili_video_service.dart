import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:simple_live_app/app/log.dart';
import 'package:simple_live_app/models/bilibili_video.dart';
import 'package:simple_live_app/requests/http_client.dart';
import 'package:simple_live_app/services/bilibili_account_service.dart';

/// 哔哩哔哩视频（AV/BV）接口
///
/// 只依赖公开接口，登录后（已保存的Cookie）可获取更高清晰度：
/// - 视频信息：x/web-interface/view
/// - 播放地址：x/player/playurl（fnval=1 返回单文件mp4，便于直接播放）
/// - 弹幕：x/v1/dm/list.so（返回 raw deflate 压缩的XML，需手动解压）
class BiliBiliVideoService {
  static final BiliBiliVideoService instance = BiliBiliVideoService._();

  BiliBiliVideoService._();

  static final RegExp _bvidReg = RegExp(r'BV[0-9A-Za-z]{10}');
  static final RegExp _aidReg = RegExp(r'(?:^|[^0-9a-zA-Z])(?:av|aid=)(\d+)',
      caseSensitive: false);
  static final RegExp _danmakuReg = RegExp(
    r'<d p="([^"]+)">([\s\S]*?)</d>',
  );

  String get _cookie {
    try {
      return BiliBiliAccountService.instance.cookie;
    } catch (_) {
      return "";
    }
  }

  Map<String, String> get _header {
    var header = {
      "User-Agent":
          "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/126.0.0.0 Safari/537.36",
      "Referer": "https://www.bilibili.com",
    };
    if (_cookie.isNotEmpty) {
      header["Cookie"] = _cookie;
    }
    return header;
  }

  /// 从用户输入中解析 BV号 / AV号
  /// 支持：BV1xx411c7mD、av170001、纯数字、以及包含它们的视频链接
  BiliVideoQuery? parseQuery(String input) {
    var text = input.trim();
    if (text.isEmpty) {
      return null;
    }
    var bvidMatch = _bvidReg.firstMatch(text);
    if (bvidMatch != null) {
      return BiliVideoQuery(bvid: bvidMatch.group(0));
    }
    var aidMatch = _aidReg.firstMatch(text);
    if (aidMatch != null) {
      return BiliVideoQuery(aid: int.tryParse(aidMatch.group(1) ?? ""));
    }
    // 纯数字当作AV号
    if (RegExp(r'^\d+$').hasMatch(text)) {
      return BiliVideoQuery(aid: int.tryParse(text));
    }
    return null;
  }

  /// 获取视频信息（包含分P列表）
  Future<BiliVideoInfo> getVideoInfo(String input) async {
    var query = parseQuery(input);
    if (query == null) {
      throw Exception("无法识别的 AV/BV 号");
    }
    var data = await HttpClient.instance.getJson(
      "https://api.bilibili.com/x/web-interface/view",
      queryParameters: {
        if (query.bvid != null) "bvid": query.bvid,
        if (query.aid != null) "aid": query.aid,
      },
      header: _header,
    );
    if (data is! Map || data["code"] != 0) {
      throw Exception(data is Map ? (data["message"] ?? "获取视频信息失败") : "获取视频信息失败");
    }
    var info = Map<String, dynamic>.from(data["data"] as Map);
    var result = BiliVideoInfo.fromJson(info);
    if (result.pages.isEmpty && info["cid"] != null) {
      result = BiliVideoInfo(
        aid: result.aid,
        bvid: result.bvid,
        title: result.title,
        cover: result.cover,
        desc: result.desc,
        duration: result.duration,
        ownerName: result.ownerName,
        ownerFace: result.ownerFace,
        pages: [
          BiliVideoPage(
            cid: info["cid"] as int,
            page: 1,
            part: result.title,
            duration: result.duration,
          ),
        ],
      );
    }
    return result;
  }

  /// 是否已登录哔哩哔哩（登录后可获取更高清晰度）
  bool get isLogin => _cookie.isNotEmpty;

  /// 获取播放地址
  ///
  /// [qn] 期望清晰度（可为空）。为空时：已登录从 1080P+ 开始尝试，未登录从 1080P 开始。
  /// 按「期望清晰度 → 接口返回的可选清晰度（从高到低）」依次尝试，返回第一个可播放的。
  Future<BiliVideoPlayUrl> getPlayUrl({
    required String bvid,
    required int cid,
    int? qn,
  }) async {
    var preferred = qn ?? (isLogin ? 112 : 80);
    var tried = <int>{};
    var candidates = <int>[preferred];
    Map<int, String> acceptQuality = {};
    var sawDash = false;

    for (var round = 0; round < 2; round++) {
      for (var quality in candidates) {
        if (!tried.add(quality)) {
          continue;
        }
        var data = await HttpClient.instance.getJson(
          "https://api.bilibili.com/x/player/playurl",
          queryParameters: {
            "bvid": bvid,
            "cid": cid,
            "qn": quality,
            "fnval": 1,
            "fourk": 1,
          },
          header: _header,
        );
        if (data is! Map || data["code"] != 0) {
          continue;
        }
        var playData = data["data"];
        if (playData is! Map) {
          continue;
        }
        if (acceptQuality.isEmpty) {
          acceptQuality = _parseAcceptQuality(playData);
        }
        if ((playData["dash"] as Map?)?.isNotEmpty == true) {
          sawDash = true;
        }
        var durl = playData["durl"];
        if (durl is List && durl.isNotEmpty) {
          var url = (durl.first as Map)["url"]?.toString() ?? "";
          if (url.isNotEmpty) {
            var actualQuality = playData["quality"] as int? ?? quality;
            return BiliVideoPlayUrl(
              url: url,
              quality: actualQuality,
              qualityDesc: acceptQuality[actualQuality] ?? "清晰度$quality",
              acceptQuality: acceptQuality,
            );
          }
        }
      }
      // 第二轮：按接口给出的可选清晰度从高到低再试一遍
      var extra = acceptQuality.keys
          .where((e) => e != preferred && !tried.contains(e))
          .toList()
        ..sort((a, b) => b.compareTo(a));
      if (extra.isEmpty) {
        break;
      }
      candidates = extra;
    }

    if (sawDash) {
      throw Exception(
        isLogin ? "该清晰度需要大会员或付费，已尝试其余清晰度仍失败" : "无法获取播放地址，登录哔哩哔哩账号后可选更高清晰度",
      );
    }
    throw Exception("无法获取播放地址（可能是付费/大会员视频）");
  }

  Map<int, String> _parseAcceptQuality(Map playData) {
    var result = <int, String>{};
    var qualities = playData["accept_quality"];
    var descriptions = playData["accept_description"];
    if (qualities is List && descriptions is List) {
      for (var i = 0; i < qualities.length && i < descriptions.length; i++) {
        var qn = qualities[i] as int?;
        if (qn != null) {
          result[qn] = descriptions[i].toString();
        }
      }
    }
    return result;
  }

  /// 获取弹幕列表（按时间升序）
  Future<List<BiliDanmaku>> getDanmaku(int cid) async {
    var resp = await HttpClient.instance.dio.get<List<int>>(
      "https://api.bilibili.com/x/v1/dm/list.so",
      queryParameters: {"oid": cid},
      options: Options(
        responseType: ResponseType.bytes,
        headers: _header,
        receiveTimeout: const Duration(seconds: 30),
      ),
    );
    var bytes = resp.data ?? <int>[];
    if (bytes.isEmpty) {
      return [];
    }
    List<int> xmlBytes;
    try {
      // 接口固定返回 raw deflate（无zlib头），需要手动解压
      xmlBytes = ZLibDecoder(raw: true).convert(bytes);
    } catch (e) {
      Log.logPrint("解压弹幕失败，尝试直接读取: $e");
      xmlBytes = bytes;
    }
    var xml = utf8.decode(xmlBytes, allowMalformed: true);
    return parseDanmakuXml(xml);
  }

  /// 解析弹幕XML
  List<BiliDanmaku> parseDanmakuXml(String xml) {
    var list = <BiliDanmaku>[];
    for (var match in _danmakuReg.allMatches(xml)) {
      var params = match.group(1)?.split(',') ?? [];
      if (params.length < 4) {
        continue;
      }
      var text = _unescapeXml(match.group(2) ?? "");
      if (text.trim().isEmpty) {
        continue;
      }
      list.add(
        BiliDanmaku(
          time: double.tryParse(params[0]) ?? 0,
          mode: int.tryParse(params[1]) ?? 1,
          fontSize: int.tryParse(params[2]) ?? 25,
          color: int.tryParse(params[3]) ?? 0xFFFFFF,
          text: text,
        ),
      );
    }
    list.sort((a, b) => a.time.compareTo(b.time));
    return list;
  }

  String _unescapeXml(String text) {
    return text
        .replaceAll("&lt;", "<")
        .replaceAll("&gt;", ">")
        .replaceAll("&quot;", '"')
        .replaceAll("&#39;", "'")
        .replaceAll("&apos;", "'")
        .replaceAll("&amp;", "&");
  }
}
