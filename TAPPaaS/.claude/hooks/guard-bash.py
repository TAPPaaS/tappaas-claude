#!/usr/bin/env python3
"""PreToolUse guard for the Bash tool in the TAPPaaS repos.

Enforces the git/forge rules of CLAUDE.md (see PROPOSAL-autonomy.md P1) so they
do not depend on the model remembering them:

  deny  git push (the operator pushes); --no-verify; gh except read-only use
        (GitHub is not the tracker); commits in a cicd's managed checkout
  ask   anything that changes `stable`; creating tags; rewriting commits that
        already exist on a remote; reset --hard / clean -f; tea writes
  —     everything else follows the normal permission rules

Reads the hook payload on stdin and prints a permission decision on stdout.
Python 3.9 compatible (macOS system python).
"""
import json
import os
import re
import shlex
import subprocess
import sys

MANAGED_CHECKOUT = os.environ.get("TAPPAAS_GUARD_MANAGED_CHECKOUT", "/home/tappaas/TAPPaaS")  # override: tests
SEPARATORS = {";", "&&", "||", "|", "&", "(", ")", "|&", ";;"}
PREFIX_WORDS = {"sudo", "command", "env", "nohup", "time", "exec", "builtin", "nice"}
COMMITTING = {"commit", "merge", "rebase", "cherry-pick", "revert", "am", "tag"}
CHANGES_CURRENT = {"commit", "merge", "rebase", "reset", "cherry-pick", "revert", "am", "pull"}
GH_READ_ONLY = {
    ("run", "list"), ("run", "view"), ("run", "watch"),
    ("release", "list"), ("release", "view"), ("release", "download"),
    ("repo", "view"), ("workflow", "list"), ("workflow", "view"), ("auth", "status"),
}
TEA_WRITE_VERBS = {
    "create", "c", "edit", "e", "close", "reopen", "open", "merge", "m", "approve",
    "reject", "review", "delete", "rm", "assign", "add", "set", "unset",
}
COMMIT_VALUE_OPTS = {"-m", "-F", "-C", "-c", "-t", "--author", "--date", "--fixup",
                     "--squash", "--cleanup", "--template", "--trailer"}


# --- helpers ---------------------------------------------------------------------

def git(cwd, *args):
    """Run a read-only git query; return stdout or '' on any failure."""
    try:
        out = subprocess.run(["git", "-C", cwd] + list(args), capture_output=True,
                             text=True, timeout=5)
        return out.stdout.strip() if out.returncode == 0 else ""
    except (OSError, subprocess.SubprocessError):
        return ""


def resolve(path, base):
    path = os.path.expanduser(path)
    return os.path.realpath(path if os.path.isabs(path) else os.path.join(base, path))


def segments(command):
    """Split a command line into simple-command token lists."""
    lex = shlex.shlex(command.replace("\n", " ; "), posix=True, punctuation_chars=True)
    lex.whitespace_split = True
    seg = []
    for tok in lex:
        if tok in SEPARATORS or tok == "$":
            if seg:
                yield seg
            seg = []
        else:
            seg.append(tok)
    if seg:
        yield seg


def strip_prefix(seg):
    """Drop env assignments and wrappers like sudo/env in front of the command."""
    i = 0
    while i < len(seg):
        tok = seg[i]
        if re.match(r"^[A-Za-z_][A-Za-z0-9_]*=", tok) or tok in PREFIX_WORDS:
            i += 1
            if tok == "sudo":
                while i < len(seg) and seg[i].startswith("-"):
                    i += 2 if seg[i] in ("-u", "-g", "-C") else 1
            continue
        break
    return seg[i:]


def base(word):
    return os.path.basename(word)


# --- rules -----------------------------------------------------------------------

def check_git(tokens, cwd):
    """Return (decision, reason) for one git invocation, or (None, None)."""
    i, where = 1, cwd
    while i < len(tokens) and tokens[i].startswith("-"):
        opt = tokens[i]
        if opt == "-C" and i + 1 < len(tokens):
            where = resolve(tokens[i + 1], where)
            i += 2
            continue
        if opt in ("-c", "--git-dir", "--work-tree", "--namespace") and i + 1 < len(tokens):
            i += 2
            continue
        i += 1
    if i >= len(tokens):
        return None, None
    sub, args = tokens[i], tokens[i + 1:]

    if sub == "push":
        return "deny", "git push is the operator's step. Commit locally and report what is ready to push."
    if "--no-verify" in args:
        return "deny", "--no-verify bypasses the repo's hooks; fix the cause instead."
    if sub == "commit" and short_flag_no_verify(args):
        return "deny", "git commit -n skips the hooks (--no-verify); fix the cause instead."

    top = git(where, "rev-parse", "--show-toplevel")
    if top and os.path.realpath(top) == os.path.realpath(MANAGED_CHECKOUT) and sub in COMMITTING:
        return "deny", ("No commits in the cicd's managed checkout (/home/tappaas/TAPPaaS): "
                        "a local commit blocks the site's scheduled pull. Work in ~/dev/TAPPaaS.")

    branch = git(where, "rev-parse", "--abbrev-ref", "HEAD")
    if branch == "stable" and sub in CHANGES_CURRENT:
        return "ask", "This changes the stable branch, which only moves through the release process."
    if touches_stable(sub, args):
        return "ask", "This moves or deletes the stable branch, which only moves through the release process."
    if sub == "tag" and args and not all(a in ("-l", "--list", "-n") or a.startswith("--sort")
                                         or a.startswith("--contains") for a in args):
        return "ask", "Creating or deleting a tag is part of the release process."
    if sub == "rebase" and not set(args) & {"--abort", "--continue", "--skip", "--quit", "--edit-todo"}:
        if branch and branch != "HEAD" and git(where, "branch", "-r", "--list", "*/" + branch):
            return "ask", "Rebasing '%s' rewrites commits that already exist on a remote." % branch
    if sub == "commit" and "--amend" in args and git(where, "branch", "-r", "--contains", "HEAD"):
        return "ask", "--amend rewrites a commit that already exists on a remote."
    if sub == "reset" and "--hard" in args:
        return "ask", "git reset --hard discards uncommitted work."
    if sub == "clean" and any(re.match(r"^-[a-zA-Z]*f", a) for a in args):
        return "ask", "git clean -f deletes untracked files."
    return None, None


