#!/usr/bin/env python3
"""Scan every installed skill for instruction classes superseded by Anthropic's
current model guidance. Plugin-agnostic by design: it matches on what an
instruction DOES, never on which plugin ships it.

Output is a review list, not a verdict. Regexes over prose over-match; a hit
means "read this line and decide", and the ledger records the decision.

Usage:  python3 scan-superseded.py [--all] [--json]
        --all   include skills with no hits
        --json  machine-readable
Exit code is always 0.
"""
import argparse, json, os, pathlib, re, sys

try:  # Windows consoles default to cp1252 and die on any arrow or dash
    sys.stdout.reconfigure(encoding="utf-8", errors="replace")
except Exception:
    pass

def roots_for(home):
    home = pathlib.Path(home)
    return [
        ("plugin", home / ".claude" / "plugins" / "cache"),
        ("local",  home / ".claude" / "skills"),
    ]

# Each class traces to a specific line of guidance, or is marked LOCAL where it
# is our own extension rather than something Anthropic states.
CLASSES = [
    {
        "id": "A", "source": "Anthropic: 'remove verification instructions; they cause over-verification'",
        "name": "Mandated verification before completion claims",
        "patterns": [
            r"no completion claims", r"verification (step|command|evidence)",
            r"before (any )?(completion|claiming|success)", r"evidence before (claims|assertions)",
            r"(must|always) run .{0,40}before (claiming|declaring)",
        ],
    },
    {
        "id": "B", "source": "Anthropic: 'do not use subagents to verify or double-check your own work'",
        "name": "Subagent verification or standing review gate",
        "patterns": [
            r"subagent to (verify|double-check|review)", r"proactively after (any|every|each)",
            r"after (any|every|each) substantive", r"(request|dispatch).{0,30}code review.{0,40}(complet|merg)",
            r"before merging to verify",
        ],
    },
    {
        "id": "C", "source": "Anthropic: 'delegate only for large, genuinely independent tracks; keep spawn counts low'",
        "name": "Delegate-by-default",
        "patterns": [
            r"delegat\w+ (by default|whenever|always)", r"2\+ independent tasks",
            r"push\w* .{0,25}down to", r"always (use|spawn) (a )?subagent",
            r"parallel agents", r"no spawn-count cap",
        ],
    },
    {
        "id": "D", "source": "Anthropic: 'avoid instructing re-checks it already performs'",
        "name": "Re-check / double-check instructions",
        "patterns": [r"double-check", r"re-verify", r"verify (again|twice)", r"check your (answer|work) again"],
    },
    {
        "id": "E", "source": "LOCAL extension - Anthropic states no rule on invocation thresholds",
        "name": "Mandatory-invocation threshold / ceremony",
        "patterns": [
            r"1% chance", r"before ANY response", r"you MUST use this before",
            r"ABSOLUTELY MUST", r"you do not have a choice",
        ],
    },
    {
        "id": "F", "source": "Anthropic: 'match length to what the task needs; do not pad'",
        "name": "Fixed-template padding in deliverables",
        "patterns": [
            r"(must|always) include (a|an|the) (summary|recap|conclusion|bottom line)",
            r"^#+ *(bottom line|key principles|real-world impact)",
        ],
    },
]

for c in CLASSES:
    c["rx"] = [re.compile(p, re.I | re.M) for p in c["patterns"]]


def skill_files(kind, root):
    if not root.exists():
        return
    for p in root.rglob("SKILL.md"):
        parts = p.parts
        plugin = version = None
        if kind == "plugin":
            try:
                i = parts.index("cache")
                plugin = parts[i + 2] if len(parts) > i + 2 else "?"
                version = parts[i + 3] if len(parts) > i + 3 else "?"
            except ValueError:
                plugin, version = "?", "?"
        yield {
            "kind": kind, "plugin": plugin, "version": version,
            "skill": p.parent.name, "path": str(p),
        }


def latest_only(recs):
    """A plugin cache keeps old versions. Only the newest of each plugin is live."""
    def key(v):
        try:
            return tuple(int(x) for x in re.findall(r"\d+", v or "")[:3])
        except ValueError:
            return (0,)
    newest = {}
    for r in recs:
        if r["kind"] != "plugin":
            continue
        p = r["plugin"]
        if p not in newest or key(r["version"]) > key(newest[p]):
            newest[p] = r["version"]
    return [r for r in recs if r["kind"] != "plugin" or r["version"] == newest.get(r["plugin"])]


def scan(home):
    out = []
    for kind, root in roots_for(home):
        for rec in skill_files(kind, root):
            try:
                text = pathlib.Path(rec["path"]).read_text(encoding="utf-8", errors="replace")
            except OSError:
                continue
            lines = text.splitlines()
            hits, seen = [], set()
            for c in CLASSES:
                for rx in c["rx"]:
                    m = rx.search(text)
                    if not m:
                        continue
                    line_no = text.count("\n", 0, m.start()) + 1
                    if (c["id"], line_no) in seen:
                        continue
                    seen.add((c["id"], line_no))
                    hits.append({"class": c["id"], "name": c["name"], "line": line_no,
                                 "text": lines[line_no - 1].strip()[:150]})
            rec["hits"] = hits
            out.append(rec)
    return latest_only(out)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--all", action="store_true")
    ap.add_argument("--json", action="store_true")
    ap.add_argument("--root", default=str(pathlib.Path.home()),
                    help="Home directory to scan (default: yours). Used by the tests.")
    a = ap.parse_args()

    recs = scan(a.root)
    flagged = [r for r in recs if r["hits"]]

    if a.json:
        print(json.dumps(recs if a.all else flagged, indent=1))
        return

    print("Superseded-instruction scan")
    print("%d skills scanned, %d carrying flagged instruction classes\n" % (len(recs), len(flagged)))

    by_class = {}
    for r in flagged:
        for h in r["hits"]:
            by_class.setdefault(h["class"], []).append((r, h))

    for c in CLASSES:
        rows = by_class.get(c["id"], [])
        if not rows and not a.all:
            continue
        print("[%s] %s" % (c["id"], c["name"]))
        print("     %s" % c["source"])
        if not rows:
            print("     no hits\n")
            continue
        for r, h in rows:
            who = "%s %s" % (r["plugin"], r["version"]) if r["kind"] == "plugin" else "local"
            print("     %-26s %-32s :%-4s %s" % (who, r["skill"], h["line"], h["text"]))
        print()

    print("Regexes over-match. A hit is a line to read and rule on, not a defect.")


if __name__ == "__main__":
    main()
    sys.exit(0)
