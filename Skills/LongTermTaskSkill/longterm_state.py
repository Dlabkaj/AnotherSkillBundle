#!/usr/bin/env python3
"""
longterm_state.py - state machine helper for LongTermTaskSkill

Folder layout (MemoryVault/LongTermTask/<slug>/):
  task.md              GOAL, METRICS, ITER_LIMIT, PARTIAL_ITER_LIMIT, MODE, AUTO_RELAUNCH, TELEGRAM_NOTIFY
  partial-tasks.md     ordered list: [01] slug: summary + status/repeatable/iter_limit/iter_count
  progress.md          STATUS, ITER, CURRENT_PARTIAL, LAST_ERROR, LAST_VERIFY, AUTO_RELAUNCH_COUNT
  iter-log.txt         dispatcher log
  STOP.md              (optional) kill switch
  partial/<NN-slug>/partial.md     GOAL, METRICS, REPEATABLE, ITER_LIMIT
  partial/<NN-slug>/steps.md       ordered: [NN] description + status [+ error]

Commands:
  init <task_dir>                                   bootstrap progress.md from task.md
  status <task_dir>                                 JSON snapshot: overall + next partial
  next-partial <task_dir>                           JSON for next pending partial (or null)
  next-step <task_dir> <partial_slug>               JSON for next pending step in partial (or null)
  mark-step <task_dir> <partial_slug> <step_id> <status> [error_msg]
  mark-partial <task_dir> <partial_slug> <status>
  inc-partial-iter <task_dir> <partial_slug>        +1 to partial's iter_count
  reset-steps <task_dir> <partial_slug> <id> [<id> ...]   set listed steps back to pending
  update <task_dir> KEY=VAL ...                     update progress.md (KEY+=N for counters)
  check-stop <task_dir>                             JSON {stop, reason}

Status vocab:
  partial:   pending | in-progress | done | error | skipped
  step:      pending | done | error
  task:      READY | RUNNING | COMPLETE | STOP_ITER_LIMIT | STOP_ERROR | STOP_BLOCKED | STOP_USER

Exit codes: 0 = ok, 1 = error
"""
import sys
import json
import re
from pathlib import Path

PROGRESS_KEYS = [
    "STATUS", "ITER", "CURRENT_PARTIAL", "LAST_ERROR", "LAST_VERIFY", "AUTO_RELAUNCH_COUNT",
]
INT_KEYS = {"ITER", "AUTO_RELAUNCH_COUNT"}

VALID_PARTIAL_STATUS = {"pending", "in-progress", "done", "error", "skipped"}
VALID_STEP_STATUS = {"pending", "done", "error"}


# --- progress.md ---

def read_progress(task_dir):
    p = Path(task_dir) / "progress.md"
    if not p.exists():
        return {k: (0 if k in INT_KEYS else "") for k in PROGRESS_KEYS}
    data = {}
    for line in p.read_text(encoding="utf-8-sig").splitlines():
        if ": " in line:
            k, v = line.split(": ", 1)
            k, v = k.strip(), v.strip()
            if k in INT_KEYS:
                try:
                    data[k] = int(v)
                except ValueError:
                    data[k] = 0
            else:
                data[k] = v
    for k in PROGRESS_KEYS:
        data.setdefault(k, 0 if k in INT_KEYS else "")
    return data


def write_progress(task_dir, data):
    lines = []
    seen = set()
    for k in PROGRESS_KEYS:
        lines.append(f"{k}: {data.get(k, 0 if k in INT_KEYS else '')}")
        seen.add(k)
    for k, v in data.items():
        if k not in seen:
            lines.append(f"{k}: {v}")
    (Path(task_dir) / "progress.md").write_text("\n".join(lines) + "\n", encoding="utf-8")


# --- task.md ---

def read_task(task_dir):
    p = Path(task_dir) / "task.md"
    data = {}
    cur_list_key = None
    for line in p.read_text(encoding="utf-8-sig").splitlines():
        m = re.match(r"^([A-Z_]+):\s*(.*)$", line)
        if m:
            k, v = m.group(1), m.group(2).strip()
            if v == "":
                cur_list_key = k
                data[k] = []
            else:
                data[k] = v
                cur_list_key = None
        elif cur_list_key and line.strip().startswith("- "):
            data[cur_list_key].append(line.strip()[2:])
    return data


