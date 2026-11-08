#!/usr/bin/env python3
"""TAPPaaS backlog view: ROADMAP.md + forge snapshot + local git + test ledger.

  backlog.py build [--repo ~/src/TAPPaaS] [--out backlog/out]
      Writes tasks.json, groups.json, decisions.json, meta.json for the
      dashboard. Reads only local files and git refs: no forge calls, no fetch.
      Refresh the snapshot first with forge-snapshot.py if it is old.

  backlog.py test <N> <T0..T4> <pass|fail> [--site hrossen] [--note TEXT]
      Records a test result for issue N in backlog/test-status.json.

  backlog.py show <N>
      Prints what the dashboard knows about issue N.

Sources, in order of trust: the test ledger (recorded results), ROADMAP.md
(rows, ticks, scores, notes), git (branches, worktrees, unpushed commits),
the snapshot (forge state, labels, assignees). Test levels found only in a
row's note are marked "inferred".
"""
import argparse, json, os, re, subprocess, sys
from datetime import datetime, timezone

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
LEDGER = os.path.join(ROOT, "backlog", "test-status.json")
SNAPSHOT = os.path.join(ROOT, "snapshots", "backlog.json")
LEVELS = ["T0", "T1", "T2", "T3", "T4"]
# Test effort needed based on Risk (ROADMAP.md): L = deep test on the test
# system, M/H = applied live there through a sweep.
REQUIRED = {"L": "T2", "M": "T3", "H": "T3"}


def now():
    return datetime.now(timezone.utc).isoformat(timespec="seconds")


def git(repo, *args):
    r = subprocess.run(["git", "-C", repo, *args], capture_output=True, text=True)
    return r.stdout if r.returncode == 0 else ""


# ---------- ROADMAP.md ----------

def cells(line):
    parts = re.split(r"(?<!\\)\|", line.strip())
    return [p.strip().replace("\\|", "|") for p in parts[1:-1]]


def plain(md, limit=None):
    s = re.sub(r"\[([^\]]+)\]\([^)]*\)", r"\1", md)
    s = s.replace("**", "").replace("`", "")
    s = re.sub(r"\s+", " ", s).strip()
    if limit and len(s) > limit:
        s = s[: limit - 1].rstrip() + "…"
    return s


HEAD = re.compile(r"^### (✅ )?(G\d+\.\d+) (.+?)(?: — (.*)| (· .*))?$")


def parse_roadmap(path):
    text = open(path).read().split("\n## Next release", 1)[0]
    groups, tasks, decisions = [], [], []
    wave = wave_name = None
    section = None
    group = None
    for line in text.splitlines():
        m = re.match(r"^## Wave (\d+) — (.+)$", line)
        if m:
            wave, wave_name, section, group = int(m[1]), m[2].strip(), "wave", None
            continue
        if line.startswith("## Future Work"):
            section, wave, wave_name = "future", None, "Future Work"
            group = {"group": "FW", "name": "Future Work — not yet in a wave", "wave": "FW",
                     "waveName": "Future Work", "ease": "–", "risk": "–", "released": 0,
                     "doneNext": 0, "open": 0, "purpose": "Known work that no wave holds yet.",
                     "complete": False}
            groups.append(group)
            continue
        if line.startswith("### Decisions"):
            section = "decisions"
            continue
        if line.startswith("## ") or (line.startswith("### ") and section == "decisions"):
            if section in ("decisions", "future"):
                section = None
            if not line.startswith("## Wave"):
                group = None if section != "wave" else group
            continue
        if section == "wave":
            m = HEAD.match(line)
            if m:
                tail = m[4] or m[5] or ""
                num = lambda k: int((re.search(k + r": (\d+)", tail) or [0, 0])[1])
                score = lambda k: (re.search(k + r" ([LMH–-])", tail) or [0, "–"])[1]
                group = {"group": m[2], "name": plain(m[3]), "wave": wave, "waveName": wave_name,
                         "ease": score("Ease"), "risk": score("Risk"), "released": num("released"),
                         "doneNext": num(r"done for [\d.]+"), "open": num("open"), "purpose": "",
                         "complete": bool(m[1])}
                groups.append(group)
                continue
            if group and not group["purpose"] and line.strip() and not line.startswith("|"):
                group["purpose"] = plain(line, 320)
                continue
        if not line.startswith("|") or re.match(r"^\|[\s:|-]+\|$", line.strip()):
            continue
        c = cells(line)
        if not c or c[0] in ("#", "ADR", "Wave · group"):
            continue
        if section == "decisions" and len(c) >= 3:
            decisions.append({"id": plain(c[0]), "question": plain(c[1], 260), "waitsOn": plain(c[2])})
        elif section in ("wave", "future") and group:
            idcell = c[0]
            done = idcell.startswith("✅")
            n = re.search(r"#(\d+)", idcell)
            if section == "wave" and len(c) >= 5:
                title, ease, risk, note = c[1], c[2], c[3], c[4]
            else:
                title, ease, risk, note = c[1], "–", "–", c[2] if len(c) > 2 else ""
            tasks.append({"id": plain(idcell.replace("✅", "")), "num": int(n[1]) if n else None,
                          "title": plain(title, 200), "group": group["group"],
                          "groupName": group["name"], "wave": group["wave"], "ease": ease or "–",
                          "risk": risk or "–", "done": done, "noteRaw": note,
                          "note": plain(note, 240)})
    return groups, tasks, decisions


