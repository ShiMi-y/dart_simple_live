import 'dart:async';
import 'dart:io';
import 'dart:isolate';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_smart_dialog/flutter_smart_dialog.dart';
import 'package:get/get.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:logger/logger.dart';
import 'package:media_kit/media_kit.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path_provider/path_provider.dart';
import 'package:simple_live_app/app/app_style.dart';
import 'package:simple_live_app/app/controller/app_settings_controller.dart';
import 'package:simple_live_app/app/instance.dart';
import 'package:simple_live_app/app/log.dart';
import 'package:simple_live_app/app/utils.dart';
import 'package:simple_live_app/app/utils/listen_fourth_button.dart';
import 'package:simple_live_app/models/db/follow_user.dart';
import 'package:simple_live_app/models/db/follow_user_tag.dart';
import 'package:simple_live_app/models/db/history.dart';
import 'package:simple_live_app/modules/other/debug_log_page.dart';
import 'package:simple_live_app/routes/app_pages.dart';
import 'package:simple_live_app/routes/route_path.dart';
import 'package:simple_live_app/services/bilibili_account_service.dart';
import 'package:simple_live_app/services/douyin_account_service.dart';
import 'package:simple_live_app/services/db_service.dart';
import 'package:simple_live_app/services/follow_service.dart';
import 'package:simple_live_app/services/local_storage_service.dart';
import 'package:simple_live_app/services/super_chat_cache_service.dart';
import 'package:simple_live_app/services/live_notify_service.dart';
import 'package:simple_live_app/services/shared_follow_service.dart';
import 'package:simple_live_app/services/sync_service.dart';
import 'package:simple_live_app/widgets/status/app_loadding_widget.dart';
import 'package:simple_live_core/simple_live_core.dart';
import 'package:window_manager/window_manager.dart';

import 'package:path/path.dart' as p;
import 'package:dynamic_color/dynamic_color.dart';

void main() {
  // 全局兜底：未捕获异常只记录日志，避免长时间播放后返回等场景直接闪退
  runZonedGuarded(
    () async {
      WidgetsFlutterBinding.ensureInitialized();
      FlutterError.onError = (details) {
        FlutterError.presentError(details);
        debugPrint("Flutter异常: ${details.exceptionAsString()}");
      };
      await migrateData();
      MediaKit.ensureInitialized();
      // 多开支持：为当前实例分配可用的Hive数据目录（桌面端）
      await initHive();
      await initWindow();
      //初始化服务
      await initServices();
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
      //设置状态栏为透明
      SystemUiOverlayStyle systemUiOverlayStyle = const SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: Brightness.dark,
        systemNavigationBarColor: Colors.transparent,
      );
      SystemChrome.setSystemUIOverlayStyle(systemUiOverlayStyle);
      runApp(const MyApp());
    },
    (error, stack) {
      debugPrint("未捕获异常: $error\n$stack");
    },
  );
}

/// 将Hive数据迁移到Application Support
Future migrateData() async {
  if (Platform.isAndroid || Platform.isIOS) {
    return;
  }
  var hiveFileList = [
    "followuser",
    //旧版本写错成hostiry了
    "hostiry",
    "followusertag",
    "localstorage",
    "danmushield",
  ];
  try {
    var newDir = await getApplicationSupportDirectory();
    var hiveFile = File(p.join(newDir.path, "followuser.hive"));
    if (await hiveFile.exists()) {
      return;
    }

    var oldDir = await getApplicationDocumentsDirectory();
    for (var element in hiveFileList) {
      var oldFile = File(p.join(oldDir.path, "$element.hive"));
      if (await oldFile.exists()) {
        var fileName = "$element.hive";
        if (element == "hostiry") {
          fileName = "history.hive";
        }
        await oldFile.copy(p.join(newDir.path, fileName));
        await oldFile.delete();
      }
      var lockFile = File(p.join(oldDir.path, "$element.lock"));
      if (await lockFile.exists()) {
        await lockFile.delete();
      }
    }
  } catch (e) {
    Log.logPrint(e);
  }
}

