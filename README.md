# 信大AIO · NUIST AIO

Flutter / Material Design 3 的南京信息工程大学校园服务整合应用.

## 功能

- 首页、学习、功能、我的四栏导航。
- 六组主题配色、明暗/系统模式、Android 12+ 壁纸动态取色，偏好本地保存。
- 首次五步设置向导：欢迎、外观、主账号登录、子站初始化、实际宿舍。
- 教务课表：每天 11 节用户作息、分周教室变更、首页彩色时间轴、学习页周课表；支持本机课程编辑/删除和 JSON 导入。
- 教务查询：空闲教室、学分进度与学期 GPA、考试安排、课程成绩和绩点；各页右上角可打开系统浏览器。
- 本机加密课表缓存，离线查看；切换账号/移除会话时清理旧课表。
- 校园卡电子余额、卡片账户余额、本月收支、按月分页账单与宿舍剩余电量；安全存储查询缓存。
- 三套电费目录共 12,418 个房间选项，离线选择、搜索；可在向导和“我的”中设置。
- 首页采用问候区、课程时间线与校园账户卡片结构；图书借阅等待后续接入。

## 运行与验证

```sh
flutter pub get
flutter run
flutter analyze
flutter test
node --test tools/test_*adapter.mjs tools/test_portal_probe.mjs
flutter run -d macos
```

已补充 macOS 本机构建与 WKWebView 支持；各平台均使用自己的学校登录会话。Android 专属证书配置、平台视图退出与动态取色仍需要手机验证。桌面浏览器登录不会自动共享给 App。业务读取在 App WebView 的教务同源环境内执行，不向第三方服务器上传凭据。

## 代码入口

- `lib/src/home_page.dart`：首页。
- `lib/src/shell.dart`：导航、功能和我的。
- `lib/src/schedule/`：课表模型、原生导入页与展示。
- `lib/src/academic/`、`assets/js/nuist_academic.js`：四项教务查询与官方浏览器入口
- `lib/src/accounts/`：校园账户查询、宿舍选择、缓存与展示。
- `assets/data/nuist_dormitories.json`：三套学校电费服务的完整目录快照。
- `assets/js/nuist_accounts.js`：固定接口的只读校园账户适配器。
- `assets/js/nuist_schedule.js`：本地打包的教务 API 读取逻辑。
- `lib/src/app.dart`、`theme_settings.dart`：MD3 与主题。
- `lib/src/auth/`：统一认证与安全存储。
- `docs/authentication-research.md`：最初的认证调研。
- `docs/schedule-integration.md`：课表接入、实测证据及边界。
- `docs/campus-accounts-integration.md`：余额、账单、电费接口及完整目录说明。

Android 使用 AGP 8.13.1 / Gradle 8.14 / Kotlin 2.2.21，兼容当前稳定版 WebView 插件；Gradle 限制 2GB 堆内存与 2 个工作线程。iOS 保留源码及 Keychain 配置，不启动模拟器验证。

## 截图

可选生成界面检查图，字体仅用于测试，不打包到 App：

```sh
CAPTURE_UI=1 UI_FONT='/path/to/chinese-font.ttc' flutter test test/app_test.dart --plain-name 'capture UI review images'
```

输出到 `build/ui-preview/`。`*-example.png` 使用合成数据，不展示真实账户数据。

课表接口参考拾光 NUIST MIT 许可适配脚本，许可随 App 打包并在开源许可页展示；详情见接入文档。