# ---------- git ----------

ISSUE_REF = re.compile(r"#(\d{2,4})\b")
CLOSE_REF = re.compile(r"\b(?:close[sd]?|fix(?:e[sd])?|resolve[sd]?) #(\d{2,4})\b", re.I)
BRANCH_NUM = re.compile(r"(?:^|[/-])(\d{2,4})(?=[-/.]|$)")


def git_state(repo):
    main, upstream = "refs/heads/main", "refs/remotes/origin/main"
    st = {"unpushed": {}, "landed": {}, "closedBy": {}, "branches": {}, "worktrees": {}}
    for rec in git(repo, "log", f"{upstream}..{main}", "--format=%h%x1f%s%x1f%b%x1e").split("\x1e"):
        p = rec.strip().split("\x1f")
        if len(p) < 2:
            continue
        for n in set(ISSUE_REF.findall(p[1] + " " + (p[2] if len(p) > 2 else ""))):
            st["unpushed"].setdefault(int(n), []).append(p[0])
    for rec in git(repo, "log", main, "--since=120.days", "--format=%h%x1f%cs%x1f%s%x1f%b%x1e").split("\x1e"):
        p = rec.strip().split("\x1f")
        if len(p) < 3:
            continue
        msg = p[2] + " " + (p[3] if len(p) > 3 else "")
        for n in set(ISSUE_REF.findall(msg)):
            st["landed"].setdefault(int(n), {"commit": p[0], "date": p[1]})
        for n in set(CLOSE_REF.findall(msg)):
            st["closedBy"].setdefault(int(n), {"commit": p[0], "date": p[1]})
    dates = {}
    for line in git(repo, "for-each-ref", "refs/heads", "--format=%(refname:short)\t%(committerdate:short)").splitlines():
        b, d = line.split("\t")
        dates[b] = d
    wt_of = {}
    for blk in git(repo, "worktree", "list", "--porcelain").split("\n\n"):
        path = re.search(r"^worktree (.+)$", blk, re.M)
        br = re.search(r"^branch refs/heads/(.+)$", blk, re.M)
        if path and br:
            wt_of[br[1]] = path[1]
    unmerged = {}
    for rec in git(repo, "log", "--source", "--branches", "--not", main,
                   "--format=%S%x1f%s%x1f%b%x1e").split("\x1e"):
        p = rec.strip().split("\x1f")
        if len(p) < 2:
            continue
        b = p[0].removeprefix("refs/heads/")
        unmerged.setdefault(b, set()).update(int(n) for n in ISSUE_REF.findall(p[1] + " " + (p[2] if len(p) > 2 else "")))
    for b in unmerged:
        wt = os.path.basename(wt_of.get(b, ""))
        nums = unmerged[b] | {int(n) for n in BRANCH_NUM.findall(b) + BRANCH_NUM.findall(wt)}
        for n in nums:
            st["branches"].setdefault(n, []).append(
                {"branch": b, "date": dates.get(b, ""), "worktree": wt_of.get(b, "")})
    return st


