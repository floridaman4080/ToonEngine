# AI Merge Review Spec (ToonEngine)

> **用途**：把 `scripts/release-public.ps1` 产出的 staging 目录（`build/release-<version>/`）里的改动，**半自动**地 merge 进 `snippets/`、`integration_notes.md`、`CHANGELOG.md`。
>
> **执行者**：AI 助手。用户对 AI 说"审批 v0.2.0"这类指令后，AI 按本文档执行。
>
> **目的**：把"人读 10 个 new-lines-only.txt 粘到 10 个 snippet 对应 Block"这种重复劳动交给 AI，人只负责**最终结果 review** + commit。
>
> **这不是一个自动 commit 工具**。AI 只修改工作树，绝不 `git commit` / `git push`。
>
> 本规范跟着 ToonEngine 仓库版本管理。如需更新，改完 commit。AI 每次执行前**必须重新读这份文档**。

---

## 触发条件

AI 进入"合并审批模式"当且仅当满足以下任一：

1. 用户显式说"审批 v0.x.y"、"merge v0.x.y"、"合并 v0.x.y"
2. 用户指向一个 staging 目录，比如"帮我处理 `build/release-v0.2.0`"
3. 用户说"跑一遍 release-public.ps1 再帮我合"（= 连续执行 staging + merge）

AI **不得**在用户未触发时主动进入该模式。

---

## 前置检查（AI 必须先做）

在动任何文件前，AI 必须确认：

| # | 检查项 | 失败时的动作 |
|---|-------|------------|
| 1 | `build/release-<version>/` 存在且非空 | 报错：让用户先跑 `release-public.ps1` |
| 2 | `build/release-<version>/manual-action-required.txt` 存在 | 报错：staging dir 可能损坏 |
| 3 | ToonEngine 工作树**干净**（`git status --porcelain` 为空）| 报错：让用户先 stash/commit 未完成改动 |
| 4 | `scripts/target-files.json` 里 22 个文件都解析通过 | 报错：让用户修 JSON |
| 5 | 本规范文档（`docs/AI_MERGE_REVIEW_SPEC.md`）未被更新到未识别的版本 | 警告：可能需要人介入 |

---

## 输入（AI 可以读）

| 文件 | 用途 | 注意 |
|------|------|------|
| `build/release-<version>/per-file/*.new-lines-only.txt` | **唯一的 merge 源** | 只含 `+` 行，无 Epic 代码 |
| `build/release-<version>/CHANGELOG-proposed.md` | CHANGELOG 骨架 | AI 可以润色后用 |
| `build/release-<version>/manual-action-required.txt` | 分类清单 | 指引 AI 哪些是 additive 哪些是 refactor |
| `scripts/target-files.json` | snippet 映射表 | 决定每个文件改到哪个 snippet |
| `snippets/shaders/*` | 待 merge 的目标 | AI 要改这些 |
| `integration_notes.md` | 散文描述 | AI 可能要改 |
| `CHANGELOG.md` | 版本历史 | AI 要追加新版本段落 |

## 输入（AI **禁止**读并复制到任何输出文件）

| 文件 | 原因 |
|------|------|
| `build/release-<version>/per-file/*.diff.txt` | **包含 Epic 上下文代码**。AI 只能用它**判断有哪些 `-` 行**（看行号、看删除了什么语义），**绝不允许把 `diff.txt` 里的任何行**（无论 `+`/`-`/空格前缀）**直接或间接粘贴到 snippet / integration_notes / CHANGELOG**。 |
| `E:\UECode\UnrealEngine-5.6\` 下的任何引擎源码 | 直接读 Epic 源码同样是污染风险。AI 的全部信息来自 staging 目录。 |

**违反此红线 = 立即终止任务 + 报错给用户 + 建议 `git checkout -- .` 回滚**。

---

## 处理规则：按文件分四类

从 `manual-action-required.txt` 里读分类，对每个文件执行对应规则。

### 类别 A — Pure Additive + 映射到现有 snippet

**特征**：`[additive]` 标签；`target-files.json` 里 `maps_to_snippet` 非空。

**示例**：`ShadingModels.ush (+8)` → `snippets/shaders/ShadingModels__ToonBxDF.ush`

**步骤**：

1. 读 `new-lines-only.txt`（跳过 header 部分，只看代码行）
2. 读 `snippets/shaders/<mapped-snippet>`
3. 识别新增代码所属的 Block：
   - 看代码开头的注释（如 `// CelToon BxDF ...`）是否出现在某个 Block header 里 → 归属该 Block
   - 看代码结构（如 `FDirectLighting ToonBxDF(...)` 函数体）是否与某个 Block 对应 → 归属该 Block
   - 看 `manual-action-required.txt` 里是否显式标注了 Block（如 "Block A"）
