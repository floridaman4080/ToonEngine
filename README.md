# CelToon Shading Model for Unreal Engine 5.6

> 一个面向 UE5.6 引擎源码的**卡通渲染 Shading Model 集成规范 + 原创着色代码片段**。
> 本仓库**不包含** Unreal Engine 源码，只描述"在你自己合法获取的 UE5.6 源码上，应该在哪里加入什么"。

> **关于注释**：本仓库所有代码片段（`snippets/`）与集成说明（`integration_notes.md`）中的**中英文注释与行内说明均由 AI 辅助生成并由作者审校**；算法实现与架构决策由作者负责，AI 主要用于把设计意图转写为可读注释。如在注释中发现不准确之处，请开 issue 反馈。

---

## 这个仓库是什么

本仓库提供一套把 `MSM_CelToon`（Cel Shading）注册为 UE5.6 官方 Shading Model 的完整方案，包括：

- **`integration_notes.md`**：28 个集成段落，逐条说明需要在 UE5.6 源码的哪个文件、哪个函数、哪个位置做什么修改（大部分是"在 Epic 现有 enum / switch / OR 链末尾再加一项 CelToon"这种胶水工作，本质上是样板扩展）
- **`snippets/shaders/*.ush` / `*.usf`**：10 个原创着色代码片段（MIT 许可），包括核心的 `ToonBxDF`、Lumen 暗部锁定、阴影边界软化、GBuffer 打包协议等

按顺序阅读 `integration_notes.md` 即可落地。关键的原创逻辑全部在 `snippets/`，可直接 copy-paste 到引擎对应位置。

---

## 它解决了什么问题

UE5.6 自带的 `MSM_DefaultLit` / `MSM_Subsurface` 等 Shading Model 无法满足卡通渲染的四个核心诉求：

1. **三段式硬色阶**（亮面 / 暗面 / 阴影边界）— 需要 smoothstep 阈值化，而非 PBR 连续阴影
2. **暗部颜色锁定**— 暗面不能被 Lumen GI / AO / BentNormal 污染，必须保持纯色
3. **高光 / 边缘光可美术控制**— 需要额外的材质参数通道（HighlightIntensity、RimWidth）
4. **与 UE 现有灯光 / 阴影 / 反射管线深度协作**— 不能只改 BxDF，CSM 阴影、反射环境、天光等都要配套调整

本方案通过：

- 在 `EMaterialShadingModel` 里新注册 `MSM_CelToon`
- 复用 `GBuffer D`（CustomData）存阴影色 + ShadowOffset
- **借用 `GBuffer E`（PrecomputedShadowFactors）**存 HighlightIntensity 和 RimWidth（前提：项目不使用 Lightmap 烘焙）
- 分叉所有依赖 Metallic 的派生路径（因为 Metallic 引脚被借作 HighlightIntensity）
- 覆盖 Lumen / SkyLighting / ReflectionEnvironment 三条间接光链路为固定色

实现一个**不改变 UE 原模型运行结果、与 Lumen/VSM/CSM/Forward+ 兼容**的卡通 Shading Model。

---

## 使用前提

1. 你必须已通过 Epic Games 账号合法获取 UE5.6 源码并同意 [Unreal Engine End User License Agreement](https://www.unrealengine.com/en-US/eula/unreal)
2. 本仓库所有修改目标都指向 UE5.6 源码（vanilla，`github.com/EpicGames/UnrealEngine` tag `5.6.x`），不适用于 5.5 或 5.7
3. 本仓库**不包含**任何 Epic 版权代码；你需要自行编辑你本地的 UE 源码树

---

## 快速上手

```
  你的本地 UE5.6 源码              本仓库
     E:\...\UnrealEngine-5.6    <---    integration_notes.md
                                        snippets/
```

1. **读 `integration_notes.md`**，按 §1 到 §28 顺序，在你的本地 UE5.6 源码里做对应修改。每节都给出：
   - 目标文件相对路径
   - 精确定位锚点（如"`MSM_Strata` 之后、`MSM_NUM` 之前"）
   - 具体插入内容或修改方式

2. **对于带"原创 snippet"标记的节**（§14 / §17 / §18 / §19 / §20 / §21 / §23 / §25 / §26 / §28），打开 `snippets/shaders/` 下的对应文件，按文件顶部注释里的 **Block A / B / C** 说明逐块集成。

3. **编译 `UnrealEditor` Win64 Development**，验证新 Shading Model 可用。

4. **材质侧使用**：
   - 创建 Material，Shading Model 选 "Cel Shading"
   - 接线约定：
     - `SubsurfaceColor` → 阴影色
     - `CustomData0` → ShadowOffset [0,1]，运行时映射到 [-1,1]
     - `Metallic` → HighlightIntensity [0,1]，运行时放大到 [0,8]
     - `CustomData1` → RimWidth [0,1]，运行时压缩到 [0,0.5]

---

## 设计要点速查

| 主题 | 参考文档小节 | 原创 snippet |
|------|:---:|:---|
| 新 Shading Model 注册 | §1–§11 | — |
| GBuffer 打包协议 | §14 | `ShadingModelsMaterial__CelToon_GBufferPacking.ush` |
| 卡通 BxDF 核心算法 | §20 | `ShadingModels__ToonBxDF.ush` |
| Lumen 暗部锁定 | §21 | `DiffuseIndirectComposite__CelToon_ShadowLock.usf` |
| 非 Lumen 天光固定色 | §17 | `SkyLightingDiffuseShared__CelToon_SkyLightingBranch.ush` |
| 反射屏蔽 + AO 覆盖 | §18 | `ReflectionEnvironment__CelToon_Overrides.usf` |
| 自阴影边界软化 | §26 | `DeferredLightingCommon__CelToon_ShadowSoftening.ush` |
| GBuffer E 借用防御 | §13 / §25 / §28 (Block B) | `DeferredLightingCommon__CelToon_StaticShadowGuard.ush` |
| Metallic 引脚借用分叉 | §19 / §23 / §28 | 三个 `*MetallicReuse_Overrides.*` 文件 |

---

## 许可

- **本仓库全部文件（`integration_notes.md` + `snippets/**`）采用 MIT 许可**，详见 [`LICENSE`](LICENSE)
- **不承诺与 Unreal Engine 源码的兼容性**，版本号限定 UE5.6；未来 UE 版本可能需要重新定位锚点
- **本仓库作者与 Epic Games 无任何关联**

---

## 版本 & 路线图

当前版本：`v0.1.0-initial`（首次发布，完整覆盖 22 个目标文件）。更多见 [`CHANGELOG.md`](CHANGELOG.md)。
