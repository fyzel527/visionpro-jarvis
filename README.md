# Jarvis Vision Prototype

一个面向 Apple Vision Pro 的 JARVIS 科幻全息 HUD 原型。项目同时保留 RealityKit 和 Compositor Services + Metal 两条渲染路径，用 ARKit 手部追踪驱动粒子、全息环和空间模型交互。

仓库地址：<https://github.com/fyzel527/visionpro-jarvis>

## 当前状态

- 目标平台：visionOS 26.0+
- 架构：arm64 Apple Vision Pro
- 本机已验证：可针对已连接的真实 Vision Pro 完成 Debug 构建
- 当前默认渲染器：Metal
- 手势输入：ARKit `HandTrackingProvider`
- 资源管理：Git LFS
- 项目阶段：可运行原型，正在完善真实模型、材质和 Metal 交互链路

## 已实现功能

### 控制面板

- RealityKit / Metal 渲染器切换
- 打开或关闭沉浸空间
- 手势、手数量和交互强度状态显示
- Metal 调试状态、帧计数和警告计数
- 粒子发射和环形交互开关
- 手势状态重置

### RealityKit 路径

- 空间粒子环和发光核心
- 左右手指尖发射粒子
- Pinch 抓取并移动粒子环
- Pinch 拖动时旋转粒子环
- Palm Open / Two Hand Expand 驱动整体缩放
- 手势光标和状态 HUD

### Metal / Compositor Services 路径

- `CompositorLayer` 双目渲染
- 根据设备能力选择 layered 或 dedicated layout
- ARKit 世界追踪和预测姿态
- Metal 全息轮廓、扫描和噪声效果
- Sci-Fi Helmet glTF 资产加载入口
- HDR 环境球和混合沉浸模式支持
- C++ 渲染线程与 Swift 手势状态之间的线程安全桥接

### FUI Showcase

- SwiftUI FUI 控制面板
- 圆环、六边形、三角形、箭头轨道和警告面板动画
- Full FUI HUD 沉浸空间
- Clear FUI 透明沉浸空间
- 发光模型展示入口

## 技术架构

```text
SwiftUI ControlPanel
        |
        +--> RealityKit ImmersiveSpace
        |       +--> JarvisSceneController
        |       +--> HandTrackingModel
        |       +--> ParticleEmitterComponent
        |
        +--> CompositorLayer / Metal ImmersiveSpace
                +--> SpatialRenderingEngine.mm
                +--> SpatialRenderer.mm
                +--> SceneShaders.metal
                +--> EnvironmentShaders.metal
                +--> ARKit World Tracking

ARKit HandTrackingProvider
        -> HandTrackingModel
        -> SpatialRenderer_SetHandTrackingState()
        -> C++ atomic snapshot
        -> Metal render thread
```

主要入口文件：

| 文件 | 作用 |
| --- | --- |
| `JarvisVisionPrototypeApp.swift` | App、窗口和多个 ImmersiveSpace 定义 |
| `ControlPanelView.swift` | 主控制面板 |
| `HandTrackingModel.swift` | ARKit 手部追踪、滤波和手势分类 |
| `JarvisSceneController.swift` | RealityKit 粒子环和指尖粒子 |
| `JarvisMetalImmersiveContent.swift` | CompositorLayer 入口 |
| `SpatialRenderingEngine.mm` | Metal 渲染线程、世界追踪和帧循环 |
| `SpatialRenderer.mm` | 模型、环境球、双目绘制和手势变换 |
| `SceneShaders.metal` | 模型全息着色器 |
| `EnvironmentShaders.metal` | HDR 环境着色器 |
| `HolographicComponent.swift` | RealityKit 全息材质和粒子封装原型 |

## 环境要求

- macOS
- Xcode，包含 visionOS 26 SDK
- Apple Vision Pro，已配对并启用开发者模式
- USB-C 有线连接或可用的网络调试连接
- Git LFS

## 获取项目

```bash
git clone git@github.com:fyzel527/visionpro-jarvis.git
cd visionpro-jarvis
git lfs install
git lfs pull
```

