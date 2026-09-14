#!/usr/bin/env python3
"""Low-load snapshot of Codeberg issues + comments for offline analysis.

Uses repo-wide paginated endpoints (50 items/page, the Codeberg max) instead of
per-issue calls: ~3 pages of issues + ~15 pages of comments for the whole repo.
Re-running with an existing snapshot only fetches items updated since the last
run (`since=`), usually 1-2 requests. Unauthenticated (reads are public).
The raw API responses are saved next to OUT before processing.

  forge-snapshot.py OUT.json [--milestones 134471,134459,134453] [--state open]
  forge-snapshot.py OUT.json --milestones 134447 --add-milestone   # 1 request

Milestone ids: 2.0 Stacks 134471, 2.0 Docs 134459, 2.1 134453,
Future Work 134447, Parking lot 134456
(list: curl -s 'https://codeberg.org/api/v1/repos/TAPPaaS/TAPPaaS/milestones?state=all&limit=50').
Keep OUT under ../snapshots/ (gitignored).
"""
import argparse, json, os, sys, time, urllib.request, urllib.parse
from datetime import datetime, timezone

API = "https://codeberg.org/api/v1/repos/TAPPaaS/TAPPaaS"
PAUSE = 1.0  # seconds between requests: be polite to a volunteer forge
calls = 0


def get_all(path, params):
    global calls
    params = dict(params, limit=50)
    page, out = 1, []
    while True:
        params["page"] = page
        url = f"{API}/{path}?{urllib.parse.urlencode(params)}"
        req = urllib.request.Request(url, headers={"Accept": "application/json",
                                                   "User-Agent": "tappaas-backlog-snapshot"})
        with urllib.request.urlopen(req, timeout=60) as r:
            batch = json.load(r)
            total = int(r.headers.get("x-total-count", "0"))
        calls += 1
        out += batch
        print(f"  {path} page {page}: {len(batch)} (total {total})", file=sys.stderr)
        if len(batch) < 50 or len(out) >= total:
            return out
        page += 1
        time.sleep(PAUSE)


def slim_issue(i):
    return {k: i.get(k) for k in ("number", "title", "state", "body", "created_at",
                                  "updated_at", "closed_at", "comments")} | {
        "labels": [l["name"] for l in i.get("labels") or []],
        "milestone": (i.get("milestone") or {}).get("title"),
        "assignees": [a["login"] for a in i.get("assignees") or []],
        "author": i["user"]["login"],
    }


def slim_comment(c):
    url = c.get("issue_url") or c.get("pull_request_url") or ""
    num = url.rstrip("/").rsplit("/", 1)[-1]
    return {"id": c["id"], "issue": int(num) if num.isdigit() else None,
            "author": c["user"]["login"], "created_at": c["created_at"],
            "updated_at": c["updated_at"], "body": c["body"]}


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("out")
    ap.add_argument("--milestones", default="134471,134459,134453")
    ap.add_argument("--state", default="open")
    ap.add_argument("--add-milestone", action="store_true",
                    help="pull a new milestone's issues in full; skip comments (already repo-wide)")
    a = ap.parse_args()

    snap = {"issues": {}, "comments": {}, "fetched_at": None}
    if os.path.exists(a.out):
        snap = json.load(open(a.out))
    since = None if a.add_milestone else snap.get("fetched_at")
    now = datetime.now(timezone.utc).isoformat(timespec="seconds")
    extra = {"since": since} if since else {}

    print(f"issues (milestones {a.milestones}, state {a.state}, since {since})", file=sys.stderr)
    # incremental runs use state=all so issues closed since last run get updated
    raw = {}
    raw["issues"] = get_all("issues", {"state": "all" if since else a.state, "type": "issues",
                                "milestones": a.milestones, **extra})
    raw["comments"] = []
    if not a.add_milestone:
        time.sleep(PAUSE)
        print("comments (repo-wide)", file=sys.stderr)
        raw["comments"] = get_all("issues/comments", extra)
    # keep the raw response first, so a processing bug never costs a re-fetch
    json.dump(raw, open(a.out + f".raw-{now[:19].replace(':', '')}.json", "w"))
    for i in raw["issues"]:
        snap["issues"][str(i["number"])] = slim_issue(i)
    for c in raw["comments"]:
        snap["comments"][str(c["id"])] = slim_comment(c)

    if not a.add_milestone:  # keep the incremental cursor tied to the comment pull
        snap["fetched_at"] = now
    json.dump(snap, open(a.out, "w"), indent=1)
    print(f"done: {len(snap['issues'])} issues, {len(snap['comments'])} comments, "
          f"{calls} API calls -> {a.out}", file=sys.stderr)


if __name__ == "__main__":
    main()
