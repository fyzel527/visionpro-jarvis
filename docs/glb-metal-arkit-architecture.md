# GLB + Metal + ARKit 三维全息展示方案

## 目标

构建一个运行在 Apple Vision Pro 上的高质量科幻全息 HUD 系统：

- macOS 负责三维资产导入、修复、材质处理、转换和打包。
- Vision Pro 负责运行时资产加载、ARKit 姿态/手势捕捉和 Metal 双目渲染。
- 最终视觉效果由 Metal Shader、粒子和后处理实现，而不是依赖模型格式自带的外观。

## 总体架构

```text
OBJ / FBX / USD / Blender / CAD
                |
                v
       macOS 资产处理工具
       - 格式导入
       - 坐标和单位统一
       - 法线/切线/UV 修复
       - 材质和贴图整理
       - LOD 和网格优化
       - GLB 导出与校验
                |
                v
          GLB 运行时资源
                |
       安装、缓存或局域网传输
                |
                v
          Vision Pro App
       - Model I/O / GLB 加载
       - PBR 基础材质
       - 全息 Metal Shader
       - Compositor Services 双目输出
       - ARKit 世界追踪
       - ARKit 手势追踪
       - 手势驱动的场景交互
```

## 格式策略

### 源格式

以下格式作为创作和工业资产的输入格式保留在 macOS 端：

- OBJ：静态网格，通常包含 `.obj`、`.mtl` 和外部贴图。
- FBX：复杂层级、骨骼和动画交换格式。
- USD/USDZ：复杂场景、装配关系、变体和 Apple 工作流。

这些格式不在 Vision Pro 运行时直接解析，尤其不在设备端引入 FBX 解析器。

### 运行时格式：GLB

GLB 是 glTF 的单文件二进制容器，可以将场景 JSON、网格数据、材质和贴图打包到一个文件中。

GLB 可承载：

- 多节点和多子网格
- UV、法线和切线
- Base Color / Albedo
- Normal Map
- Metallic/Roughness
- Ambient Occlusion
- Emissive
- Alpha/透明
- 骨骼和基础动画

GLB 的优势是传输、缓存和加载简单；它不是最终视觉效果的限制。全息边缘光、扫描线、噪声溶解、色散、粒子和发光叠加由 Metal 实现。

## macOS 资产处理边界

Mac 端工具负责：

1. 导入 OBJ、FBX、USD 和贴图。
2. 统一单位为米，坐标约定为 Y-up、前方 -Z。
3. 应用旋转和缩放，生成或修复法线、切线和 UV。
4. 将材质映射为 glTF PBR Metallic-Roughness 模型。
5. 打包贴图，优先生成单文件 GLB。
6. 为复杂模型生成 LOD、简化网格和实例数据。
7. 校验缺失贴图、异常法线、空 UV 和过高面数。
8. 输出资产元数据，例如默认缩放、包围盒、动画和材质列表。

建议使用 Blender/Blender Python 作为第一版转换工具链，并使用 glTF Transform 做压缩和校验。

## Vision Pro 运行时

运行时使用当前的 Compositor Services + Metal 架构：

- `CompositorLayer` 创建空间渲染层。
- 根据设备能力选择 layered 或 dedicated stereo layout。
- 使用预测帧时间和 device anchor 保证双目姿态正确。
- `Model I/O` 加载 GLB，遍历所有 `MDLMesh` 和 submesh。
- 将 GLB 材质转换为 Metal 纹理和材质参数。
- 使用深度、透明混合和双目投影完成空间显示。

当前代码入口：

- `JarvisMetalImmersiveContent.swift`
- `SpatialRenderingEngine.mm`
- `SpatialRenderer.mm`

## ARKit 手势链路

手势捕捉不依赖 RealityKit：

```text
ARKit HandTrackingProvider
        -> HandTrackingModel
        -> C/Objective-C++ bridge
        -> 线程安全手势快照
        -> SpatialRenderer
        -> Metal 场景变换、材质和粒子参数
```

首批手势：

- Pinch：移动/抓取目标，后续可扩展为选择和旋转。
- Palm Open：提高全息场景尺度或亮度。
- Two Hand Expand：整体展开、缩放或打开多层 HUD。

渲染线程只读取最新快照，不阻塞 ARKit 更新线程。

## Metal 全息表现

GLB 提供基础几何和 PBR 纹理，Metal 在其上叠加：

- Fresnel 边缘发光
- 冷青主色和琥珀高光
- 程序化噪声和动态扫描
- 噪声驱动消融与光屑
- 局部 RGB 色散
- 发光、透明和加法混合
- GPU 粒子和指尖粒子
- 手势驱动的亮度、溶解和状态动画

建议的材质分层：

```text
GLB PBR base
    + Fresnel
    + holographic noise
    + scan / dissolve
    + emissive pulse
    + particles / post effect
```

## 资产传输

第一阶段支持：

- Xcode 安装到 Vision Pro
- App Bundle 内置 GLB

第二阶段可增加 Mac 资产服务端和 Vision Pro 客户端：

```text
Mac Asset Server --(Bonjour/TCP/WebSocket)--> Vision Pro Client
```

传输单位优先使用完整 GLB，而不是分别传输 OBJ、MTL 和贴图。Vision Pro 侧下载后校验 checksum，写入本地缓存，再通知 Metal 加载。

## 实施阶段

### 阶段一：GLB 基础加载

- 支持多个 mesh 和 submesh。
- 读取 GLB 内嵌贴图。
- 支持 Base Color、Normal、Metallic/Roughness。
- 修复当前只取第一个 `MDLMesh` 的限制。

### 阶段二：Metal 全息材质

- 建立统一 `MeshMaterial` 结构。
- 在 Metal Shader 中实现 PBR + Fresnel。
- 加入噪声、扫描、溶解和发光参数。
- 处理透明排序和深度策略。

### 阶段三：ARKit 交互

- 将 Pinch、Palm Open、Two Hand Expand 接入 Metal。
- 增加模型拾取、移动、旋转和缩放。
- 将交互状态映射到材质和粒子参数。

### 阶段四：复杂场景优化

- LOD、视锥剔除和遮挡剔除。
- GPU instancing。
- 异步加载和纹理流式处理。
- KTX2/BasisU 纹理压缩。
- 多模型场景、动画和空间锚点。

### 阶段五：Mac 实时资产服务

- Mac 端导入和转换 OBJ/FBX/USD。
- 自动打包 GLB 和元数据。
- 局域网或 USB 网络传输。
- Vision Pro 端热更新和资源缓存。

## 设计结论

采用 **OBJ/FBX/USD 作为 Mac 端源格式，GLB 作为运行时格式，Metal 作为最终全息渲染器，ARKit 作为姿态和手势输入层**。

GLB 足够承载高质量科幻模型；展示效果由 Metal 的材质、Shader、粒子、后处理和交互系统决定。RealityKit 不再是手势交互的必要依赖，可保留为原型和对照路径，但正式展示路径以 Metal + ARKit 为准。