4. 把新增代码 merge 进 Block：
   - **全量替换**型 Block（如 `ShadingModels__ToonBxDF.ush` 里 `ToonBxDF` 函数）→ 用新代码替换整个函数体
   - **追加**型 Block（如 `IntegrateBxDF` switch case 追加一个 case）→ 在 Block 末尾追加
5. **保留 snippet 原有的 header 注释**（MIT license + 集成说明）——**绝不删除**
6. 记 merge-report：`Merged N lines into Block X of <snippet>`

**不确定 Block 归属时**：标记为 "SKIPPED - ambiguous block"，交给人工。

### 类别 B — Refactor（有 +/- 混合）+ 映射到现有 snippet

**特征**：`[refactor]` 标签；`maps_to_snippet` 非空。

**步骤**：

1. 读 `new-lines-only.txt` 得到所有 `+` 行
2. 读 `diff.txt` **只为了提取 `-` 行**（以单个 `-` 开头且不以 `---` 开头的行）：
   - AI 可以把 `-` 行的**内容**记在内存里，用于 3、4 步的定位
   - AI **禁止**把 `-` 行的内容、或其周围的上下文行（空格前缀）写入任何输出文件
3. 在 snippet 里定位 `-` 行内容对应的位置：
   - 字符串匹配：如果 snippet 里存在完全相同的行 → 标记为"删除候选"
   - 语义匹配：如果 snippet 里有相似但不完全一致的行（比如变量名变了）→ 标记为"修改候选"
4. 决策：
   - **≥90% `-` 行在 snippet 里能精确定位** → 执行删除/修改
   - **50% ≤ 定位率 < 90%** → 执行能确定的部分，剩下的在 merge-report 里列出 "需人工 review"
   - **定位率 < 50%** → STOP 整个文件，标记 "SKIPPED - refactor too ambiguous"
5. 再按类别 A 的规则 merge `+` 行
6. 记 merge-report：`Refactored <snippet>: removed M lines from Block X, added N lines to Block X. Locate rate: P%. [Human review recommended]`

### 类别 C — List-extension only（无 mapped snippet）

**特征**：`maps_to_snippet` 为空；`integration_section` 非空。

**示例**：`EngineTypes.h (+1)` 或 `ShaderGenerationUtil.cpp (+1)` —— 通常是加一个枚举项或 switch case。

**步骤**：

1. 读 `new-lines-only.txt` 得到新增代码
2. 读 `integration_notes.md` 对应 section
3. 判断是否需要改 integration_notes：
   - 如果 section 描述仍然正确（比如 "在 enum 末尾加 `MSM_CelToon`" —— 新的改动还是这种形态）→ **无需修改**
   - 如果 section 描述过时了（比如新增行不再是简单 append，而是加了个完全不同的位置）→ 更新 section 的描述
4. **绝不**为 list-extension 新增 snippet 文件
5. 记 merge-report：`Integration §N: no change required` 或 `Integration §N: description updated`

### 类别 D — 找不到映射 / 新文件

**特征**：文件不在 `target-files.json` 里，或者 `target-files.json` 里的 `integration_section` 也为空。

**这种情况不该出现**，因为 `release-public.ps1` 只遍历 `target-files.json`。如果真出现了：

- 如果是 bug：停止，报告给用户
- 如果是用户加了新文件但没更新 JSON：停止，让用户先补 `target-files.json`

AI **绝不**自动创建新 snippet、新 section、或修改 `target-files.json`。

---

## CHANGELOG 处理

最后一步，在所有 snippet / integration_notes 改完后：

1. 读 `build/release-<version>/CHANGELOG-proposed.md`（骨架）
2. 基于 merge-report 的内容，把骨架 bullets 改写成**人性化**的 release notes：
   - 不要只列 "+12 / -3 lines"
   - 要讲 "Improved xxx feature by yyy"
   - 分组：Added / Changed / Fixed / Removed（Keep a Changelog 格式）
3. 写入 `CHANGELOG.md` 的 `## [0.1.0]` 条目**之前**
4. 更新文件末尾的 compare URL：追加新版本的 URL
5. 保留原有所有历史版本条目**不变**

---

## 输出

AI 完成后工作树应该是：