def short_flag_no_verify(args):
    j = 0
    while j < len(args):
        a = args[j]
        if a in COMMIT_VALUE_OPTS:
            j += 2
            continue
        if re.fullmatch(r"-[a-zA-Z]+", a):
            if "n" in a[1:]:
                return True
            if a[-1] in "mFCct":
                j += 2
                continue
        j += 1
    return False


def touches_stable(sub, args):
    names = {"stable", "refs/heads/stable"}
    if not names & set(args):
        return False
    if sub == "update-ref":
        return True
    if sub == "branch":
        return bool(set(args) & {"-f", "--force", "-d", "-D", "--delete", "-m", "-M", "-c", "-C"})
    if sub in ("checkout", "switch"):
        return bool(set(args) & {"-B", "-C", "--force-create"})
    return False


def check_gh(tokens):
    words = [t for t in tokens[1:] if not t.startswith("-")]
    if not words or words[0] in ("version", "help") or "--version" in tokens or "--help" in tokens:
        return None, None
    if words[0] in ("issue", "pr"):
        return "deny", "GitHub is not the issue tracker (it is a push mirror). Use tea against Codeberg."
    if words[0] == "api":
        method = "GET"
        for k, t in enumerate(tokens):
            if t in ("-X", "--method") and k + 1 < len(tokens):
                method = tokens[k + 1].upper()
            elif t.startswith("--method="):
                method = t.split("=", 1)[1].upper()
        has_fields = any(t in ("-f", "-F", "--field", "--raw-field", "--input") or
                         t.startswith(("--field=", "--raw-field=", "--input=")) for t in tokens)
        if method == "GET" and not has_fields:
            return None, None
        return "deny", "Only read-only gh use is allowed (GitHub hosts pipelines and releases only)."
    if len(words) >= 2 and (words[0], words[1]) in GH_READ_ONLY:
        return None, None
    return "deny", "Only read-only gh use is allowed: gh run list|view|watch, gh release list|view|download, gh api GETs."


def check_tea(tokens):
    words = [t for t in tokens[1:] if not t.startswith("-")]
    if not words:
        return None, None
    if words[0] in ("comment", "c") or (len(words) > 1 and words[1] in TEA_WRITE_VERBS):
        return "ask", "This writes to Codeberg as the operator. Check the text before approving."
    return None, None


def decide(command, cwd):
    decisions = []
    for seg in segments(command):
        seg = strip_prefix(seg)
        if not seg:
            continue
        cmd = base(seg[0])
        if cmd in ("cd", "pushd"):
            cwd = resolve(seg[1], cwd) if len(seg) > 1 and seg[1] != "-" else os.path.expanduser("~")
        elif cmd == "git":
            decisions.append(check_git(seg, cwd))
        elif cmd == "gh":
            decisions.append(check_gh(seg))
        elif cmd == "tea":
            decisions.append(check_tea(seg))
    for level in ("deny", "ask"):
        for d, reason in decisions:
            if d == level:
                return d, reason
    return None, None


def fallback(command):
    """Used when the command cannot be tokenized (e.g. unbalanced quotes)."""
    if re.search(r"\bgit\b[^;&|]*\bpush\b", command) or "--no-verify" in command:
        return "deny", "git push / --no-verify are not allowed (command could not be parsed exactly)."
    if re.search(r"\bgh\s+(issue|pr)\b", command):
        return "deny", "GitHub is not the issue tracker. Use tea against Codeberg."
    return None, None


def main():
    try:
        payload = json.load(sys.stdin)
    except ValueError:
        return 0
    if payload.get("tool_name", "Bash") != "Bash":
        return 0
    command = (payload.get("tool_input") or {}).get("command", "")
    cwd = payload.get("cwd") or os.getcwd()
    try:
        decision, reason = decide(command, cwd)
    except ValueError:
        decision, reason = fallback(command)
    if decision:
        print(json.dumps({"hookSpecificOutput": {
            "hookEventName": "PreToolUse",
            "permissionDecision": decision,
            "permissionDecisionReason": "tappaas guard: " + reason,
        }}))
    return 0


if __name__ == "__main__":
    sys.exit(main())