/// 初始化Hive，并为当前实例选择可用的数据目录（桌面端支持多开）
///
/// 多开场景下，第二个实例无法打开已被占用的 Hive 文件，
/// 因此这里依次尝试：默认目录 -> instances/inst_1 -> inst_2 ...
/// 用临时 Hive 实例「打开核心box」来探测目录是否被占用，
/// （不能用全局 Hive 探测：它会缓存失败的 box，导致后续实例全部启动失败）
/// 额外实例首次使用时会从主目录复制关注列表/标签/设置，保证多窗口数据一致。
Future<void> initHive() async {
  if (Platform.isAndroid || Platform.isIOS) {
    await Hive.initFlutter();
    return;
  }
  var baseDir = await getApplicationSupportDirectory();
  for (var i = 0; i < 30; i++) {
    var dir = i == 0
        ? baseDir
        : Directory(p.join(baseDir.path, "instances", "inst_$i"));
    try {
      if (!await dir.exists()) {
        await dir.create(recursive: true);
      }
      if (i > 0) {
        await _copyInitialConfigIfEmpty(baseDir, dir);
      }
      if (!await _probeHiveDirectory(dir.path)) {
        continue;
      }
      await Hive.initFlutter(dir.path);
      instanceIndex = i;
      isPrimaryInstance = i == 0;
      Log.d("Instance index: $i, data dir: ${dir.path}");
      return;
    } catch (e) {
      Log.logPrint("Instance dir #$i error: $e");
    }
  }
  // 兜底：使用默认目录
  await Hive.initFlutter(baseDir.path);
}

/// 探测数据目录是否可用（未被其他运行中的实例占用）
///
/// 在一个独立 isolate 中尝试打开核心 box：
/// isolate 拥有独立的全局 Hive 实例与内存，探测失败不会污染主 isolate 的 Hive，
/// 也不会像直接探测那样把失败的 box 缓存下来导致后续启动失败。
Future<bool> _probeHiveDirectory(String path) async {
  try {
    return await Isolate.run(() async {
      Hive.init(path);
      var box = await Hive.openBox("LocalStorage");
      await box.close();
      return true;
    });
  } catch (e) {
    Log.logPrint("Probe failed for $path: $e");
    return false;
  }
}

/// 新实例目录首次使用时，从主目录复制基础数据（关注列表、设置）
Future<void> _copyInitialConfigIfEmpty(
  Directory baseDir,
  Directory targetDir,
) async {
  try {
    var filesToCopy = [
      "followuser.hive",
      "followusertag.hive",
      "localstorage.hive",
    ];
    for (var fileName in filesToCopy) {
      var src = File(p.join(baseDir.path, fileName));
      var dst = File(p.join(targetDir.path, fileName));
      if (await src.exists() && !await dst.exists()) {
        await src.copy(dst.path);
      }
    }
  } catch (e) {
    Log.logPrint("Copy initial config error: $e");
  }
}

Future initWindow() async {
  if (!(Platform.isMacOS || Platform.isWindows || Platform.isLinux)) {
    return;
  }
  await windowManager.ensureInitialized();
  WindowOptions windowOptions = WindowOptions(
    minimumSize: const Size(280, 280),
    center: true,
    // 多开时在标题上标注实例序号，便于区分窗口
    title: instanceIndex > 0 ? "Simple Live (实例 ${instanceIndex + 1})" : "Simple Live",
  );
  windowManager.waitUntilReadyToShow(windowOptions, () async {
    // 多开时错开窗口位置，方便并排查看多个直播
    if (instanceIndex > 0) {
      await windowManager.setPosition(
        Offset(70.0 * instanceIndex, 50.0 * instanceIndex),
      );
    }
    await windowManager.show();
    await windowManager.focus();
  });
}

Future initServices() async {
  Hive.registerAdapter(FollowUserAdapter());
  Hive.registerAdapter(HistoryAdapter());
  Hive.registerAdapter(FollowUserTagAdapter());

  //包信息
  Utils.packageInfo = await PackageInfo.fromPlatform();
  //本地存储
  Log.d("Init LocalStorage Service");
  await Get.put(LocalStorageService()).init();
  await Get.put(SuperChatCacheService()).init();
  await Get.put(LiveNotifyService()).init();
  await Get.put(DBService()).init();
  // 多开：共享同一份关注数据（必须在 DBService 之后、FollowService 之前）
  await Get.put(SharedFollowService()).init();
  //初始化设置控制器
  Get.put(AppSettingsController());

  Get.put(BiliBiliAccountService());

  Get.put(DouyinAccountService());

  Get.put(SyncService());

  Get.put(FollowService());

  initCoreLog();
}

