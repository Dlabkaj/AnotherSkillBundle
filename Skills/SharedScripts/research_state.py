#!/usr/bin/env python3
"""
autoresearch_state.py - deterministic state machine helper for AutoresearchSkill WORKER

Commands:
  status <task_dir>                      JSON snapshot: phase, status, next candidate, stop check
  mark <task_dir> <url_substr> <status> [raw_path]  Update candidate status in candidates.md
  update <task_dir> KEY=VAL ...          Update progress.md fields; KEY+=N appends to a list
  check-stop <task_dir>                  Evaluate stop conditions, print JSON {stop, reason}

Exit codes: 0=ok, 1=error
"""
import sys, json, re, os
from pathlib import Path

DIMINISHING = {
    "LOW":    {"min_ingested": 5,  "last_n": 3, "threshold": 200},
    "MEDIUM": {"min_ingested": 12, "last_n": 3, "threshold": 100},
    "HIGH":   {"min_ingested": 20, "last_n": 5, "threshold": 100},
}

PROGRESS_KEYS = [
    "STATUS", "PHASE", "ITER", "SOURCES_FETCHED", "SOURCES_INGESTED",
    "SOURCES_SKIPPED", "RECENT_EDIT_CHARS", "LAST_EDIT", "WIKI_PAGES_TOUCHED", "LAST_VERIFY",
]
INT_KEYS = {"ITER", "SOURCES_FETCHED", "SOURCES_INGESTED", "SOURCES_SKIPPED"}
LIST_KEYS = {"RECENT_EDIT_CHARS", "WIKI_PAGES_TOUCHED"}


# --- progress.md read/write ---

def read_progress(task_dir):
    text = (Path(task_dir) / "progress.md").read_text(encoding="utf-8-sig")
    data = {}
    for line in text.splitlines():
        if ": " in line:
            k, v = line.split(": ", 1)
            k, v = k.strip(), v.strip()
            if k in INT_KEYS:
                try:
                    data[k] = int(v)
                except ValueError:
                    data[k] = 0
            elif k in LIST_KEYS:
                try:
                    data[k] = json.loads(v)
                except Exception:
                    data[k] = []
            else:
                data[k] = v
    for k in INT_KEYS:
        data.setdefault(k, 0)
    for k in LIST_KEYS:
        data.setdefault(k, [])
    return data


def write_progress(task_dir, data):
    lines = []
    seen = set()
    for key in PROGRESS_KEYS:
        val = data.get(key, "")
        if isinstance(val, list):
            val = json.dumps(val)
        lines.append(f"{key}: {val}")
        seen.add(key)
    # preserve any extra keys (e.g. NOTES)
    for k, v in data.items():
        if k not in seen:
            if isinstance(v, list):
                v = json.dumps(v)
            lines.append(f"{k}: {v}")
    (Path(task_dir) / "progress.md").write_text("\n".join(lines) + "\n", encoding="utf-8")


# --- task.md read ---

def read_task(task_dir):
    text = (Path(task_dir) / "task.md").read_text(encoding="utf-8-sig")
    data = {}
    for line in text.splitlines():
        if ": " in line:
            k, v = line.split(": ", 1)
            data[k.strip()] = v.strip()
    return data


# --- candidates.md: pick next (lightweight, no full parse) ---

def pick_next_candidate(task_dir, want_status):
    """Return dict with url, title, type, raw (if present) for the first candidate with want_status."""
    lines = (Path(task_dir) / "candidates.md").read_text(encoding="utf-8-sig").splitlines()
    # separator is em-dash or double-hyphen
    entry_re = re.compile(r"^- \[(\w+)\] (.+?)(?:\s+(?:--|—)\s+)(.+)$")
    i = 0
    while i < len(lines):
        line = lines[i]
        m = entry_re.match(line)
        if m:
            ctype, title, url = m.group(1), m.group(2).strip(), m.group(3).strip()
            candidate = {"type": ctype, "title": title, "url": url}
            j = i + 1
            while j < len(lines) and lines[j].startswith("  "):
                kv = lines[j].strip()
                if kv.startswith("status: "):
                    candidate["status"] = kv[8:]
                elif kv.startswith("raw: "):
                    candidate["raw"] = kv[5:]
                elif kv.startswith("snippet: "):
                    candidate["snippet"] = kv[9:]
                elif kv.startswith("note: "):
                    candidate["note"] = kv[6:]
                j += 1
            candidate.setdefault("status", "pending")
            if candidate["status"] == want_status:
                return candidate
        i += 1
    return None


def count_statuses(task_dir):
    lines = (Path(task_dir) / "candidates.md").read_text(encoding="utf-8-sig").splitlines()
    counts = {}
    i = 0
    while i < len(lines):
        line = lines[i]
        if line.startswith("- "):
            status = "pending"
            j = i + 1
            while j < len(lines) and lines[j].startswith("  "):
                kv = lines[j].strip()
                if kv.startswith("status: "):
                    status = kv[8:]
                j += 1
            counts[status] = counts.get(status, 0) + 1
        i += 1
    return counts


# --- stop conditions ---