# --- partial-tasks.md ---

PARTIAL_HEAD_RE = re.compile(r"^- \[(\d+)\]\s+([^:]+):\s*(.+)$")


def parse_partials(task_dir):
    """Return list of dicts: {idx, slug, summary, status, repeatable, iter_limit, iter_count, last_error}."""
    p = Path(task_dir) / "partial-tasks.md"
    if not p.exists():
        return []
    lines = p.read_text(encoding="utf-8-sig").splitlines()
    result = []
    i = 0
    while i < len(lines):
        m = PARTIAL_HEAD_RE.match(lines[i])
        if m:
            entry = {
                "idx": m.group(1),
                "slug": m.group(2).strip(),
                "summary": m.group(3).strip(),
                "status": "pending",
                "repeatable": False,
                "iter_limit": 5,
                "iter_count": 0,
                "last_error": "",
            }
            j = i + 1
            while j < len(lines) and lines[j].startswith("  "):
                kv = lines[j].strip()
                if ": " in kv:
                    k, v = kv.split(": ", 1)
                    k, v = k.strip(), v.strip()
                    if k == "repeatable":
                        entry["repeatable"] = v.lower() in ("true", "yes", "1")
                    elif k in ("iter_limit", "iter_count"):
                        try:
                            entry[k] = int(v)
                        except ValueError:
                            pass
                    elif k in ("status", "last_error"):
                        entry[k] = v
                j += 1
            entry["partial_dir"] = f"partial/{entry['idx']}-{entry['slug']}"
            result.append(entry)
            i = j
        else:
            i += 1
    return result


def write_partials(task_dir, partials):
    lines = []
    for e in partials:
        lines.append(f"- [{e['idx']}] {e['slug']}: {e['summary']}")
        lines.append(f"  status: {e['status']}")
        lines.append(f"  repeatable: {'true' if e['repeatable'] else 'false'}")
        lines.append(f"  iter_limit: {e['iter_limit']}")
        lines.append(f"  iter_count: {e['iter_count']}")
        if e.get("last_error"):
            lines.append(f"  last_error: {e['last_error']}")
    (Path(task_dir) / "partial-tasks.md").write_text("\n".join(lines) + "\n", encoding="utf-8")


# --- steps.md (per partial) ---

STEP_HEAD_RE = re.compile(r"^- \[(\d+)\]\s+(.+)$")


def parse_steps(task_dir, partial):
    p = Path(task_dir) / partial["partial_dir"] / "steps.md"
    if not p.exists():
        return []
    lines = p.read_text(encoding="utf-8-sig").splitlines()
    result = []
    i = 0
    while i < len(lines):
        m = STEP_HEAD_RE.match(lines[i])
        if m:
            entry = {
                "id": m.group(1),
                "description": m.group(2).strip(),
                "status": "pending",
                "error": "",
            }
            j = i + 1
            while j < len(lines) and lines[j].startswith("  "):
                kv = lines[j].strip()
                if kv.startswith("status: "):
                    entry["status"] = kv[8:]
                elif kv.startswith("error: "):
                    entry["error"] = kv[7:]
                j += 1
            result.append(entry)
            i = j
        else:
            i += 1
    return result


def write_steps(task_dir, partial, steps):
    p = Path(task_dir) / partial["partial_dir"] / "steps.md"
    lines = []
    for s in steps:
        lines.append(f"- [{s['id']}] {s['description']}")
        lines.append(f"  status: {s['status']}")
        if s.get("error"):
            lines.append(f"  error: {s['error']}")
    p.write_text("\n".join(lines) + "\n", encoding="utf-8")


# --- helpers ---

def find_next_partial(partials):
    """First pending or in-progress partial."""
    for e in partials:
        if e["status"] in ("pending", "in-progress"):
            return e
    return None


def find_partial(partials, slug):
    for e in partials:
        if e["slug"] == slug:
            return e
    return None


def find_next_step(steps):
    for s in steps:
        if s["status"] == "pending":
            return s
    return None


# --- stop conditions ---

