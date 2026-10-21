import 'dart:io';

import 'package:simple_live_app/app/constant.dart';
import 'package:simple_live_app/app/log.dart';
import 'package:simple_live_app/app/sites.dart';
import 'package:simple_live_app/services/local_storage_service.dart';

import 'package:flutter/material.dart';
import 'package:get/get.dart';

class AppSettingsController extends GetxController {
  static AppSettingsController get instance =>
      Get.find<AppSettingsController>();

  /// 缩放模式
  var scaleMode = 0.obs;

  var themeMode = 0.obs;

  var firstRun = false;

  @override
  void onInit() {
    loadSettings();
    initSiteSort();
    initHomeSort();
    sanitizePlayerOutput();
    super.onInit();
  }

  /// 从本地存储重新加载全部设置（WebDAV/同步恢复后需要调用，
  /// 否则只写了 Hive 而内存里还是旧值：表现为「恢复当次正常、重启后才出问题」）
  void loadSettings() {
    themeMode.value = LocalStorageService.instance
        .getValue(LocalStorageService.kThemeMode, 0);
    firstRun = LocalStorageService.instance
        .getValue(LocalStorageService.kFirstRun, true);
    danmuSize.value = LocalStorageService.instance
        .getValue(LocalStorageService.kDanmuSize, 16.0);
    danmuOpacity.value = LocalStorageService.instance
        .getValue(LocalStorageService.kDanmuOpacity, 1.0);
    danmuArea.value = LocalStorageService.instance
        .getValue(LocalStorageService.kDanmuArea, 0.8);
    danmuSpeed.value = LocalStorageService.instance
        .getValue(LocalStorageService.kDanmuSpeed, 10.0);
    danmuEnable.value = LocalStorageService.instance
        .getValue(LocalStorageService.kDanmuEnable, true);
    danmuStrokeWidth.value = LocalStorageService.instance
        .getValue(LocalStorageService.kDanmuStrokeWidth, 2.0);
    danmuTopMargin.value = LocalStorageService.instance
        .getValue(LocalStorageService.kDanmuTopMargin, 0.0);
    danmuBottomMargin.value = LocalStorageService.instance
        .getValue(LocalStorageService.kDanmuBottomMargin, 0.0);
    danmuFontWeight.value = LocalStorageService.instance
        .getValue(LocalStorageService.kDanmuFontWeight, 4);

    hardwareDecode.value = LocalStorageService.instance
        .getValue(LocalStorageService.kHardwareDecode, true);
    chatTextSize.value = LocalStorageService.instance
        .getValue(LocalStorageService.kChatTextSize, 14.0);

    chatTextGap.value = LocalStorageService.instance
        .getValue(LocalStorageService.kChatTextGap, 4.0);

    chatBubbleStyle.value = LocalStorageService.instance.getValue(
      LocalStorageService.kChatBubbleStyle,
      false,
    );

    qualityLevel.value = LocalStorageService.instance
        .getValue(LocalStorageService.kQualityLevel, 2);
    qualityLevelCellular.value = LocalStorageService.instance
        .getValue(LocalStorageService.kQualityLevelCellular, 2);

    autoExitEnable.value = LocalStorageService.instance
        .getValue(LocalStorageService.kAutoExitEnable, false);

    autoExitDuration.value = LocalStorageService.instance
        .getValue(LocalStorageService.kAutoExitDuration, 60);

    roomAutoExitDuration.value = LocalStorageService.instance
        .getValue(LocalStorageService.kRoomAutoExitDuration, 60);

    playerCompatMode.value = LocalStorageService.instance
        .getValue(LocalStorageService.kPlayerCompatMode, false);

    playerAutoPause.value = LocalStorageService.instance
        .getValue(LocalStorageService.kPlayerAutoPause, false);

    playerForceHttps.value = LocalStorageService.instance
        .getValue(LocalStorageService.kPlayerForceHttps, false);

    autoFullScreen.value = LocalStorageService.instance
        .getValue(LocalStorageService.kAutoFullScreen, false);

    // ignore: invalid_use_of_protected_member
    shieldList.value = LocalStorageService.instance.shieldBox.values.toSet();

    // ignore: invalid_use_of_protected_member
    scUidList.value = LocalStorageService.instance.scUidBox.values.toSet();

    scPersist.value = LocalStorageService.instance.getValue(
      LocalStorageService.kScPersist,
      false,
    );

    chatScInline.value = LocalStorageService.instance.getValue(
      LocalStorageService.kChatScInline,
      true,
    );

    chatScInlineCount.value = LocalStorageService.instance.getValue(
      LocalStorageService.kChatScInlineCount,
      3,
    );

    chatScBarVisible.value = LocalStorageService.instance.getValue(
      LocalStorageService.kChatScBarVisible,
      true,
    );

    // 「播放器中显示SC」开关（此前只有保存、没有启动恢复，重启后会复位）
    playershowSuperChat.value = LocalStorageService.instance.getValue(
      LocalStorageService.kPlayerShowSuperChat,
      true,
    );

    scaleMode.value = LocalStorageService.instance.getValue(
      LocalStorageService.kPlayerScaleMode,
      0,
    );

    playerVolume.value = LocalStorageService.instance.getValue(
      LocalStorageService.kPlayerVolume,
      100.0,
    );
    videoVolume.value = LocalStorageService.instance.getValue(
      LocalStorageService.kVideoVolume,
      100.0,
    );
    liveNotifyEnable.value = LocalStorageService.instance.getValue(
      LocalStorageService.kLiveNotifyEnable,
      true,
    );
    pipHideDanmu.value = LocalStorageService.instance
        .getValue(LocalStorageService.kPIPHideDanmu, true);

    styleColor.value = LocalStorageService.instance
        .getValue(LocalStorageService.kStyleColor, 0xff3498db);

    isDynamic.value = LocalStorageService.instance
        .getValue(LocalStorageService.kIsDynamic, false);

    bilibiliLoginTip.value = LocalStorageService.instance
        .getValue(LocalStorageService.kBilibiliLoginTip, true);

    playerBufferSize.value = LocalStorageService.instance
        .getValue(LocalStorageService.kPlayerBufferSize, 32);

    logEnable.value = LocalStorageService.instance
        .getValue(LocalStorageService.kLogEnable, false);
    if (logEnable.value) {
      Log.initWriter();
    }

    customPlayerOutput.value = LocalStorageService.instance
        .getValue(LocalStorageService.kCustomPlayerOutput, false);

    videoOutputDriver.value = LocalStorageService.instance.getValue(
      LocalStorageService.kVideoOutputDriver,
      Platform.isAndroid ? "gpu" : "libmpv",
    );

    audioOutputDriver.value = LocalStorageService.instance.getValue(
      LocalStorageService.kAudioOutputDriver,
      Platform.isAndroid
          ? "audiotrack"
          : Platform.isLinux
              ? "pulse"
              : Platform.isWindows
                  ? "wasapi"
                  : Platform.isIOS
                      ? "audiounit"
                      : Platform.isMacOS
                          ? "coreaudio"
                          : "sdl",
    );

    videoHardwareDecoder.value = LocalStorageService.instance.getValue(
      LocalStorageService.kVideoHardwareDecoder,
      Platform.isAndroid ? "auto-safe" : "auto",
    );

    // 一次性迁移：画质默认值由「中间」改为「最高（原画）」
    try {
      var migrated = LocalStorageService.instance
          .getValue("QualityLevelDefaultMigrated", false);
      if (!migrated) {
        if (qualityLevel.value == 1) {
          setQualityLevel(2);
        }
        if (qualityLevelCellular.value == 1) {
          setQualityLevelCellular(2);
        }
        LocalStorageService.instance
            .setValue("QualityLevelDefaultMigrated", true);
      }
    } catch (e) {
      Log.logPrint("画质默认值迁移失败: $e");
    }

    autoUpdateFollowEnable.value = LocalStorageService.instance
        .getValue(LocalStorageService.kAutoUpdateFollowEnable, true);

    autoUpdateFollowDuration.value = LocalStorageService.instance
        .getValue(LocalStorageService.kUpdateFollowDuration, 10);

    updateFollowThreadCount.value = LocalStorageService.instance
        .getValue(LocalStorageService.kUpdateFollowThreadCount, 0);  // 默认 0 = 自动
  }

