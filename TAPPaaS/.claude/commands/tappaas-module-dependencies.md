Regenerate `src/module-dependencies.md`, the module dependency model, from each module's `<module>.json` (`dependsOn`, `provides`).

## Steps

### 1. Generate

From the repository root:

```bash
src/generate-module-dependencies.sh            # writes src/module-dependencies.md
src/generate-module-dependencies.sh --check    # only says whether it is stale
```

It reads every module under `src/<stack>/` and `src/foundation/` (a directory holding `<dirname>.json`; `00-Template` skipped) and writes three views: the plumbing services most modules consume, a mermaid graph of the rest, and a per-module table. Do not hand-edit the output; change the script.

### 2. Check and commit

Read the diff (new modules, changed `dependsOn`), then on `main`, by pathspec:

```bash
git commit -m "docs(modules): regenerate the module dependency model" -- src/module-dependencies.md
```

### 3. Report

The module count and what changed.