def check_stop(task_dir, progress, task, partials):
    status = progress.get("STATUS", "")
    if status.startswith("STOP_") or status == "COMPLETE":
        return {"stop": True, "reason": f"status={status}"}
    if (Path(task_dir) / "STOP.md").exists():
        return {"stop": True, "reason": "STOP.md present"}
    try:
        iter_limit = int(task.get("ITER_LIMIT", "5"))
    except (TypeError, ValueError):
        iter_limit = 5
    if progress.get("ITER", 0) >= iter_limit:
        return {"stop": True, "reason": f"iter_limit reached ({progress['ITER']}/{iter_limit})"}
    # any partial errored?
    for e in partials:
        if e["status"] == "error":
            return {"stop": True, "reason": f"partial '{e['slug']}' status=error"}
    # all done or skipped?
    if partials and all(e["status"] in ("done", "skipped") for e in partials):
        return {"stop": True, "reason": "all partials done"}
    return {"stop": False, "reason": None}


# --- commands ---

def cmd_init(task_dir):
    task = read_task(task_dir)
    progress = {
        "STATUS": "READY",
        "ITER": 0,
        "CURRENT_PARTIAL": "",
        "LAST_ERROR": "",
        "LAST_VERIFY": "",
        "AUTO_RELAUNCH_COUNT": 0,
    }
    write_progress(task_dir, progress)
    print(json.dumps({"ok": True, "goal": task.get("GOAL", "")}))


def cmd_status(task_dir):
    progress = read_progress(task_dir)
    task = read_task(task_dir)
    partials = parse_partials(task_dir)
    stop = check_stop(task_dir, progress, task, partials)
    next_p = None if stop["stop"] else find_next_partial(partials)
    counts = {}
    for e in partials:
        counts[e["status"]] = counts.get(e["status"], 0) + 1
    out = {
        "status": progress.get("STATUS"),
        "iter": progress.get("ITER", 0),
        "iter_limit": int(task.get("ITER_LIMIT", "5")),
        "current_partial": progress.get("CURRENT_PARTIAL", ""),
        "last_error": progress.get("LAST_ERROR", ""),
        "should_exit": stop["stop"],
        "stop_reason": stop["reason"],
        "next_partial": next_p,
        "partial_counts": counts,
        "task": {k: task.get(k) for k in ("GOAL", "ITER_LIMIT", "PARTIAL_ITER_LIMIT", "MODE", "AUTO_RELAUNCH", "TELEGRAM_NOTIFY")},
    }
    print(json.dumps(out, indent=2, ensure_ascii=False))


def cmd_next_partial(task_dir):
    partials = parse_partials(task_dir)
    nxt = find_next_partial(partials)
    print(json.dumps(nxt, ensure_ascii=False))


def cmd_next_step(task_dir, partial_slug):
    partials = parse_partials(task_dir)
    p = find_partial(partials, partial_slug)
    if not p:
        print(json.dumps({"error": f"partial '{partial_slug}' not found"}))
        sys.exit(1)
    steps = parse_steps(task_dir, p)
    nxt = find_next_step(steps)
    print(json.dumps(nxt, ensure_ascii=False))


def cmd_mark_step(task_dir, partial_slug, step_id, new_status, error_msg=None):
    if new_status not in VALID_STEP_STATUS:
        print(json.dumps({"ok": False, "error": f"invalid step status '{new_status}'"}))
        sys.exit(1)
    partials = parse_partials(task_dir)
    p = find_partial(partials, partial_slug)
    if not p:
        print(json.dumps({"ok": False, "error": f"partial '{partial_slug}' not found"}))
        sys.exit(1)
    steps = parse_steps(task_dir, p)
    found = False
    for s in steps:
        if s["id"] == step_id:
            s["status"] = new_status
            if error_msg is not None:
                s["error"] = error_msg
            elif new_status != "error":
                s["error"] = ""
            found = True
            break
    if not found:
        print(json.dumps({"ok": False, "error": f"step '{step_id}' not found"}))
        sys.exit(1)
    write_steps(task_dir, p, steps)
    print(json.dumps({"ok": True, "step": step_id, "status": new_status}))


def cmd_mark_partial(task_dir, partial_slug, new_status):
    if new_status not in VALID_PARTIAL_STATUS:
        print(json.dumps({"ok": False, "error": f"invalid partial status '{new_status}'"}))
        sys.exit(1)
    partials = parse_partials(task_dir)
    found = False
    for e in partials:
        if e["slug"] == partial_slug:
            e["status"] = new_status
            found = True
            break
    if not found:
        print(json.dumps({"ok": False, "error": f"partial '{partial_slug}' not found"}))
        sys.exit(1)
    write_partials(task_dir, partials)
    print(json.dumps({"ok": True, "partial": partial_slug, "status": new_status}))