void initCoreLog() {
  //日志信息
  CoreLog.enableLog =
      !kReleaseMode || AppSettingsController.instance.logEnable.value;
  CoreLog.requestLogType = RequestLogType.short;
  CoreLog.onPrintLog = (level, msg) {
    switch (level) {
      case Level.debug:
        Log.d(msg);
        break;
      case Level.error:
        Log.e(msg, StackTrace.current);
        break;
      case Level.info:
        Log.i(msg);
        break;
      case Level.warning:
        Log.w(msg);
        break;
      default:
        Log.logPrint(msg);
    }
  };
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    bool isDynamicColor = AppSettingsController.instance.isDynamic.value;
    Color styleColor = Color(AppSettingsController.instance.styleColor.value);
    return DynamicColorBuilder(
        builder: ((ColorScheme? lightDynamic, ColorScheme? darkDynamic) {
      ColorScheme? lightColorScheme;
      ColorScheme? darkColorScheme;
      if (lightDynamic != null && darkDynamic != null && isDynamicColor) {
        lightColorScheme = lightDynamic;
        darkColorScheme = darkDynamic;
      } else {
        lightColorScheme = ColorScheme.fromSeed(
          seedColor: styleColor,
          brightness: Brightness.light,
        );
        darkColorScheme = ColorScheme.fromSeed(
            seedColor: styleColor, brightness: Brightness.dark);
      }
      return GetMaterialApp(
        title: "Simple Live",
        theme: AppStyle.lightTheme.copyWith(colorScheme: lightColorScheme),
        darkTheme: AppStyle.darkTheme.copyWith(colorScheme: darkColorScheme),
        themeMode:
            ThemeMode.values[Get.find<AppSettingsController>().themeMode.value],
        initialRoute: RoutePath.kIndex,
        getPages: AppPages.routes,
        //国际化
        locale: const Locale("zh", "CN"),
        localizationsDelegates: const [
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        supportedLocales: const [Locale("zh", "CN")],
        logWriterCallback: (text, {bool? isError}) {
          Log.addDebugLog(text, (isError ?? false) ? Colors.red : Colors.grey);
          Log.writeLog(text, (isError ?? false) ? Level.error : Level.info);
        },
        // 升级后Android页面过渡动画似乎有BUG
        defaultTransition: Platform.isAndroid ? Transition.cupertino : null,
        //debugShowCheckedModeBanner: false,
        navigatorObservers: [FlutterSmartDialog.observer],
        builder: FlutterSmartDialog.init(
          loadingBuilder: ((msg) => const AppLoaddingWidget()),
          //字体大小不跟随系统变化
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context)
                .copyWith(textScaler: const TextScaler.linear(1.0)),
            child: Stack(
              children: [
                //侧键返回
                RawGestureDetector(
                  excludeFromSemantics: true,
                  gestures: <Type, GestureRecognizerFactory>{
                    FourthButtonTapGestureRecognizer:
                        GestureRecognizerFactoryWithHandlers<
                            FourthButtonTapGestureRecognizer>(
                      () => FourthButtonTapGestureRecognizer(),
                      (FourthButtonTapGestureRecognizer instance) {
                        instance.onTapDown = (TapDownDetails details) async {
                          //如果处于全屏状态，退出全屏
                          if (!Platform.isAndroid && !Platform.isIOS) {
                            if (await windowManager.isFullScreen()) {
                              await windowManager.setFullScreen(false);
                              return;
                            }
                          }
                          Get.back();
                        };
                      },
                    ),
                  },
                  child: KeyboardListener(
                    focusNode: FocusNode(),
                    onKeyEvent: (KeyEvent event) async {
                      if (event is KeyDownEvent &&
                          event.logicalKey == LogicalKeyboardKey.escape) {
                        // ESC退出全屏
                        // 如果处于全屏状态，退出全屏
                        if (!Platform.isAndroid && !Platform.isIOS) {
                          if (await windowManager.isFullScreen()) {
                            await windowManager.setFullScreen(false);
                            return;
                          }
                        }
                      }
                    },
                    child: child!,
                  ),
                ),

                //查看DEBUG日志按钮
                //只在Debug、Profile模式显示
                Visibility(
                  visible: !kReleaseMode,
                  child: Positioned(
                    right: 12,
                    bottom: 100 + context.mediaQueryViewPadding.bottom,
                    child: Opacity(
                      opacity: 0.4,
                      child: ElevatedButton(
                        child: const Text("DEBUG LOG"),
                        onPressed: () {
                          Get.bottomSheet(
                            const DebugLogPage(),
                          );
                        },
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }));
  }
}
