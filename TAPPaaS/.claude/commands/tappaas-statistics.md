Regenerate `src/STATISTICS.md`: the source statistics of the current revision against the last release, so the file shows the release delta.

Arguments (optional): `$ARGUMENTS` — the label of the current revision (the version the next boundary cuts, e.g. `2.5`). Default: ask what the next version is from `ROADMAP.md` ("done for X.Y").

## Steps

### 1. Pick the two sides

- **Last release:** the newest release tag, `git describe --tags --abbrev=0 --match 'v[0-9]*' origin/staging` (e.g. `v2.4`). Its label is the version without the `v`.
- **Current:** `origin/main` after `git fetch origin` — what the next boundary releases. Its label is the next version (the argument, or from `ROADMAP.md`).

When the user names other refs or labels, use those.

### 2. Generate

From the repository root:

```bash
python3 src/generate-statistics.py --last v2.4 --last-label 2.4 --current origin/main --current-label 2.5 > src/STATISTICS.md
```

The script counts both sides from git by the same rules (no checkout), so it is safe in a dirty tree; it never edits anything but its output. Read its docstring for what it counts and excludes. Do not hand-edit the result; change the script instead, so the next run says the same.

### 3. Check it

- The two totals are plausible (a release changes thousands of lines, not hundreds of thousands, unless something big landed or a generated file slipped in).
- A large jump in one row (the "Δ lines" column) has a reason: a new module, a new manager, the console. If it is generated output or a fixture that should not count, add it to `EXCLUDE` in the script, commit that, and regenerate.

### 4. Commit

On `main`, by pathspec (other sessions may have staged work):

```bash
git commit -m "docs(stats): source statistics, 2.5 against 2.4" -- src/STATISTICS.md
```

### 5. Report

Tell the user the path, the two totals, the delta, and the three rows that grew most.