```
Modified:
  snippets/shaders/<若干>        ← 类别 A / B 的改动
  integration_notes.md           ← 类别 C 的描述更新（如果有）
  CHANGELOG.md                   ← 追加新版本段落

Untracked (在 build/ 下，gitignored):
  build/release-<version>/merge-report.md    ← AI 本次执行的详细报告
```

### `merge-report.md` 格式

```markdown
# AI Merge Report — v0.2.0

Generated: 2026-xx-xx xx:xx:xx
Staging dir: build/release-v0.2.0
Target files audited: N

## ✅ Merged successfully

- `<file1>` → `<snippet1>` Block X: +12 / -0 lines
- `<file2>` → `<snippet2>` Block Y: +8 / -5 lines (refactor, locate rate 100%)

## ⚠ Needs human review

- `<file3>` → `<snippet3>` Block Z: refactor locate rate 70%. Removed 5 of 7 `-` lines.
  The following `-` lines were not auto-matched:
    - (describe what was NOT found in snippet — do NOT quote Epic code content, only location hints)

## ⛔ Skipped

- `<file4>`: ambiguous block mapping (new code does not match any existing Block header).
  Action required: human to decide whether to add to existing Block Y or create new Block D.

## integration_notes.md changes

- §13: no change (description still accurate).
- §20: description updated — mentioned new ShadowRange parameter.

## CHANGELOG.md

- New [0.2.0] entry added at top.
- Compare URL appended.

## Safety self-check

- [x] No content from diff.txt was written to any file
- [x] No git commit / push performed
- [x] Snippet header/license blocks preserved
- [x] No new snippet files created
- [x] No new integration_notes sections created
- [x] target-files.json unchanged
```

---

## AI 执行完后给用户的回复模板

```
# Merge 完成 — v0.2.0

## ✅ 成功 merge
<N> 个文件，覆盖 <M> 个 snippet Block

## ⚠ 需要你 review
<K> 个文件或位置，详见 build/release-v0.2.0/merge-report.md

## 下一步
1. review 工作树：
     git status
     git diff snippets/ integration_notes.md CHANGELOG.md
2. 满意后：
     git add snippets/ integration_notes.md CHANGELOG.md
     git commit -m "Release v0.2.0"
     git tag -a v0.2.0 -m "v0.2.0 release"
     git push origin main
     git push origin v0.2.0
3. 给 UE5 fork 打 baseline tag：
     git -C E:\UECode\UnrealEngine-5.6 tag -a celtoon-v0.2.0 -m "..."
     git -C E:\UECode\UnrealEngine-5.6 push origin celtoon-v0.2.0
4. 清理：
     Remove-Item -Recurse -Force build
```

---

## 失败处理

如果 AI 在 merge 过程中遇到以下情况：

| 情况 | 动作 |
|------|------|
| 前置检查失败 | 立即报错，不改任何文件 |
| 读到 diff.txt 里的 Epic 代码想拷贝 | **终止**，工作树可能已有部分改动 → 建议用户 `git checkout -- .` 回滚 |
| Snippet 文件 parse 失败 | STOP 该文件，继续下一个；merge-report 里记 SKIPPED |
| 拿不准哪个 Block | 选 SKIP 而不是猜；记 "ambiguous" |
| 中途被用户取消 | 停下即可，不清理中间态；工作树会有部分改动，用户决定是 commit 还是 `git checkout -- .` |

---

## 红线汇总（AI 死也不能越过）

1. ❌ 把 `diff.txt` 的任何行（包括 `+` 行）直接读入并写到 snippet —— **必须走 `new-lines-only.txt`**
2. ❌ 把 snippet 的 header 注释 / MIT license 块删掉或重写
3. ❌ 创建新的 snippet 文件（哪怕你觉得需要）
4. ❌ 在 integration_notes.md 里新加 section
5. ❌ 改 `scripts/target-files.json`
6. ❌ 运行任何改变 git 状态的命令（`add`/`commit`/`push`/`tag`/`reset`/`rebase`/`checkout`）
7. ❌ 访问 `E:\UECode\UnrealEngine-5.6\` 下的引擎源码
8. ❌ 跳过 merge-report —— 即使一切顺利，也必须生成

---

## 规范版本

- **当前版本**：1.0（2026-04-21）
- **修改方式**：直接改本文档 + commit。AI 每次执行前重新读此文档。
- **不兼容变更**：rename 本文档时必须同步更新 Windsurf memory 里的路径引用。