def check_stop(task_dir, progress, task, counts):
    status = progress.get("STATUS", "")
    if status.startswith("STOP_") or status in ("COMPLETE", "DONE", "DONE_INGEST"):
        return {"stop": True, "reason": f"status={status}"}

    if (Path(task_dir) / "STOP.md").exists():
        return {"stop": True, "reason": "STOP.md present"}

    depth = task.get("DEPTH", "MEDIUM").upper()
    try:
        hard_cap = int(task.get("HARD_CAP", "0"))
    except ValueError:
        hard_cap = 0
    ingested = progress.get("SOURCES_INGESTED", 0)
    if hard_cap > 0 and ingested >= hard_cap:
        return {"stop": True, "reason": f"hard_cap {ingested}/{hard_cap}"}

    phase = progress.get("PHASE", "FETCH")
    if phase == "INGEST" and depth in DIMINISHING:
        d = DIMINISHING[depth]
        recent = progress.get("RECENT_EDIT_CHARS", [])
        if ingested >= d["min_ingested"]:
            tail = recent[-d["last_n"]:]
            if len(tail) >= d["last_n"] and all(x < d["threshold"] for x in tail):
                return {"stop": True, "reason": f"diminishing_returns depth={depth} last_n={tail}"}

    return {"stop": False, "reason": None}


# --- commands ---

def cmd_status(task_dir):
    progress = read_progress(task_dir)
    task = read_task(task_dir)
    counts = count_statuses(task_dir)
    phase = progress.get("PHASE", "FETCH")
    if phase == "FETCH":
        want = "pending"
    elif phase == "REVIEW":
        want = None   # REVIEW loop reads WIKI_PAGES_TOUCHED, not a candidate queue
    else:
        want = "fetched"
    stop = check_stop(task_dir, progress, task, counts)
    next_c = None if (stop["stop"] or want is None) else pick_next_candidate(task_dir, want)
    out = {
        "phase": phase,
        "status": progress.get("STATUS"),
        "should_exit": stop["stop"],
        "stop_reason": stop["reason"],
        "next_candidate": next_c,
        "candidate_counts": counts,
        "counters": {
            "sources_fetched": progress["SOURCES_FETCHED"],
            "sources_ingested": progress["SOURCES_INGESTED"],
            "sources_skipped": progress["SOURCES_SKIPPED"],
        },
        "recent_edit_chars": progress["RECENT_EDIT_CHARS"],
        "wiki_pages_touched": progress.get("WIKI_PAGES_TOUCHED", []),
        "task": {k: task.get(k) for k in ("DEPTH", "HARD_CAP", "LANGUAGE", "RESEARCH_FOCUS", "WIKI_TARGET")},
    }
    print(json.dumps(out, indent=2, ensure_ascii=False))


def cmd_mark(task_dir, url_substr, new_status, raw_path=None):
    path = Path(task_dir) / "candidates.md"
    lines = path.read_text(encoding="utf-8-sig").splitlines()

    block_start = None
    for i, line in enumerate(lines):
        if line.startswith("- ") and url_substr in line:
            block_start = i
            break

    if block_start is None:
        print(json.dumps({"ok": False, "error": f"no candidate matching '{url_substr}'"}))
        sys.exit(1)

    # find end of block (next entry or EOF)
    block_end = block_start + 1
    while block_end < len(lines) and lines[block_end].startswith("  "):
        block_end += 1

    # update status: line
    status_updated = False
    for j in range(block_start + 1, block_end):
        if lines[j].strip().startswith("status: "):
            lines[j] = f"  status: {new_status}"
            status_updated = True
            break
    if not status_updated:
        lines.insert(block_start + 1, f"  status: {new_status}")
        block_end += 1

    # update raw: line if provided
    if raw_path:
        raw_updated = False
        for j in range(block_start + 1, block_end):
            if lines[j].strip().startswith("raw: "):
                lines[j] = f"  raw: {raw_path}"
                raw_updated = True
                break
        if not raw_updated:
            # insert after status line
            for j in range(block_start + 1, block_end):
                if lines[j].strip().startswith("status: "):
                    lines.insert(j + 1, f"  raw: {raw_path}")
                    break

    path.write_text("\n".join(lines) + "\n", encoding="utf-8")
    print(json.dumps({"ok": True, "status": new_status}))


def cmd_update(task_dir, updates):
    progress = read_progress(task_dir)
    for item in updates:
        if "+=" in item:
            k, v = item.split("+=", 1)
            k, v = k.strip(), v.strip()
            lst = progress.get(k, [])
            if not isinstance(lst, list):
                lst = []
            try:
                lst.append(int(v))
            except ValueError:
                lst.append(v)
            if k == "RECENT_EDIT_CHARS":
                lst = lst[-5:]
            progress[k] = lst
        elif "=" in item:
            k, v = item.split("=", 1)
            k, v = k.strip(), v.strip()
            if k in INT_KEYS:
                try:
                    progress[k] = int(v)
                except ValueError:
                    progress[k] = v
            else:
                progress[k] = v
    write_progress(task_dir, progress)
    print(json.dumps({"ok": True}))


def cmd_check_stop(task_dir):
    progress = read_progress(task_dir)
    task = read_task(task_dir)
    counts = count_statuses(task_dir)
    result = check_stop(task_dir, progress, task, counts)
    print(json.dumps(result))


if __name__ == "__main__":
    if len(sys.argv) < 3:
        print(__doc__)
        sys.exit(1)
    cmd, task_dir = sys.argv[1], sys.argv[2]
    if cmd == "status":
        cmd_status(task_dir)
    elif cmd == "mark":
        if len(sys.argv) < 5:
            print("usage: mark <task_dir> <url_substr> <status> [raw_path]", file=sys.stderr)
            sys.exit(1)
        raw = sys.argv[5] if len(sys.argv) > 5 else None
        cmd_mark(task_dir, sys.argv[3], sys.argv[4], raw)
    elif cmd == "update":
        cmd_update(task_dir, sys.argv[3:])
    elif cmd == "check-stop":
        cmd_check_stop(task_dir)
    else:
        print(f"unknown command: {cmd}", file=sys.stderr)
        sys.exit(1)