  /// 当前平台支持的音频输出驱动（mpv 的 ao）
  static bool isAudioDriverValidForPlatform(String driver) {
    if (driver.isEmpty) {
      return false;
    }
    const cross = {"null", "pcm", "sdl", "openal", "libao"};
    if (cross.contains(driver)) {
      return true;
    }
    if (Platform.isAndroid) {
      return {"audiotrack", "opensles", "aaudio"}.contains(driver);
    }
    if (Platform.isWindows) {
      return {"wasapi", "directsound", "winmm"}.contains(driver);
    }
    if (Platform.isLinux) {
      return {"pulse", "pipewire", "alsa", "oss", "jack"}.contains(driver);
    }
    if (Platform.isIOS) {
      return driver == "audiounit";
    }
    if (Platform.isMacOS) {
      return driver == "coreaudio";
    }
    return false;
  }

  /// 当前平台支持的视频输出驱动（mpv 的 vo）
  static bool isVideoDriverValidForPlatform(String driver) {
    if (driver.isEmpty) {
      return false;
    }
    const cross = {"gpu", "gpu-next", "null", "sdl"};
    if (cross.contains(driver)) {
      return true;
    }
    if (Platform.isAndroid) {
      return driver == "mediacodec_embed";
    }
    if (Platform.isWindows) {
      return {"direct3d", "libmpv"}.contains(driver);
    }
    if (Platform.isLinux) {
      return {"xv", "x11", "vdpau", "dmabuf-wayland", "vaapi"}.contains(driver);
    }
    return false;
  }