# ---------- tests ----------

def load_ledger():
    return json.load(open(LEDGER)) if os.path.exists(LEDGER) else {}


LIVE = re.compile(r"(live[- ]tested|live on (?:hrossen|lab2)|drill on \w+ passed|proven on (?:hrossen|lab2)|"
                  r"passed on (?:hrossen|lab2)|on hrossen[^.]{0,40}passed)", re.I)


def inferred_test(note):
    m = LIVE.search(note)
    if not m:
        return None
    site = "lab2" if "lab2" in m[0].lower() else "hrossen"
    return {"level": "T3", "result": "pass", "site": site, "date": "", "source": "inferred"}


# ---------- derive ----------

def classify(t, forge, g):
    n, note = t["num"], t["note"]
    closed = forge.get("state") == "closed"
    pushed = n in g["landed"] and n not in g["unpushed"]
    if t["done"] or closed or (n in g["closedBy"]):
        if n in g["unpushed"]:
            return "Done", "on local main, not pushed"
        if closed or t["done"]:
            return "Done", "closed" if closed else "ticked in ROADMAP"
        return "Done", "closing commit on main"
    if n in g["unpushed"] or n in g["branches"] or re.search(r"\b(built|mostly built|in progress)\b", note, re.I):
        return "In progress", ""
    if re.search(r"\b(parked|deferred|rejected)\b", note, re.I):
        return "Parked", ""
    m = re.search(r"waiting (?:on|for) ([^.;]+)", note, re.I)
    if m:
        return "Waiting", plain(m[1], 60)
    m = re.search(r"\b(decide with #\d+|after #\d+|depends on [^.;]+|needs #\d+)", note, re.I)
    if m:
        return "Blocked", plain(m[1], 60)
    return "To do", ""


