# CelToon Shading Model — UE5.6 Integration Notes

> **适用引擎版本**：Unreal Engine 5.6 (vanilla, from `github.com/EpicGames/UnrealEngine`, tag `5.6.x`)
> **集成对象**：所有需要支持 `MSM_CelToon` 这个自定义 Shading Model 的位置
> **使用前提**：你必须已通过 Epic Games 账号合法获取 UE5.6 源码并签署 EULA。本仓库不包含任何 Unreal Engine 源码，只描述"在你自己的 UE5.6 源码中，应该在哪里加入什么"。

---

## 目录

- [1. Shading Model 枚举注册](#1-shading-model-枚举注册)
- [2. Shading Model 参数名映射](#2-shading-model-参数名映射)
- [3. Subsurface 集族归类](#3-subsurface-集族归类)
- [4. Custom GBuffer 数据标志](#4-custom-gbuffer-数据标志)
- [5. Shader Material 位字段声明](#5-shader-material-位字段声明)
- [6. HLSL Translator 环境定义](#6-hlsl-translator-环境定义)
- [7. Shading Model 名字字符串映射](#7-shading-model-名字字符串映射)
- [8. Shader 编译统计归类](#8-shader-编译统计归类)
- [9. Shader 编译标志提取](#9-shader-编译标志提取)
- [10. GBuffer Slot 配置](#10-gbuffer-slot-配置)
- [11. Material Expression 节点下拉菜单](#11-material-expression-节点下拉菜单)
- [12. Material Attribute 有效性表](#12-material-attribute-有效性表)
- [13. BasePass Common — 启用 CustomData / PrecomputedShadow 写入](#13-basepass-common--启用-customdata--precomputedshadow-写入)
- [14. BasePass 材质阶段 — GBuffer 打包块（原创 snippet）](#14-basepass-材质阶段--gbuffer-打包块原创-snippet)
- [15. GBuffer Hints 调试 HUD](#15-gbuffer-hints-调试-hud)
- [16. 材质面板 Pin 名本地化（HighlightIntensity / Offset / RimWidth）](#16-材质面板-pin-名本地化highlightintensity--offset--rimwidth)
- [17. Sky Lighting 固定色分支（原创 snippet）](#17-sky-lighting-固定色分支原创-snippet)
- [18. Reflection Environment 屏蔽反射与 AO 覆盖（原创 snippet）](#18-reflection-environment-屏蔽反射与-ao-覆盖原创-snippet)
- [19. GBuffer 解包 Metallic 引脚借用分叉（原创 snippet）](#19-gbuffer-解包-metallic-引脚借用分叉原创-snippet)
- [20. ToonBxDF — 卡通着色核心函数（原创 snippet）](#20-toonbxdf--卡通着色核心函数原创-snippet)
- [21. Lumen 暗部锁定（原创 snippet）](#21-lumen-暗部锁定原创-snippet)
- [22. BasePass 材质阶段：SubsurfaceData 分支扩展](#22-basepass-材质阶段subsurfacedata-分支扩展)
- [23. BasePass 材质阶段：SpecularColor / DiffuseColor 分叉（原创 snippet）](#23-basepass-材质阶段specularcolor--diffusecolor-分叉原创-snippet)
- [24. BasePass 翻译 Translucency 体积光条件扩展](#24-basepass-翻译-translucency-体积光条件扩展)
- [25. Deferred Lighting：静态阴影点积防御（原创 snippet）](#25-deferred-lighting静态阴影点积防御原创-snippet)
- [26. Deferred Lighting：CelToon Attenuation + 自阴影软化（原创 snippet）](#26-deferred-lightingceltoon-attenuation--自阴影软化原创-snippet)
- [27. Deferred Shading 类别归类（IsSubsurfaceModel / HasCustomGBufferData）](#27-deferred-shading-类别归类issubsurfacemodel--hascustomgbufferdata)
- [28. Deferred Shading GBuffer 解包分叉（原创 snippet）](#28-deferred-shading-gbuffer-解包分叉原创-snippet)

---

## 1. Shading Model 枚举注册

**文件**：`Engine/Source/Runtime/Engine/Classes/Engine/EngineTypes.h`  
**定位锚点**：`enum EMaterialShadingModel` 内，最后一项 `MSM_Strata` 之后、`MSM_NUM` 之前  
**作用**：在 UE 的 Shading Model 枚举里注册一个新的枚举项 `MSM_CelToon`，编辑器的材质 ShadingModel 下拉菜单里会出现 "Cel Shading"。

**插入内容**（这几行是本仓库作者原创）：

```cpp
///
/// 卡渲
///
MSM_CelToon  UMETA(DisplayName="Cel Shading"),
```

---

## 2. Shading Model 参数名映射

**文件**：`Engine/Source/Runtime/Engine/Private/Materials/MaterialIRToHLSLTranslator.cpp`  
**定位锚点**：`static const TCHAR* GetShadingModelParameterName(EMaterialShadingModel InModel)` 函数内的 switch，`case MSM_ThinTranslucent:` 之后、`default:` 之前  
**作用**：把枚举 `MSM_CelToon` 映射到 shader 端的宏名 `MATERIAL_SHADINGMODEL_CELTOON`，IR→HLSL 转换阶段需要这个映射才能在生成的 shader 里正确分支。

**插入内容**（这一行是本仓库作者原创）：

```cpp
case MSM_CelToon: return TEXT("MATERIAL_SHADINGMODEL_CELTOON");
```

---

## 3. Subsurface 集族归类

**文件**：`Engine/Source/Runtime/Engine/Public/MaterialShared.h`  
**定位锚点**：`inline bool IsSubsurfaceShadingModel(FMaterialShadingModelField ShadingModel)` 的 return 表达式末尾  
**作用**：把 `MSM_CelToon` 纳入"需要 Subsurface 处理分支"的 Shading Model 集合。这样 UE 的各种子表面相关代码路径会自动为 CelToon 打开（我们用它来通过 CustomData/SubsurfaceColor 通道携带卡通阴影参数）。

**修改方式**：在原函数 return 表达式的末尾**追加**下面这一项（用 `||` 连接）：

```cpp
|| ShadingModel.HasShadingModel(MSM_CelToon)
```

---

## 4. Custom GBuffer 数据标志

**文件**：`Engine/Source/Runtime/RenderCore/Private/ShaderMaterialDerivedHelpers.cpp`  
**定位锚点**：`Dst.WRITES_CUSTOMDATA_TO_GBUFFER = ...` 的布尔表达式末尾（`Mat.MATERIAL_SHADINGMODEL_EYE` 之后）  
**作用**：声明 CelToon Shading Model 需要写入 GBuffer 的 CustomData 通道（我们用 CustomData.a 存卡通阴影偏移量 ShadowOffset）。不加这项，RenderCore 不会为 CelToon 分配 CustomData 写入路径。

**修改方式**：在原赋值语句的表达式末尾**追加**下面这一项（用 `||` 连接）：

```cpp
|| Mat.MATERIAL_SHADINGMODEL_CELTOON
```

---

## 5. Shader Material 位字段声明

**文件**：`Engine/Source/Runtime/RenderCore/Public/ShaderMaterial.h`  
**定位锚点**：`FShaderMaterialPropertyDefines`（或等价结构体）内，`uint8 MATERIAL_SHADINGMODEL_THIN_TRANSLUCENT : 1;` 之后  
**作用**：为新 Shading Model 预留一个位字段，供 shader 编译时的派生宏生成使用。

**插入内容**（这一行是本仓库作者原创）：

```cpp
uint8 MATERIAL_SHADINGMODEL_CELTOON : 1;
```

---

## 6. HLSL Translator 环境定义

**文件**：`Engine/Source/Runtime/Engine/Private/Materials/HLSLMaterialTranslator.cpp`  
**定位锚点**：生成 shader Environment defines 的那段 if-链里，处理 `MSM_ThinTranslucent` 的 `if (EnvironmentDefines->HasShadingModel(MSM_ThinTranslucent)) { ... }` 块**之后**  
**作用**：当材质使用 CelToon shading model 时，为其 HLSL 编译环境追加 `MATERIAL_SHADINGMODEL_CELTOON=1` 宏定义，shader 端的 `#if MATERIAL_SHADINGMODEL_CELTOON` 分支才能被激活。

**插入内容**（这一 if-block 是本仓库作者按 Epic 现有样板格式添加的）：

```cpp
if (EnvironmentDefines->HasShadingModel(MSM_CelToon))
{
    OutEnvironment.SetDefine(TEXT("MATERIAL_SHADINGMODEL_CELTOON"), TEXT("1"));
}
```

---

## 7. Shading Model 名字字符串映射

**文件**：`Engine/Source/Runtime/Engine/Private/Materials/MaterialShader.cpp`  
**定位锚点**：`FString GetShadingModelString(EMaterialShadingModel ShadingModel)` 内的 switch，`case MSM_ThinTranslucent:` 之后、`default:` 之前  
**作用**：让调试 / 日志里能把 `MSM_CelToon` 打印成 `"MSM_CelToon"`。

**插入内容**：

```cpp
case MSM_CelToon:           ShadingModelName = TEXT("MSM_CelToon"); break;
```

---

## 8. Shader 编译统计归类

**文件**：`Engine/Source/Runtime/Engine/Private/Materials/MaterialShader.cpp`  
**定位锚点**：`void UpdateMaterialShaderCompilingStats(...)` 里那句 `else if (ShadingModels.HasAnyShadingModel({ ... }))` 列表。  
**作用**：把 CelToon 也算进"Lit"类材质的编译统计里，避免它被归类成"Unlit/Unknown"。

**修改方式**：在 `HasAnyShadingModel({ ... })` 的初始化列表末尾追加 `MSM_CelToon`。例如原表达式末尾是 `..., MSM_ThinTranslucent }`，改成 `..., MSM_ThinTranslucent, MSM_CelToon }`。

---

## 9. Shader 编译标志提取

**文件**：`Engine/Source/Runtime/Engine/Private/ShaderCompiler/ShaderGenerationUtil.cpp`  
**定位锚点**：一连串 `FETCH_COMPILE_BOOL(MATERIAL_SHADINGMODEL_*)` 宏调用末尾，`FETCH_COMPILE_BOOL(MATERIAL_SHADINGMODEL_THIN_TRANSLUCENT);` 之后  
**作用**：把新引入的 `MATERIAL_SHADINGMODEL_CELTOON` 编译标志注册到 shader 编译器的布尔提取表里。

**插入内容**：

```cpp
FETCH_COMPILE_BOOL(MATERIAL_SHADINGMODEL_CELTOON);
```

---

## 10. GBuffer Slot 配置

**文件**：`Engine/Source/Runtime/Engine/Private/ShaderCompiler/ShaderGenerationUtil.cpp`  
**定位锚点**：为各 Shading Model 设置 GBuffer slot 的 if-链里，处理 `MSM_Subsurface` 的 `if (Mat.MATERIAL_SHADINGMODEL_SUBSURFACE) { ... }` 块**之后**  
**作用**：为 CelToon 分配标准 GBuffer slots 并启用 CustomData slot（我们用 CustomData.a 存 ShadowOffset，其它通道可留作未来扩展）。

**插入内容**（if-block 由作者按 Epic 样板构造）：

```cpp
if (Mat.MATERIAL_SHADINGMODEL_CELTOON)
{
    SetStandardGBufferSlots(Slots, bWriteEmissive, bHasTangent, bHasVelocity, bWritesVelocity, bHasStaticLighting, bIsSubstrateMaterial, bIsSubstrateNewGBuffer);
    Slots[GBS_CustomData] = GetGBufferSlotUsage(bUseCustomData);
}
```

---

## 11. Material Expression 节点下拉菜单

**文件**：`Engine/Source/Runtime/Engine/Public/Materials/MaterialExpressionShadingModel.h`  
**定位锚点**：`UMaterialExpressionShadingModel` 内那个 `UPROPERTY(EditAnywhere, Category=ShadingModel, meta=(ValidEnumValues="...", ShowAsInputPin="Primary"))` 的 `ValidEnumValues` 字符串。  
**作用**：让材质编辑器里 `Shading Model` 节点的下拉选项增加 "Cel Shading" 一项，不加的话用户无法在材质图里切到新 shading model。

**修改方式**：在 `ValidEnumValues` 字符串末尾追加 `, MSM_CelToon`。例如：

- 原：`ValidEnumValues="MSM_DefaultLit, MSM_Subsurface, ..., MSM_Eye"`  
- 改：`ValidEnumValues="MSM_DefaultLit, MSM_Subsurface, ..., MSM_Eye, MSM_CelToon"`

---

## 12. Material Attribute 有效性表

**文件**：`Engine/Source/Runtime/Engine/Private/Materials/Material.cpp`  
**定位锚点**：`UMaterial::IsPropertyActive_Internal(...)` 内依照 `EMaterialProperty` 分发的 switch，下面三个 `case` 的 `HasAnyShadingModel({ ... })` 列表：`MP_SubsurfaceColor` / `MP_CustomData0` / `MP_CustomData1`  
**作用**：告诉材质编辑器，CelToon 材质的 SubsurfaceColor / CustomData0 / CustomData1 三个 pin 应该被视为"活跃"（可以接线、能参与编译）。

**修改方式**：在这三个 case 的初始化列表末尾各**追加** `MSM_CelToon`：

```cpp
// MP_SubsurfaceColor
Active = ShadingModels.HasAnyShadingModel({ MSM_Subsurface, MSM_PreintegratedSkin, MSM_TwoSidedFoliage, MSM_Cloth, MSM_CelToon });

// MP_CustomData0
Active = ShadingModels.HasAnyShadingModel({ MSM_ClearCoat, MSM_Hair, MSM_Cloth, MSM_Eye, MSM_SubsurfaceProfile, MSM_CelToon });

// MP_CustomData1
Active = ShadingModels.HasAnyShadingModel({ MSM_ClearCoat, MSM_Eye, MSM_CelToon });
```

---

## 13. BasePass Common — 启用 CustomData / PrecomputedShadow 写入

**文件**：`Engine/Shaders/Private/BasePassCommon.ush`  
**作用**：(a) 让 CelToon 的 CustomData（SubsurfaceColor + ShadowOffset）能被写入 GBuffer D；(b) 借用 GBuffer E（PrecomputedShadowFactors）存卡通附加参数，即使项目没用 Lightmap 烘焙也强制写。

### 13.1 `WRITES_CUSTOMDATA_TO_GBUFFER` 宏

**定位锚点**：现有 `#define WRITES_CUSTOMDATA_TO_GBUFFER (USES_GBUFFER && (..._SUBSURFACE || ... || ..._EYE))`  
**修改方式**：在末尾 OR 链追加 `|| MATERIAL_SHADINGMODEL_CELTOON`。

### 13.2 `WRITES_PRECSHADOWFACTOR_TO_GBUFFER` 宏（配上 2 行设计注释）

**定位锚点**：现有 `#define WRITES_PRECSHADOWFACTOR_TO_GBUFFER (GBUFFER_HAS_PRECSHADOWFACTOR && !WRITES_PRECSHADOWFACTOR_ZERO)`  
**修改方式**：在这个 `#define` 前面加两行中文注释，并把宏体改成：

```glsl
// CelToon 借用 GBuffer E 存卡通参数（HighlightIntensity/RimWidth），即便没有 Lightmap 也强制写入。
// 前提：项目保证不用 Lightmap 烘焙（灯光 ShadowMapChannelMask=0，原语义闲置）。
#define WRITES_PRECSHADOWFACTOR_TO_GBUFFER (GBUFFER_HAS_PRECSHADOWFACTOR && (!WRITES_PRECSHADOWFACTOR_ZERO || MATERIAL_SHADINGMODEL_CELTOON))
```

---

## 14. BasePass 材质阶段 — GBuffer 打包块（原创 snippet）

**文件**：`Engine/Shaders/Private/ShadingModelsMaterial.ush`  
**定位锚点**：函数 `SetGBufferForShadingModel(...)`（或 UE5.6 对应的等价函数）中，最后一个 `else if (ShadingModel == ...) { ... }` 分支之后、关闭外层 `#if` 的 `#endif` 之前  
**作用**：CelToon 的完整 GBuffer 打包协议 —— 包括 CustomData.rgb 存阴影色 / CustomData.a 存 ShadowOffset / PrecomputedShadowFactors 借用 4 个通道存 HighlightIntensity 等参数。配套的解包请看 §17 / §18 等小节。

**集成方式**：整块拷贝 `snippets/shaders/ShadingModelsMaterial__CelToon_GBufferPacking.ush` 的内容（全文由本仓库作者原创，MIT 许可），放在上述定位位置。

---

## 15. GBuffer Hints 调试 HUD

**文件**：`Engine/Shaders/Private/PostProcessGBufferHints.usf`  
**作用**：UE 的 GBuffer 可视化 HUD 里把 CelToon 分类进去，让调试时能看到 "CELTOON" 标签 + 两个自定义通道值。

### 15.1 `PrintShadingMode(...)` 的 if 链

**定位锚点**：紧接在 `if (In == SHADINGMODELID_SUBSTRATE) { Print(..., "SUBSTRATE", ...); return; }` 之后、`if (In == SHADINGMODELID_NUM) { ... }` 之前  
**插入内容**：

```glsl
if (In == SHADINGMODELID_CELTOON) { Print(Ctx, TEXT("CELTOON"), FontRed); return; }
```

### 15.2 Custom Data 面板里的 else-if 分支

**定位锚点**：同函数（`PrintDebugInfo` 或其调用处）里那一串 `else if (Data.ShadingModelID == SHADINGMODELID_XXX) { ... }` 的末尾  
**插入内容**（5 行 else-if 分支，由作者按 Epic 样板结构构造）：

```glsl
else if (Data.ShadingModelID == SHADINGMODELID_CELTOON)
{
    Print(Ctx, TEXT("CelToon SSS Color : "), FontWhite); Print(Ctx, ExtractSubsurfaceColor(Data), FontYellow); Newline(Ctx, RectMax);
    Print(Ctx, TEXT("CelToon Range     : "), FontWhite); Print(Ctx, Data.CustomData.a, FontYellow); Newline(Ctx, RectMax);
}
```

---

## 16. 材质面板 Pin 名本地化（HighlightIntensity / Offset / RimWidth）

**文件**：`Engine/Source/Runtime/Engine/Private/Materials/MaterialAttributeDefinitionMap.cpp`  
**定位锚点**：`FMaterialAttributeDefinitionMap::GetAttributeOverrideForMaterial(...)` 里按 `EMaterialProperty` 分发的 switch，下面四个 `case`：`MP_Metallic` / `MP_SubsurfaceColor` / `MP_CustomData0` / `MP_CustomData1`  
**作用**：当材质选中 CelToon shading model 时，把编辑器里这些 pin 的默认名字换成我们实际借用的语义，便于美术使用。

**修改方式**：在这四个 case 里原有 `CustomPinNames.Add({ ... });` 序列中各**追加**一行（为可读性，`MP_Metallic` 和 `MP_CustomData1` 的插入行额外加 1 行中文注释说明意图）：

```cpp
// case MP_Metallic  —— 在现有 Hair/Eye 两行 Add 之后插入：
// CelToon 借用 Metallic 引脚存 HighlightIntensity（GBuffer E .r、[0,1]映射到 [0,8]）
CustomPinNames.Add({ MSM_CelToon, LOCTEXT("CelToonHighlightIntensity", "Highlight Intensity").ToString() });

// case MP_SubsurfaceColor —— 在 MSM_Cloth 行之前/之后任意位置插入：
CustomPinNames.Add({ MSM_CelToon, LOCTEXT("CelToonSubsurfaceColor", "CelToon Subsurface Color").ToString() });

// case MP_CustomData0 —— 在第一行 Add（ClearCoat）之前插入：
CustomPinNames.Add({ MSM_CelToon, LOCTEXT("CelToonOffset", "Offset").ToString() });

// case MP_CustomData1 —— 在 MSM_Eye 行之后插入（含 1 行中文注释）：
// CelToon 借用 CustomData1 引脚存 RimWidth（GBuffer E .g、[0,1]映射到 [0,0.5]）
CustomPinNames.Add({ MSM_CelToon, LOCTEXT("CelToonRimWidth", "Rim Width").ToString() });
```

---

## 17. Sky Lighting 固定色分支（原创 snippet）

**文件**：`Engine/Shaders/Private/SkyLightingDiffuseShared.ush`  
**定位锚点**：`SkyLightDiffuse(...)` 内，Epic 原有 `if (GBuffer.ShadingModelID == SHADINGMODELID_SUBSURFACE || ... PREINTEGRATED_SKIN)` 块**之后**、`if (GBuffer.ShadingModelID == SHADINGMODELID_HAIR)` 之前（任何能保证 early-return 先于方向性采样的位置皆可）  
**作用**：非 Lumen 路径下（`ReflectionEnvironmentPixelShader.usf` 调用的这条分支），让 CelToon 的天光贡献变成**固定色** = BaseColor × SubsurfaceColor × SkyLightColor × Scale；与 Lumen 路径下 `DiffuseIndirectComposite.usf` 的固定色策略对齐，保证暗部永远是纯色块，不被 BentNormal/AO 污染。

**集成方式**：整块拷贝 `snippets/shaders/SkyLightingDiffuseShared__CelToon_SkyLightingBranch.ush` 到指定位置。全文由本仓库作者原创、MIT 许可。

---

## 18. Reflection Environment 屏蔽反射与 AO 覆盖（原创 snippet）

**文件**：`Engine/Shaders/Private/ReflectionEnvironmentPixelShader.usf`  
**作用**：CelToon 材质
  - **屏蔽反射环境**：避免 SSR / Lumen Reflections / 反射捕获给 CelToon 添加金属质感
  - **AO = 1.0**：避免 AO 在 CelToon 暗部叠加第二层环境阴影
  - 以及一段注释解释"天光固定色由 §17 的 `SkyLightDiffuse` 分支产出"

**集成方式**：打开 `snippets/shaders/ReflectionEnvironment__CelToon_Overrides.usf`，按里面的 Block A / Block B 说明插入两处。全文由本仓库作者原创、MIT 许可。

---

## 19. GBuffer 解包 Metallic 引脚借用分叉（原创 snippet）

**文件**：`Engine/Shaders/Private/GBufferHelpers.ush`  
**作用**：因为 CelToon 借用 Metallic 材质引脚存 `HighlightIntensity`，所有 GBuffer 解包/派生阶段里依赖 Metallic 的计算都必须对 CelToon 单独处理，否则 HighlightIntensity 会被当成真实金属度：

- **Block A**：`DiffuseColor` 初值派生 — CelToon 走 `OriginalBaseColor`
- **Block B**：`PrecomputedShadowFactors` 跳过 `SelectiveOutputMask` 覆写（保护借用来的 GBuffer E）
- **Block C**：`SpecularColor` / `DiffuseColor` 最终派生 — CelToon 强制按 Metallic=0 计算

**集成方式**：打开 `snippets/shaders/GBufferHelpers__CelToon_MetallicReuse_Overrides.ush`，按里面的三个 Block 依次在对应位置插入或替换。全文由本仓库作者原创、MIT 许可。

---

## 20. ToonBxDF — 卡通着色核心函数（原创 snippet）

**文件**：`Engine/Shaders/Private/ShadingModels.ush`  
**作用**：整个 CelToon 方案的**核心光照函数**。实现三次阈值化（漫反射/高光/边缘光）+ ShadowOffset 平移 + HighlightIntensity/RimWidth 从 GBuffer E 读取。

**集成方式**：按 `snippets/shaders/ShadingModels__ToonBxDF.ush` 内的 Part 1 / Part 2 两处插入：
- **Part 1**：`ToonStep` helper + `ToonBxDF` 完整实现 → 插在 `PreintegratedSkinBxDF` 函数之后、`IntegrateBxDF` 函数之前
- **Part 2**：在 `IntegrateBxDF` 的 switch 里，紧跟 `case SHADINGMODELID_EYE:` 之后、`default:` 之前加一个 case：

```cpp
case SHADINGMODELID_CELTOON:
    return ToonBxDF(GBuffer, N, V, L, Falloff, NoL, AreaLight, Shadow);
```

全文由本仓库作者原创，MIT 许可。算法骨架参考 UE5.7 公开文档的 Toon Shading 思路（smoothstep 三次阈值化 + Blinn 高光 + Rim），实现细节与参数映射全部独立完成。

---

## 21. Lumen 暗部锁定（原创 snippet）

**文件**：`Engine/Shaders/Private/DiffuseIndirectComposite.usf`  
**定位锚点**：主 pass（非 Substrate 分支）里 Epic 现有 `if (GBuffer.ShadingModelID == SHADINGMODELID_CLOTH)` 块之后，`IndirectLighting.Diffuse = ...;` 赋值之后  
**作用**：Lumen 场景下让 CelToon 的 IndirectLighting 变成**固定色** = BaseColor × SubColor × SHADOW_AMBIENT。彻底绕开 Lumen GI / Occlusion / EnergyPreservationFactor 等所有场景相关因素，保证暗部是一块恒定的纯色，不被 Lumen 的间接光污染。与 §17 的非 Lumen 路径策略保持一致。

**集成方式**：按 `snippets/shaders/DiffuseIndirectComposite__CelToon_ShadowLock.usf` 内的 Block A / Block B 两处插入。全文原创、MIT 许可。

---

## 22. BasePass 材质阶段：SubsurfaceData 分支扩展

**文件**：`Engine/Shaders/Private/BasePassPixelShader.usf`  
**作用**：让 CelToon 材质也能走 `GetMaterialSubsurfaceData(...)` 取出 SubsurfaceColor（我们把卡通阴影色放在这里）。

### 22.1 外层 `#if` 宏 + 进入条件

**定位锚点**：Epic 原代码（`!SUBSTRATE_ENABLED` 分支内）中的：
```cpp
#if MATERIAL_SHADINGMODEL_SUBSURFACE || ... || MATERIAL_SHADINGMODEL_EYE
if (ShadingModel == SHADINGMODELID_SUBSURFACE || ... || ShadingModel == SHADINGMODELID_EYE)
```
**修改方式**：两个地方都追加 `|| MATERIAL_SHADINGMODEL_CELTOON` / `|| ShadingModel == SHADINGMODELID_CELTOON`。

### 22.2 Cloth 分支合并 CelToon

**定位锚点**：`#if MATERIAL_SHADINGMODEL_CLOTH / else if (ShadingModel == SHADINGMODELID_CLOTH) { SubsurfaceColor = SubsurfaceData.rgb; }` 块  
**修改方式**：把 `#if` 和 `else if` 两行各追加 `|| MATERIAL_SHADINGMODEL_CELTOON` / `|| ShadingModel == SHADINGMODELID_CELTOON`。表达式原样重用 Cloth 的 `SubsurfaceColor = SubsurfaceData.rgb;` 语义。

---

## 23. BasePass 材质阶段：SpecularColor / DiffuseColor 分叉（原创 snippet）

**文件**：`Engine/Shaders/Private/BasePassPixelShader.usf`  
**作用**：与 §19 是对偶关系 —— §19 处理的是 Decode 阶段（从 GBuffer 读回），这里处理的是 Encode 阶段（写入 GBuffer 前的 Metallic 派生）。同样因为 CelToon 借用 Metallic 存 HighlightIntensity，必须分叉。

**集成方式**：按 `snippets/shaders/BasePassPixelShader__CelToon_MetallicReuse_Overrides.usf` 内的 Block A / Block B 两处各替换 Epic 原有的一行赋值。全文原创、MIT 许可。

---

## 24. BasePass 翻译 Translucency 体积光条件扩展

**文件**：`Engine/Shaders/Private/BasePassPixelShader.usf`  
**定位锚点**：Epic 原有那一行 `if (GBuffer.ShadingModelID == SHADINGMODELID_DEFAULT_LIT || GBuffer.ShadingModelID == SHADINGMODELID_SUBSURFACE) { Color += GetTranslucencyVolumeLighting(...); }`  
**作用**：让 CelToon 翻译材质也能取到体积光贡献。

**修改方式**：在 if 条件末尾追加 `|| GBuffer.ShadingModelID == SHADINGMODELID_CELTOON`。

---

## 25. Deferred Lighting：静态阴影点积防御（原创 snippet）

**文件**：`Engine/Shaders/Private/DeferredLightingCommon.ush`  
**作用**：CelToon 借用 GBuffer E 存卡通参数后，如果美术误设灯光 `ShadowMapChannelMask` 非 0，原本的 `dot(ShadowMapChannelMask, half4(1,1,1,1))` 会把"HighlightIntensity"通道错当静态阴影读。这里通过扩展 `GetShadowTermsBase` 的签名加一个 `ShadingModelID` 默认参数，在 CelToon 分支下强制把 `UsesStaticShadowMap = 0`，彻底屏蔽点积路径。

**集成方式**：按 `snippets/shaders/DeferredLightingCommon__CelToon_StaticShadowGuard.ush` 的 Block A/B/C 三处改动集成。其中 Block A 是函数签名扩展（加默认参数），Block B 是函数体内的三元表达式替换，Block C 是上层 `GetShadowTerms` 调用处把 `ShadingModelID` 传下去。全文原创、MIT 许可。

---

## 26. Deferred Lighting：CelToon Attenuation + 自阴影软化（原创 snippet）

**文件**：`Engine/Shaders/Private/DeferredLightingCommon.ush`  
**作用**：
- **Block A**：CelToon 材质不再受点光/聚光的物理距离衰减（`Attenuation = 1.0f`），光强只由 ToonBxDF 内部的 NoL 阈值决定，符合卡通语义
- **Block B**：对 CSM / VSM 产生的 `SurfaceShadow` / `TransmissionShadow` 做一次 smoothstep 软化（阈值 0.5，Softness 复用 ToonBxDF 的 Roughness 后半段），让阴影边界与 BxDF 色阶同频，避免"硬锯齿+卡通硬切"的双重割裂

**集成方式**：按 `snippets/shaders/DeferredLightingCommon__CelToon_ShadowSoftening.ush` 的 Block A / Block B 两处插入到桌面端 DeferredLighting 主循环里。全文原创、MIT 许可。

---

## 27. Deferred Shading 类别归类（IsSubsurfaceModel / HasCustomGBufferData）

**文件**：`Engine/Shaders/Private/DeferredShadingCommon.ush`  
**作用**：把 CelToon 归入"子表面散射类模型"和"需要 CustomData 的模型"，这样 shader 端各路径判断都能正确识别 CelToon。

### 27.1 `IsSubsurfaceModel(int ShadingModel)`

**修改方式**：在 return 表达式的 OR 链末尾追加 `|| ShadingModel == SHADINGMODELID_CELTOON`。

### 27.2 `HasCustomGBufferData(int ShadingModelID)`

**修改方式**：在 return 表达式的 OR 链末尾追加 `|| ShadingModelID == SHADINGMODELID_CELTOON`。

---

## 28. Deferred Shading GBuffer 解包分叉（原创 snippet）

**文件**：`Engine/Shaders/Private/DeferredShadingCommon.ush`  
**作用**：DeferredShadingCommon 里有两条 GBuffer 解包路径（Mobile & Desktop），都依赖 Metallic 派生 F0 / DiffuseColor。因为 CelToon 借用 Metallic 存 HighlightIntensity，两条路径都必须分叉；同时 Desktop 路径里 `PrecomputedShadowFactors` 的读回也必须对 CelToon 跳过 `SelectiveOutputMask` 的 fallback（保护借来存 HighlightIntensity 的 GBuffer E）。

**集成方式**：按 `snippets/shaders/DeferredShadingCommon__CelToon_MetallicReuse_Overrides.ush` 的 Block A / B / C 三处在对应函数里替换原块：
- **Block A**：Mobile 解包路径的 F0 / DiffuseColor 分叉
- **Block B**：Desktop 路径的 `PrecomputedShadowFactors` 强读（跳过 `SelectiveOutputMask`）
- **Block C**：Desktop 路径的 F0 / DiffuseColor 分叉（含 SubsurfaceProfile 兼容逻辑）

全文原创、MIT 许可。Block B/C 与 `snippets/shaders/GBufferHelpers__CelToon_MetallicReuse_Overrides.ush` 的 Block B/C 是同一问题在不同文件里的对应改动。

---
