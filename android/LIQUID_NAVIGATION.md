# Android 液态玻璃导航栏

MD3 与 MIUIX 共用「外观与主题 → 液态玻璃导航栏」和已有持久化配置。
开启后替换当前主题底栏，关闭后恢复 Material NavigationBar 或 MiuixNavigationBar。

## 完整移植及来源

Android 13+ 直接运行 SukiSU-Ultra 的 Compose `FloatingBottomBar`，不是 View 重写。
`navigation/sukisu/UPSTREAM.json` 固定上游 revision 和 8 个源文件的 SHA-256。
以下文件只改了包名及对应 import，核心实现原样保留：

- `FloatingBottomBar.kt`：背景及标签双采样、组合背景、拖动胶囊、位移与形变。
- `DampedDragAnimation.kt`：原弹簧参数、速度跟踪、按压/释放时序、取消回弹。
- `InteractiveHighlight.kt`：加色高光、手指光斑、按压及位置弹簧。
- `DragGestureInspector.kt`：原触摸事件通道、多指衔接与取消规则。
- `Lens.kt`：圆角矩形 SDF、深度透镜及七通道色散。
- `Vibrancy.kt`：1.5 倍饱和度。
- `CombinedBackdrop.kt`：背景与放大标签图层组合采样。
- `InnerShadow.kt`：动态离屏内阴影。

保留原组件的全部光学、动画管线：4dp 模糊、24dp 边缘折射、随按压渐变的
10/14dp 深度透镜及 0.5 色散、双峰 BloomStroke 高光、3° 量化重力光源、
外/内阴影、按压 78/56 缩放、1.2 倍标签内容、速度导致的横纵拉伸和 4dp 橡皮筋位移。
原组件的可选渐进模糊分支也保留；默认与 SukiSU 一样不额外启用该独立选项。

执行 `python3 tools/checks/check_liquid_nav_port.py` 验证上游核心文件没有被简化。
署名和许可证见 `third_party/sukisu-liquid-glass/NOTICE.md`。

## Flutter 适配

`FlutterBackdrop` 将 Hybrid Composition 的 Flutter 背景 `FlutterImageView` 直接记录
到 Compose 原生硬件画布，交给原版 miuix-blur 0.9.4 管线处理。不采样导航栏自身，
不读取截图或创建全屏 Bitmap。逆变换算法使用同版本 miuix 的 `InverseLayerScope`。
Flutter 背景提交新帧时只使采样绘制失效，没有定时器或无限动画。

`LiquidNavView` 仅负责配置、四个业务页签内容、生命周期和 Flutter 回调；
主题色由 Flutter 提供。宿主使用 FlutterFragmentActivity，向 Compose 传播真实
LifecycleOwner 与 SavedStateRegistryOwner，原版重力传感器随生命周期注册/注销。
原生视图预留 96dp 空间，64dp 底栏居中，避免 78dp 按压胶囊及阴影被裁切。

原版 0.9.4 依赖要求 compileSdk 37、Kotlin/Compose compiler 2.4.20、AGP 9.1+；
本项目使用 AGP 9.1.0 和 Gradle 9.3.1。官方 Maven Central 镜像用于依赖下载。
现有 WebView 插件 1.1.3 的旧 ProGuard 默认文件名通过项目内 Gradle 脚本映射到
优化版默认规则，不修改 pub 缓存或 WebView 运行时代码。
miuix-blur / shader 的 minSdk 为 33，仅精确覆盖这两个模块的清单门槛；
工厂在 API 33 以下完全不创建 Compose 玻璃类，使用隔离的 `LegacyLiquidNavView`：
Android 12 使用模糊，更早系统使用高不透明度兼容样式。其他平台沿用原 Flutter 底栏。

## MIUIX 页面交互

MIUIX 主页面使用 `lib/src/navigation/tab_pages.dart` 的横向分页容器，
点击底栏时连续滑过中间页，支持手势跟随、释放吸附与底栏选中同步。
点击翻页采用 SukiSU 所用 miuix 0.9.4 `PagerNavigationSpringSpec` 的
弹簧参数：质量 1、刚度 322.2、阻尼 32.31，静止阈值换算到页面宽度。
快速切换会取消旧目标；页面持续挂载，保留输入和滚动状态。MD3 保留淡入切页。
系统开启减少动画时直接切换，RTL 布局反转横向手势与过渡方向。

## 验证

Flutter 模拟测试检查创建参数、选中回调及非法值、主题更新、安全区、销毁，以及
MD3/MIUIX 开关和恢复主题底栏。模拟测试不能证明原生光学效果或动画帧率。
真机应检查按压/拖动/释放、取消、滚动背景、深浅主题、两种 UI、页面与弹窗遮挡、
返回、后台恢复及安全区。原版核心校验与设备验证应分别报告。

2026-11-15 验证记录：静态分析、204 项 Flutter 测试、8 个上游文件校验和发布
APK 构建通过；已在连接的 API 37 真机覆盖安装。ADB 画面检查确认按压放大、
拖动透镜与色散、释放切页；用户另行确认人工测试通过。
