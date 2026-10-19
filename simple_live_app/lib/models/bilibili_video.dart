/// 哔哩哔哩视频（AV/BV）相关模型
library;

/// 查询参数（BV号或AV号）
class BiliVideoQuery {
  final String? bvid;
  final int? aid;

  BiliVideoQuery({this.bvid, this.aid});
}

/// 视频信息
class BiliVideoInfo {
  final int aid;
  final String bvid;
  final String title;
  final String cover;
  final String desc;
  final int duration;
  final String ownerName;
  final String ownerFace;
  final List<BiliVideoPage> pages;

  BiliVideoInfo({
    required this.aid,
    required this.bvid,
    required this.title,
    required this.cover,
    required this.desc,
    required this.duration,
    required this.ownerName,
    required this.ownerFace,
    required this.pages,
  });

  factory BiliVideoInfo.fromJson(Map<String, dynamic> json) {
    var pages = <BiliVideoPage>[];
    var rawPages = json["pages"];
    if (rawPages is List) {
      for (var item in rawPages) {
        if (item is Map) {
          pages.add(BiliVideoPage.fromJson(Map<String, dynamic>.from(item)));
        }
      }
    }
    return BiliVideoInfo(
      aid: json["aid"] as int? ?? 0,
      bvid: json["bvid"]?.toString() ?? "",
      title: json["title"]?.toString() ?? "",
      cover: json["pic"]?.toString() ?? "",
      desc: json["desc"]?.toString() ?? "",
      duration: json["duration"] as int? ?? 0,
      ownerName: (json["owner"] as Map?)?["name"]?.toString() ?? "",
      ownerFace: (json["owner"] as Map?)?["face"]?.toString() ?? "",
      pages: pages,
    );
  }
}

/// 视频分P
class BiliVideoPage {
  final int cid;
  final int page;
  final String part;
  final int duration;

  BiliVideoPage({
    required this.cid,
    required this.page,
    required this.part,
    required this.duration,
  });

  factory BiliVideoPage.fromJson(Map<String, dynamic> json) {
    return BiliVideoPage(
      cid: json["cid"] as int? ?? 0,
      page: json["page"] as int? ?? 0,
      part: json["part"]?.toString() ?? "",
      duration: json["duration"] as int? ?? 0,
    );
  }
}

/// 播放地址
class BiliVideoPlayUrl {
  /// 播放链接（durl，单文件mp4）
  final String url;
  final int quality;
  final String qualityDesc;

  /// 可选清晰度（qn -> 描述）
  final Map<int, String> acceptQuality;

  BiliVideoPlayUrl({
    required this.url,
    required this.quality,
    required this.qualityDesc,
    required this.acceptQuality,
  });
}

/// 一条弹幕
class BiliDanmaku {
  /// 出现时间，秒
  final double time;

  /// 1-3 滚动，4 底部，5 顶部
  final int mode;
  final int fontSize;

  /// 十进制RGB颜色
  final int color;
  final String text;

  BiliDanmaku({
    required this.time,
    required this.mode,
    required this.fontSize,
    required this.color,
    required this.text,
  });
}
