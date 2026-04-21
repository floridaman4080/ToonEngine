# ToonEngine release tooling

This directory contains the automation glue for publishing new versions of
`ToonEngine` based on ongoing work in the **private** UE5.6 fork.

## Files

| File | Purpose |
|------|---------|
| `target-files.json` | The 22 UE5.6 source files that may contain CelToon changes, plus hints about which ToonEngine snippet each file maps to |
| `release-public.ps1` | Extracts, filters, and stages the diff for human review. Never modifies the repo or commits anything. |
| `README.md` (this file) | Usage |

## Prerequisites

1. **Two repos on disk**:
   - `E:\UECode\UnrealEngine-5.6` — private UE5.6 fork (git repo). Contains Epic code.
   - `E:\UECode\UE56_CelShading_Public` — this repo, a.k.a. ToonEngine. Public. No Epic code.

2. **Baseline tag in the UE5.6 fork**: `celtoon-v0.1.0` (already created). This represents the state of UE5.6 source that corresponds to ToonEngine `v0.1.0-initial`.

3. **PowerShell 5.1+** (Windows default) and `git` on PATH.

## Typical workflow — publishing v0.2.0

### Step 1. Make changes in the UE5.6 fork

Edit CelToon-related code in `E:\UECode\UnrealEngine-5.6\Engine\...`, compile, test,
and commit in the UE5.6 fork as normal:

```powershell
cd E:\UECode\UnrealEngine-5.6
# ... edit files ...
git add .
git commit -m "feat: <what you changed>"
# optional: push to the private fork immediately
git push origin master
```

Repeat as many times as you want. You may accumulate dozens of commits between
public releases.

### Step 2. Stage the diff into ToonEngine

When you are ready to publish a new public version, from the ToonEngine repo root:

```powershell
cd E:\UECode\UE56_CelShading_Public
.\scripts\release-public.ps1 -NewVersion v0.2.0
```

The script:

1. Reads `target-files.json` for the 22 target files.
2. For each, runs `git diff celtoon-v0.1.0..HEAD -- <file>` in the UE5.6 fork.
3. Writes two files per changed file to `build/release-v0.2.0/per-file/`:
   - `<file>.diff.txt` — raw diff (**contains Epic context — never commit this**).
   - `<file>.new-lines-only.txt` — **only** the `+` lines you added, Epic context stripped. Safe to copy into snippets.
4. Writes `build/release-v0.2.0/CHANGELOG-proposed.md` — skeleton for the new version's CHANGELOG entry.
5. Writes `build/release-v0.2.0/manual-action-required.txt` — checklist of what you must decide.

Parameters:

| Parameter | Default | Description |
|-----------|---------|-------------|
| `-NewVersion` *(required)* | — | Version label, e.g. `v0.2.0`. Must match `v<major>.<minor>.<patch>`. |
| `-Baseline` | `celtoon-v0.1.0` (from JSON) | Tag in UE5.6 fork representing the last release point. |
| `-UE5Path` | `E:\UECode\UnrealEngine-5.6` (from JSON) | Path to the private UE5.6 fork. |
| `-ToonEnginePath` | parent of `scripts/` | Path to the ToonEngine repo. |
| `-ConfigPath` | `scripts/target-files.json` | Override config file. |

### Step 3. Manual review & integration

Open `build/release-v0.2.0/manual-action-required.txt` — it lists every changed file with a `[refactor]` or `[additive]` tag and tells you which snippet/section each maps to.

For each `*.new-lines-only.txt`:

- **Pure additive (no `-` lines)** — usually a straight append/replace into the mapped snippet Block. Copy the new lines in, check the Block header comment still applies, save.
- **Refactor (has `-` lines)** — open `*.diff.txt` side-by-side, decide whether the snippet needs OLD content removed in addition to new content added. Do not just blindly append.
- **No mapped snippet** — the change is in a list-extension-only file (enum, switch, OR-chain). Update the matching `integration_notes.md` section to mention the change if it affects the description; otherwise you may not need to change ToonEngine at all.

### Step 4. Finalise CHANGELOG

```powershell
# Open build/release-v0.2.0/CHANGELOG-proposed.md, review, then
# merge its contents into CHANGELOG.md above the [0.1.0] entry.
```

Edit / rewrite the bullets to be human-readable release notes, not just file-line stats. The skeleton is only there so you don't forget anything.

### Step 5. Commit & tag ToonEngine, tag UE5 fork

```powershell
# ToonEngine
cd E:\UECode\UE56_CelShading_Public
git add snippets/ integration_notes.md CHANGELOG.md
git commit -m "Release v0.2.0"
git tag -a v0.2.0 -m "v0.2.0 release"
git push origin main
git push origin v0.2.0

# UE5.6 fork — mark the new baseline for the NEXT release
git -C E:\UECode\UnrealEngine-5.6 tag -a celtoon-v0.2.0 -m "UE5.6 state for ToonEngine v0.2.0"
git -C E:\UECode\UnrealEngine-5.6 push origin celtoon-v0.2.0
```

> **Why tag the UE5 fork?** Because next time you run `release-public.ps1 -NewVersion v0.3.0 -Baseline celtoon-v0.2.0`, the script will only surface changes made AFTER v0.2.0. Without the tag, you'd keep seeing the whole history since v0.1.0.

### Step 6. Clean up staging

```powershell
Remove-Item -Recurse -Force build/release-v0.2.0
```

(`build/` is in `.gitignore`, so it was never tracked anyway; this just keeps your disk tidy.)

## Safety guarantees of the script

The script **never**:

- Modifies any file under `snippets/` or `integration_notes.md` or `CHANGELOG.md`.
- Runs `git add`, `git commit`, `git push` on the ToonEngine repo.
- Runs anything other than `git diff` / `git tag --list` on the UE5.6 fork.
- Writes outside of `build/release-<version>/`.
- Produces any output file containing Epic source code.

Every Epic-code-containing file it writes (`*.diff.txt`) is clearly marked and stays inside `build/` which is gitignored.

## Troubleshooting

**"Baseline tag 'celtoon-v0.1.0' not found"**
You never pushed the tag, or it was pushed to a different remote. Check:
```powershell
git -C E:\UECode\UnrealEngine-5.6 tag --list
```

**"No changes in any of the 22 target files"**
Either you made changes in files we don't track, or you ran the script from the wrong `-Baseline`. Double-check with:
```powershell
git -C E:\UECode\UnrealEngine-5.6 log celtoon-v0.1.0..HEAD --oneline --stat
```

**Chinese characters garbled in output files**
On Windows PowerShell 5.1, `Out-File -Encoding UTF8` writes a BOM. Most viewers handle it fine; if yours doesn't, open with VS Code or Notepad++.

## Extending the target file list

If a future CelToon change touches a file that isn't in `target-files.json`, add a new entry there:

```jsonc
{
    "path": "Engine/Shaders/Private/SomeNewFile.ush",
    "maps_to_snippet": "",              // or "MyNewSnippet.ush"
    "integration_section": "29",        // new section number in integration_notes.md
    "note": "Short description of what CelToon changes in this file"
}
```

Then run the release script as usual — it will pick up the new file automatically.