def build(a):
    repo = os.path.expanduser(a.repo)
    groups, tasks, decisions = parse_roadmap(os.path.join(repo, "ROADMAP.md"))
    snap = json.load(open(SNAPSHOT)) if os.path.exists(SNAPSHOT) else {"issues": {}}
    g = git_state(repo)
    ledger = load_ledger()
    for t in tasks:
        n = t["num"]
        forge = snap["issues"].get(str(n), {}) if n else {}
        t["stage"], t["stageNote"] = classify(t, forge, g)
        t["forgeState"] = forge.get("state", "")
        t["labels"] = ", ".join(forge.get("labels") or [])
        t["assignees"] = ", ".join(forge.get("assignees") or [])
        t["forgeUpdated"] = (forge.get("updated_at") or "")[:10]
        br = sorted(g["branches"].get(n, []), key=lambda b: b["date"], reverse=True)
        t["branch"] = br[0]["branch"] if br else ""
        t["branchDate"] = br[0]["date"] if br else ""
        t["worktree"] = os.path.basename(br[0]["worktree"]) if br and br[0]["worktree"] else ""
        t["branches"] = len(br)
        t["unpushed"] = len(g["unpushed"].get(n, []))
        landed = g["closedBy"].get(n) or g["landed"].get(n)
        t["lastCommit"] = landed["commit"] if landed else ""
        t["lastCommitDate"] = landed["date"] if landed else ""
        if t["stage"] == "Done":
            t["code"] = "local main" if t["unpushed"] else ("pushed" if landed else "–")
        else:
            t["code"] = "unpushed" if t["unpushed"] else ("branch" if br else "–")
        rec = (ledger.get(str(n)) or [])[-1:] if n else []
        test = dict(rec[0], source="recorded") if rec else inferred_test(t["noteRaw"])
        t["testLevel"] = test["level"] if test else ""
        t["testResult"] = test["result"] if test else ""
        t["testSite"] = test.get("site", "") if test else ""
        t["testDate"] = test.get("date", "") if test else ""
        t["testSource"] = test["source"] if test else ""
        req = REQUIRED.get(t["risk"], "")
        t["testRequired"] = req
        lvl = LEVELS.index(t["testLevel"]) if t["testLevel"] in LEVELS else -1
        need = LEVELS.index(req) if req else -1
        if t["testResult"] == "fail":
            t["testState"] = "failing"
        elif need < 0:
            t["testState"] = "passed" if lvl >= 0 else "n/a"
        elif lvl >= need:
            t["testState"] = "met"
        elif t["stage"] in ("Done", "In progress") and t["code"] != "–" or t["stage"] == "Done":
            t["testState"] = "below required" if lvl >= 0 else "no test record"
        else:
            t["testState"] = "not started"
        t["key"] = f'{t["group"]}:{t["id"]}'
        del t["noteRaw"]
    for gr in groups:
        mine = [t for t in tasks if t["group"] == gr["group"]]
        for s in ("To do", "In progress", "Waiting", "Blocked", "Parked", "Done"):
            gr["n_" + s.lower().replace(" ", "_")] = sum(t["stage"] == s for t in mine)
        gr["rows"] = len(mine)
        gr["testGaps"] = sum(t["testState"] in ("no test record", "below required", "failing") for t in mine)
        gr["onBranch"] = sum(1 for t in mine if t["branch"])
        gr["key"] = gr["group"]
    meta = [{"key": "now", "generated": now(), "snapshotAt": snap.get("fetched_at", ""),
             "main": git(repo, "rev-parse", "--short", "refs/heads/main").strip(),
             "originMain": git(repo, "rev-parse", "--short", "refs/remotes/origin/main").strip(),
             "unpushedCommits": len([l for l in git(repo, "log", "--oneline",
                                                    "refs/remotes/origin/main..refs/heads/main").splitlines() if l]),
             "roadmapCommit": git(repo, "log", "-1", "--format=%h %cs", "--", "ROADMAP.md").strip()}]
    os.makedirs(a.out, exist_ok=True)
    for name, rows in (("tasks", tasks), ("groups", groups), ("decisions", decisions), ("meta", meta)):
        json.dump(rows, open(os.path.join(a.out, name + ".json"), "w"), indent=1, ensure_ascii=False)
    by = {}
    for t in tasks:
        by[t["stage"]] = by.get(t["stage"], 0) + 1
    print(f"{len(groups)} groups, {len(tasks)} tasks {by}, {len(decisions)} decisions -> {a.out}")


def record(a):
    if a.level not in LEVELS:
        sys.exit(f"level must be one of {LEVELS}")
    led = load_ledger()
    led.setdefault(str(a.num), []).append({"level": a.level, "result": a.result, "site": a.site,
                                           "date": datetime.now().strftime("%Y-%m-%d"),
                                           "note": a.note or ""})
    os.makedirs(os.path.dirname(LEDGER), exist_ok=True)
    json.dump(led, open(LEDGER, "w"), indent=1, sort_keys=True)
    print(f"#{a.num}: {a.level} {a.result} on {a.site} recorded")


def show(a):
    tasks = json.load(open(os.path.join(a.out, "tasks.json")))
    for t in tasks:
        if t["num"] == a.num:
            print(json.dumps(t, indent=1, ensure_ascii=False))


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--out", default=os.path.join(ROOT, "backlog", "out"))
    sub = ap.add_subparsers(dest="cmd", required=True)
    b = sub.add_parser("build")
    b.add_argument("--repo", default="~/src/TAPPaaS")
    r = sub.add_parser("test")
    r.add_argument("num", type=int)
    r.add_argument("level")
    r.add_argument("result", choices=["pass", "fail"])
    r.add_argument("--site", default="hrossen")
    r.add_argument("--note")
    s = sub.add_parser("show")
    s.add_argument("num", type=int)
    a = ap.parse_args()
    {"build": build, "test": record, "show": show}[a.cmd](a)


if __name__ == "__main__":
    main()