如果资源文件内容以以下文本开头，说明 Git LFS 对象尚未下载：

```text
version https://git-lfs.github.com/spec/v1
```

模型和环境资源需要完整下载后才能正常显示。glTF 还引用以下贴图文件：

```text
SciFiHelmet_BaseColor.png
SciFiHelmet_MetallicRoughness.png
SciFiHelmet_Normal.png
SciFiHelmet_AmbientOcclusion.png
```

## 构建和运行

### Xcode

1. 打开 `JarvisVisionPrototype.xcodeproj`。
2. 选择 `JarvisVisionPrototype` scheme。
3. 将运行目标设为已连接的 Apple Vision Pro。
4. 首次运行时允许手部追踪权限。
5. 启动应用后，在控制面板中打开 Metal 或 RealityKit 沉浸空间。

### 命令行构建

模拟器或设备目标可按 Xcode 当前识别到的 destination 调整：

```bash
xcodebuild \
  -project JarvisVisionPrototype.xcodeproj \
  -scheme JarvisVisionPrototype \
  -destination 'platform=visionOS,id=<VISION_PRO_IDENTIFIER>' \
  -configuration Debug \
  build
```

查看已连接设备：

```bash
xcrun devicectl list devices
```

## 手势说明

| 手势 | 当前行为 |
| --- | --- |
| Pinch | 显示空间光标；抓取、移动和旋转 RealityKit 粒子环；Metal 路径支持模型平面偏移 |
| Palm Open | 增强粒子环尺度和交互强度 |
| Two Hand Expand | 根据双手距离展开整体效果 |
| Idle | 保持基础动画 |

手部关节数据经过自适应指数滤波，并在短暂丢失指尖采样时保留 Pinch 状态，以减少拖动跳变。

## 资源和全息材质

项目设计目标是：

```text
GLB / glTF 基础几何
    + Fresnel 边缘光
    + 程序化噪声和扫描
    + 消融与光屑
    + RGB 色散
    + 粒子和后处理
```

相关设计文档：

- [`docs/glb-metal-arkit-architecture.md`](docs/glb-metal-arkit-architecture.md)
- [`docs/holographic-fui-material-requirements.md`](docs/holographic-fui-material-requirements.md)

## 当前已知限制

1. `SciFiHelmet.gltf` 当前的 BIN、HDR、PNG 和字体资源使用 Git LFS；未执行 `git lfs pull` 时，设备上会出现资源加载失败或渲染回退。
2. glTF 运行时目前只取第一个 `MDLMesh` 和第一个 submesh，尚未完成多 mesh、完整 PBR 材质和贴图绑定。
3. `HolographicSurface.mtlx` 已加入工程，但当前 RealityKit 封装仍主要使用 `UnlitMaterial` 线框方案，MaterialX 参数链路尚未完全接通。
4. Metal 内容组件已经预留粒子、环交互和 glowing model 参数，但部分控制面板开关尚未完整传入 C++/Metal 渲染逻辑。
5. Metal 代码仍使用 visionOS 26 已标记 deprecated 的 `cp_frame_query_drawable`；后续应迁移到 `cp_frame_query_drawables`。
6. 构建时若看到 `pngcrush caught libpng error`，优先检查 Git LFS 资源是否已正确下载，而不是先修改 Swift 或 Metal 代码。

## 后续计划

- 完整加载 GLB 多 mesh、submesh 和 PBR 纹理
- 接入真实 MaterialX 全息材质
- 将 Metal 控制项全部接入运行时参数
- 增加模型拾取、旋转、缩放和空间锚定
- 增加 LOD、实例化、视锥剔除和异步资源加载
- 支持 Mac 端资产转换和局域网热更新

## Git 远程配置

当前仓库使用 GitHub SSH：

```bash
git remote -v
# origin  git@github.com:fyzel527/visionpro-jarvis.git
```

测试 GitHub SSH 身份：

```bash
ssh -T git@github.com
```