def cmd_inc_partial_iter(task_dir, partial_slug):
    partials = parse_partials(task_dir)
    found = False
    new_count = 0
    for e in partials:
        if e["slug"] == partial_slug:
            e["iter_count"] += 1
            new_count = e["iter_count"]
            found = True
            break
    if not found:
        print(json.dumps({"ok": False, "error": f"partial '{partial_slug}' not found"}))
        sys.exit(1)
    write_partials(task_dir, partials)
    print(json.dumps({"ok": True, "iter_count": new_count}))


def cmd_reset_steps(task_dir, partial_slug, step_ids):
    partials = parse_partials(task_dir)
    p = find_partial(partials, partial_slug)
    if not p:
        print(json.dumps({"ok": False, "error": f"partial '{partial_slug}' not found"}))
        sys.exit(1)
    steps = parse_steps(task_dir, p)
    reset = []
    target = set(step_ids)
    for s in steps:
        if s["id"] in target:
            s["status"] = "pending"
            s["error"] = ""
            reset.append(s["id"])
    write_steps(task_dir, p, steps)
    print(json.dumps({"ok": True, "reset": reset}))


def cmd_update(task_dir, updates):
    progress = read_progress(task_dir)
    for item in updates:
        if "+=" in item:
            k, v = item.split("+=", 1)
            k, v = k.strip(), v.strip()
            try:
                progress[k] = int(progress.get(k, 0)) + int(v)
            except ValueError:
                progress[k] = v
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
    partials = parse_partials(task_dir)
    print(json.dumps(check_stop(task_dir, progress, task, partials)))


# --- entry point ---

DISPATCH = {
    "init":             (cmd_init,             1),
    "status":           (cmd_status,           1),
    "next-partial":     (cmd_next_partial,     1),
    "next-step":        (cmd_next_step,        2),
    "mark-partial":     (cmd_mark_partial,     3),
    "inc-partial-iter": (cmd_inc_partial_iter, 2),
    "update":           (cmd_update,           "variadic"),
    "check-stop":       (cmd_check_stop,       1),
}


def main():
    if len(sys.argv) < 3:
        print(__doc__)
        sys.exit(1)
    cmd = sys.argv[1]
    task_dir = sys.argv[2]
    rest = sys.argv[3:]
    if cmd == "init":
        cmd_init(task_dir)
    elif cmd == "status":
        cmd_status(task_dir)
    elif cmd == "next-partial":
        cmd_next_partial(task_dir)
    elif cmd == "next-step":
        if len(rest) < 1:
            print("usage: next-step <task_dir> <partial_slug>", file=sys.stderr); sys.exit(1)
        cmd_next_step(task_dir, rest[0])
    elif cmd == "mark-step":
        if len(rest) < 3:
            print("usage: mark-step <task_dir> <partial_slug> <step_id> <status> [error_msg]", file=sys.stderr); sys.exit(1)
        err = rest[3] if len(rest) > 3 else None
        cmd_mark_step(task_dir, rest[0], rest[1], rest[2], err)
    elif cmd == "mark-partial":
        if len(rest) < 2:
            print("usage: mark-partial <task_dir> <partial_slug> <status>", file=sys.stderr); sys.exit(1)
        cmd_mark_partial(task_dir, rest[0], rest[1])
    elif cmd == "inc-partial-iter":
        if len(rest) < 1:
            print("usage: inc-partial-iter <task_dir> <partial_slug>", file=sys.stderr); sys.exit(1)
        cmd_inc_partial_iter(task_dir, rest[0])
    elif cmd == "reset-steps":
        if len(rest) < 2:
            print("usage: reset-steps <task_dir> <partial_slug> <step_id> [<step_id> ...]", file=sys.stderr); sys.exit(1)
        cmd_reset_steps(task_dir, rest[0], rest[1:])
    elif cmd == "update":
        cmd_update(task_dir, rest)
    elif cmd == "check-stop":
        cmd_check_stop(task_dir)
    else:
        print(f"unknown command: {cmd}", file=sys.stderr)
        sys.exit(1)


if __name__ == "__main__":
    main()
