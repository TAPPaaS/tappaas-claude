Regenerate the foundation's program and dependency documentation: `src/foundation/PROGRAMS.csv`, `DEPENDENCIES.csv` and `DEPENDENCIES.md`.

## Steps

### 1. Generate

From the repository root:

```bash
python3 src/foundation/generate-dependencies.py          # writes the three files
python3 src/foundation/generate-dependencies.py --check  # only says whether they are stale
```

The script reads the code, never a site. Programs come from what the installers link into `~/bin` (`tappaas-cicd/install.sh`, `components.json`, each component's `install.sh`, `package.json` bins, `pyproject.toml` scripts); dependencies are the files sourced, the programs named in the code and the config files named. Its docstring has the exact rules. Do not hand-edit the output; change the script and run it again.

### 2. Check it

- `git diff --stat` on the three files: a new or vanished program has a reason (a component added, a verb retired).
- If a program a site has in `~/bin` is missing, an installer links it in a way the script does not know yet: add that pattern to `programs()` and rerun. A file placed by hand on one site (not in any installer) is not a program.
- A dependency that is only a word in a message (a false match) is fixed in the script's matching, not in the CSV.

### 3. Commit

On `main`, by pathspec:

```bash
git commit -m "docs(foundation): regenerate programs and dependencies" -- src/foundation/PROGRAMS.csv src/foundation/DEPENDENCIES.csv src/foundation/DEPENDENCIES.md
```

### 4. Report

The program count, the files read, and what changed since the last run.