  /// 按当前平台默认值
  static String defaultAudioDriver() {
    if (Platform.isAndroid) {
      return "audiotrack";
    }
    if (Platform.isLinux) {
      return "pulse";
    }
    if (Platform.isWindows) {
      return "wasapi";
    }
    if (Platform.isIOS) {
      return "audiounit";
    }
    if (Platform.isMacOS) {
      return "coreaudio";
    }
    return "sdl";
  }

  static String defaultVideoDriver() {
    if (Platform.isAndroid) {
      return "gpu";
    }
    if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
      return "gpu";
    }
    return "gpu";
  }

  /// 启动时纠正「跨平台同步/误选」导致的非法驱动（否则 mpv 音频输出创建失败 → 无声）
  void sanitizePlayerOutput() {
    try {
      if (!customPlayerOutput.value) {
        return;
      }
      var audio = audioOutputDriver.value;
      if (!isAudioDriverValidForPlatform(audio)) {
        Log.logPrint("音频输出驱动 [$audio] 不适用于当前平台，已回退为默认值");
        setAudioOutputDriver(defaultAudioDriver());
      }
      var video = videoOutputDriver.value;
      if (!isVideoDriverValidForPlatform(video)) {
        Log.logPrint("视频输出驱动 [$video] 不适用于当前平台，已回退为默认值");
        setVideoOutputDriver(defaultVideoDriver());
      }
    } catch (e) {
      Log.logPrint("纠正播放器输出设置失败: $e");
    }
  }

  void initSiteSort() {
    var sort = LocalStorageService.instance
        .getValue(
          LocalStorageService.kSiteSort,
          Sites.allSites.keys.join(","),
        )
        .split(",");
    //如果数量与allSites的数量不一致，将缺失的添加上
    if (sort.length != Sites.allSites.length) {
      var keys = Sites.allSites.keys.toList();
      for (var i = 0; i < keys.length; i++) {
        if (!sort.contains(keys[i])) {
          sort.add(keys[i]);
        }
      }
    }

    siteSort.value = sort;
  }

  void initHomeSort() {
    var sort = LocalStorageService.instance
        .getValue(
          LocalStorageService.kHomeSort,
          Constant.allHomePages.keys.join(","),
        )
        .split(",");
    //如果数量与allSites的数量不一致，将缺失的添加上
    if (sort.length != Constant.allHomePages.length) {
      var keys = Constant.allHomePages.keys.toList();
      for (var i = 0; i < keys.length; i++) {
        if (!sort.contains(keys[i])) {
          sort.add(keys[i]);
        }
      }
    }

    homeSort.value = sort;
  }

  void setNoFirstRun() {
    LocalStorageService.instance.setValue(LocalStorageService.kFirstRun, false);
  }

  void changeTheme() {
    Get.dialog(
      RadioGroup(
        groupValue: themeMode.value,
        onChanged: (e) {
          Get.back();
          setTheme(e ?? 0);
        },
        child: const SimpleDialog(
          title: Text("设置主题"),
          children: [
            RadioListTile<int>(
              title: Text("跟随系统"),
              value: 0,
            ),
            RadioListTile<int>(
              title: Text("浅色模式"),
              value: 1,
            ),
            RadioListTile<int>(
              title: Text("深色模式"),
              value: 2,
            ),
          ],
        ),
      ),
    );
  }

  void setTheme(int i) {
    themeMode.value = i;
    var mode = ThemeMode.values[i];

    LocalStorageService.instance.setValue(LocalStorageService.kThemeMode, i);
    Get.changeThemeMode(mode);
  }

  var hardwareDecode = true.obs;
  void setHardwareDecode(bool e) {
    hardwareDecode.value = e;
    LocalStorageService.instance
        .setValue(LocalStorageService.kHardwareDecode, e);
  }

  var chatTextSize = 14.0.obs;
  void setChatTextSize(double e) {
    chatTextSize.value = e;
    LocalStorageService.instance.setValue(LocalStorageService.kChatTextSize, e);
  }

  var chatTextGap = 4.0.obs;
  void setChatTextGap(double e) {
    chatTextGap.value = e;
    LocalStorageService.instance.setValue(LocalStorageService.kChatTextGap, e);
  }

  var chatBubbleStyle = false.obs;
  void setChatBubbleStyle(bool e) {
    chatBubbleStyle.value = e;
    LocalStorageService.instance
        .setValue(LocalStorageService.kChatBubbleStyle, e);
  }

  var danmuSize = 16.0.obs;
  void setDanmuSize(double e) {
    danmuSize.value = e;
    LocalStorageService.instance.setValue(LocalStorageService.kDanmuSize, e);
  }

  var danmuSpeed = 10.0.obs;
  void setDanmuSpeed(double e) {
    danmuSpeed.value = e;
    LocalStorageService.instance.setValue(LocalStorageService.kDanmuSpeed, e);
  }

  var danmuArea = 0.8.obs;
  void setDanmuArea(double e) {
    danmuArea.value = e;
    LocalStorageService.instance.setValue(LocalStorageService.kDanmuArea, e);
  }

  var danmuOpacity = 1.0.obs;
  void setDanmuOpacity(double e) {
    danmuOpacity.value = e;
    LocalStorageService.instance.setValue(LocalStorageService.kDanmuOpacity, e);
  }

  var danmuEnable = true.obs;
  void setDanmuEnable(bool e) {
    danmuEnable.value = e;
    LocalStorageService.instance.setValue(LocalStorageService.kDanmuEnable, e);
  }

  var danmuStrokeWidth = 2.0.obs;
  void setDanmuStrokeWidth(double e) {
    danmuStrokeWidth.value = e;
    LocalStorageService.instance
        .setValue(LocalStorageService.kDanmuStrokeWidth, e);
  }

  var danmuFontWeight = 4.obs;
  void setDanmuFontWeight(int e) {
    danmuFontWeight.value = e;
    LocalStorageService.instance
        .setValue(LocalStorageService.kDanmuFontWeight, e);
  }

  var qualityLevel = 1.obs;
  void setQualityLevel(int level) {
    qualityLevel.value = level;
    LocalStorageService.instance
        .setValue(LocalStorageService.kQualityLevel, level);
  }

  var qualityLevelCellular = 1.obs;
  void setQualityLevelCellular(int level) {
    qualityLevelCellular.value = level;
    LocalStorageService.instance
        .setValue(LocalStorageService.kQualityLevelCellular, level);
  }

  var autoExitEnable = false.obs;
  void setAutoExitEnable(bool e) {
    autoExitEnable.value = e;
    LocalStorageService.instance
        .setValue(LocalStorageService.kAutoExitEnable, e);
  }

  var autoExitDuration = 60.obs;
  void setAutoExitDuration(int e) {
    autoExitDuration.value = e;
    LocalStorageService.instance
        .setValue(LocalStorageService.kAutoExitDuration, e);
  }

  var roomAutoExitDuration = 60.obs;
  void setRoomAutoExitDuration(int e) {
    roomAutoExitDuration.value = e;
    LocalStorageService.instance
        .setValue(LocalStorageService.kRoomAutoExitDuration, e);
  }

  var playerCompatMode = false.obs;
  void setPlayerCompatMode(bool e) {
    playerCompatMode.value = e;
    LocalStorageService.instance
        .setValue(LocalStorageService.kPlayerCompatMode, e);
  }

  var playerBufferSize = 32.obs;
  void setPlayerBufferSize(int e) {
    playerBufferSize.value = e;
    LocalStorageService.instance
        .setValue(LocalStorageService.kPlayerBufferSize, e);
  }

  var playerAutoPause = false.obs;
  void setPlayerAutoPause(bool e) {
    playerAutoPause.value = e;
    LocalStorageService.instance
        .setValue(LocalStorageService.kPlayerAutoPause, e);
  }

  var autoFullScreen = false.obs;
  void setAutoFullScreen(bool e) {
    autoFullScreen.value = e;
    LocalStorageService.instance
        .setValue(LocalStorageService.kAutoFullScreen, e);
  }

  var playershowSuperChat = true.obs;
  void setPlayerShowSuperChat(bool e) {
    playershowSuperChat.value = e;
    LocalStorageService.instance
        .setValue(LocalStorageService.kPlayerShowSuperChat, e);
  }

  RxSet<String> shieldList = <String>{}.obs;
  void addShieldList(String e) {
    shieldList.add(e);
    LocalStorageService.instance.shieldBox.put(e, e);
  }

  void removeShieldList(String e) {
    shieldList.remove(e);
    LocalStorageService.instance.shieldBox.delete(e);
  }

  Future clearShieldList() async {
    shieldList.clear();
    await LocalStorageService.instance.shieldBox.clear();
  }

  /// SC常驻显示：倒计时结束后不消失
  var scPersist = false.obs;
  void setScPersist(bool e) {
    scPersist.value = e;
    LocalStorageService.instance.setValue(LocalStorageService.kScPersist, e);
  }

  /// SC混入聊天流
  var chatScInline = true.obs;
  void setChatScInline(bool e) {
    chatScInline.value = e;
    LocalStorageService.instance.setValue(LocalStorageService.kChatScInline, e);
  }

  /// 聊天流中内联SC的最大条数（2~5）
  var chatScInlineCount = 3.obs;
  void setChatScInlineCount(int e) {
    chatScInlineCount.value = e;
    LocalStorageService.instance
        .setValue(LocalStorageService.kChatScInlineCount, e);
  }

  /// 聊天区是否显示SC窗口（点击SC窗口可隐藏，有新的SC会自动重新显示）
  var chatScBarVisible = true.obs;
  void setChatScBarVisible(bool e) {
    chatScBarVisible.value = e;
    LocalStorageService.instance
        .setValue(LocalStorageService.kChatScBarVisible, e);
  }

  /// SC关注UID（哔哩哔哩），命中的发言始终以SC形式显示
  RxSet<String> scUidList = <String>{}.obs;
  /// 整体替换 SC 关注UID（用于 WebDAV/局域网同步恢复）
  Future<void> replaceScUidList(Set<String> ids) async {
    await LocalStorageService.instance.scUidBox.clear();
    for (var id in ids) {
      await LocalStorageService.instance.scUidBox.put(id, id);
    }
    // ignore: invalid_use_of_protected_member
    scUidList.value = ids;
  }

  void addScUid(String e) {
    scUidList.add(e);
    LocalStorageService.instance.scUidBox.put(e, e);
  }

  void removeScUid(String e) {
    scUidList.remove(e);
    LocalStorageService.instance.scUidBox.delete(e);
  }

  Future clearScUid() async {
    scUidList.clear();
    await LocalStorageService.instance.scUidBox.clear();
  }

  void setScaleMode(int value) {
    scaleMode.value = value;
    LocalStorageService.instance.setValue(
      LocalStorageService.kPlayerScaleMode,
      value,
    );
  }

  RxList<String> siteSort = RxList<String>();
  void setSiteSort(List<String> e) {
    siteSort.value = e;
    LocalStorageService.instance.setValue(
      LocalStorageService.kSiteSort,
      siteSort.join(","),
    );
  }

  RxList<String> homeSort = RxList<String>();
  void setHomeSort(List<String> e) {
    homeSort.value = e;
    LocalStorageService.instance.setValue(
      LocalStorageService.kHomeSort,
      homeSort.join(","),
    );
  }

  Rx<double> playerVolume = 100.0.obs;
  void setPlayerVolume(double value) {
    playerVolume.value = value;
    LocalStorageService.instance.setValue(
      LocalStorageService.kPlayerVolume,
      value,
    );
  }

  /// 开播提醒总开关（关注主播开播时发送系统通知）
  Rx<bool> liveNotifyEnable = true.obs;

  void setLiveNotifyEnable(bool value) {
    liveNotifyEnable.value = value;
    LocalStorageService.instance.setValue(
      LocalStorageService.kLiveNotifyEnable,
      value,
    );
  }

  /// 视频播放器（AV/BV）独立音量，与直播间音量互不影响
  Rx<double> videoVolume = 100.0.obs;

  void setVideoVolume(double value) {
    videoVolume.value = value;
    LocalStorageService.instance.setValue(
      LocalStorageService.kVideoVolume,
      value,
    );
  }

  var pipHideDanmu = true.obs;
  void setPIPHideDanmu(bool e) {
    pipHideDanmu.value = e;
    LocalStorageService.instance.setValue(LocalStorageService.kPIPHideDanmu, e);
  }

  var styleColor = 0xff3498db.obs;
  void setStyleColor(int e) {
    styleColor.value = e;
    LocalStorageService.instance.setValue(LocalStorageService.kStyleColor, e);
  }

  var isDynamic = false.obs;
  void setIsDynamic(bool e) {
    isDynamic.value = e;
    LocalStorageService.instance.setValue(LocalStorageService.kIsDynamic, e);
  }

  var danmuTopMargin = 0.0.obs;
  void setDanmuTopMargin(double e) {
    danmuTopMargin.value = e;
    LocalStorageService.instance
        .setValue(LocalStorageService.kDanmuTopMargin, e);
  }

  var danmuBottomMargin = 0.0.obs;
  void setDanmuBottomMargin(double e) {
    danmuBottomMargin.value = e;
    LocalStorageService.instance
        .setValue(LocalStorageService.kDanmuBottomMargin, e);
  }

  var bilibiliLoginTip = true.obs;
  void setBiliBiliLoginTip(bool e) {
    bilibiliLoginTip.value = e;
    LocalStorageService.instance
        .setValue(LocalStorageService.kBilibiliLoginTip, e);
  }

  var logEnable = false.obs;
  void setLogEnable(bool e) {
    logEnable.value = e;
    LocalStorageService.instance.setValue(LocalStorageService.kLogEnable, e);
  }

  var customPlayerOutput = false.obs;
  void setCustomPlayerOutput(bool e) {
    customPlayerOutput.value = e;
    LocalStorageService.instance
        .setValue(LocalStorageService.kCustomPlayerOutput, e);
  }

  var videoOutputDriver = "".obs;
  void setVideoOutputDriver(String e) {
    videoOutputDriver.value = e;
    LocalStorageService.instance
        .setValue(LocalStorageService.kVideoOutputDriver, e);
  }

  var audioOutputDriver = "".obs;
  void setAudioOutputDriver(String e) {
    audioOutputDriver.value = e;
    LocalStorageService.instance
        .setValue(LocalStorageService.kAudioOutputDriver, e);
  }

  var videoHardwareDecoder = "".obs;
  void setVideoHardwareDecoder(String e) {
    videoHardwareDecoder.value = e;
    LocalStorageService.instance
        .setValue(LocalStorageService.kVideoHardwareDecoder, e);
  }

  var autoUpdateFollowEnable = false.obs;
  void setAutoUpdateFollowEnable(bool e) {
    autoUpdateFollowEnable.value = e;
    LocalStorageService.instance
        .setValue(LocalStorageService.kAutoUpdateFollowEnable, e);
  }

  var autoUpdateFollowDuration = 10.obs;
  void setAutoUpdateFollowDuration(int e) {
    autoUpdateFollowDuration.value = e;
    LocalStorageService.instance
        .setValue(LocalStorageService.kUpdateFollowDuration, e);
  }

  var updateFollowThreadCount = 4.obs;
  void setUpdateFollowThreadCount(int e) {
    updateFollowThreadCount.value = e;
    LocalStorageService.instance
        .setValue(LocalStorageService.kUpdateFollowThreadCount, e);
  }

  var playerForceHttps = false.obs;
  void setPlayerForceHttps(bool e) {
    playerForceHttps.value = e;
    LocalStorageService.instance
        .setValue(LocalStorageService.kPlayerForceHttps, e);
  }
}
