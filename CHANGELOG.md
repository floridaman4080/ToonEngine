# Changelog

All notable changes to this project are documented here.  
Format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/);
this project adheres to [Semantic Versioning](https://semver.org/).

---

## [0.1.0] - 2026-04-21

First public release. Covers the full integration surface for registering
`MSM_CelToon` as a first-class Shading Model in Unreal Engine 5.6 source.

### Added — Integration spec (`integration_notes.md`)

- **§1–§11 · Shading Model registration boilerplate** — `EMaterialShadingModel`
  enum entry, parameter-name mapping, subsurface / custom-data classification,
  shader bitfield, HLSL environment defines, GBuffer slot config, Material
  Expression dropdown entry, etc. (12 files, ~30 lines total touching engine
  glue code.)
- **§12 · Material attribute validity table** — activate SubsurfaceColor /
  CustomData0 / CustomData1 pins for CelToon in the Material editor.
- **§13 · BasePassCommon.ush** — enable CustomData write path and force GBuffer E
  write even without Lightmap baking (documented precondition: project does not
  use static lighting).
- **§14 · BasePass material-stage GBuffer packing** (snippet) — the full
  `#if MATERIAL_SHADINGMODEL_CELTOON / else if (...) { ... }` block that encodes
  the CelToon channel layout into GBuffer D + E.
- **§15 · GBuffer Visualizer HUD** — label and debug prints for CelToon.
- **§16 · Material pin localisation** — Highlight Intensity / Offset / Rim Width
  display names.
- **§17 · Sky lighting fixed-colour branch** (snippet) — non-Lumen path returns
  `BaseColor × SubColor × SkyLightColor × SKYLIGHT_SCALE` for CelToon pixels.
- **§18 · Reflection environment overrides** (snippet) — suppress SSR / Lumen
  reflections + override AO for CelToon.
- **§19 · GBuffer decode Metallic-reuse forks** (snippet) — three blocks that
  isolate CelToon from Metallic-dependent F0 / DiffuseColor derivation.
- **§20 · ToonBxDF core** (snippet) — the heart of the system. Three-stage
  smoothstep thresholding (diffuse / specular / rim), Blinn-style specular,
  Rim masking, ShadowOffset translation, HighlightIntensity & RimWidth
  read from GBuffer E.
- **§21 · Lumen dark-side lock** (snippet) — replaces `IndirectLighting.Diffuse`
  for CelToon with a fixed colour, bypassing Lumen GI / Occlusion.
- **§22–§24 · BasePassPixelShader extensions** — SubsurfaceData branch, F0 /
  DiffuseColor forks, translucency volume lighting inclusion.
- **§25 · Deferred static shadow guard** (snippet) — extends
  `GetShadowTermsBase` with a `ShadingModelID` default parameter; forces
  `UsesStaticShadowMap = 0` for CelToon so that the borrowed GBuffer E is
  never misinterpreted as a static-shadow channel.
- **§26 · Deferred Attenuation + self-shadow softening** (snippet) — CelToon
  materials bypass physical light attenuation and receive smoothstep-softened
  `SurfaceShadow` that stays in-phase with ToonBxDF's own stepping.
- **§27 · Deferred shading classification** — `IsSubsurfaceModel` and
  `HasCustomGBufferData` accept CelToon.
- **§28 · Deferred shading GBuffer decode forks** (snippet) — Mobile and
  Desktop decode paths both get Metallic-reuse forks; Desktop path additionally
  bypasses `SelectiveOutputMask` fallback for CelToon.

### Added — Original snippets (`snippets/shaders/`)

10 MIT-licensed shader snippet files, ~40 KB total, containing roughly **300
lines of original HLSL/ush code + ~150 lines of design commentary** (Chinese).

All snippets carry an explicit MIT license header and a "本文件全部由本仓库作者
原创" attestation.

### Notes

- This release intentionally does **not** publish patch files or diffs. The
  integration spec is phrased as prose + original snippet insertions so that
  it cannot be mechanically applied without a legally-obtained UE5.6 source
  tree.
- Target engine version: **Unreal Engine 5.6** (vanilla).

[0.1.0]: https://github.com/floridaman4080/ToonEngine/releases/tag/v0.1.0
