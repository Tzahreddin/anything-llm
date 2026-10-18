#!/usr/bin/env python3
"""PM-knowledge wiki control plane (DEC-0030 / Hermes llm-wiki adapted).

All mutations go through allowlists; git commit/push to local bare for archive.
No Obsidian. Tags must come from SCHEMA taxonomy unless propose_new + confirm.
"""
from __future__ import annotations

import argparse
import hashlib
import json
import os
import re
import shutil
import subprocess
import sys
import urllib.error
import urllib.request
from datetime import date
from pathlib import Path

REPO = Path(os.environ.get("WIKI_REPO", "/srv/PM-knowledge"))
BARE = os.environ.get("WIKI_BARE", "/srv/git/PM-knowledge.git")
BRANCH_PREFIX = os.environ.get("WIKI_BRANCH_PREFIX", "wiki/")
PLAN_ID_RE = re.compile(r"^plan_\d{4}_\d{2}_\d{2}_[A-Za-z0-9_-]+$")
LAYER2 = ("entities", "concepts", "comparisons", "queries")
ALLOW_WRITE_ROOTS = LAYER2 + ("_archive", ".plans")
META_FILES = ("SCHEMA.md", "index.md", "log.md")


def die(msg: str, code: int = 1) -> None:
    print(msg, file=sys.stderr)
    raise SystemExit(code)


def run_git(*args: str, check: bool = True) -> subprocess.CompletedProcess[str]:
    return subprocess.run(
        ["git", "-C", str(REPO), *args],
        text=True,
        capture_output=True,
        check=check,
    )


def _git_quiet(*args: str, cwd: Path = None, check: bool = True) -> None:
    env = {**os.environ, "GIT_TEMPLATE_DIR": ""}
    cmd = ["git", "-C", str(cwd), *args] if cwd is not None else ["git", *args]
    subprocess.run(
        cmd,
        check=check,
        env=env,
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
    )


def ensure_repo() -> None:
    if not REPO.is_dir():
        die(f"WIKI_REPO missing: {REPO}", 66)


def is_dirty(*, ignore_plans: bool = False) -> bool:
    r = run_git("status", "--porcelain", check=False)
    lines = [ln for ln in r.stdout.splitlines() if ln.strip()]
    if ignore_plans:
        lines = [ln for ln in lines if ".plans/" not in ln]
    return bool(lines)


def safe_rel(path: str) -> Path:
    p = Path(path)
    if p.is_absolute() or ".." in p.parts:
        die(f"Illegal path: {path}", 64)
    return p


def under_allowlist(rel: Path) -> bool:
    s = rel.as_posix()
    if s in META_FILES:
        return True
    if s.startswith("raw/"):
        return False  # raw immutable via apply; use write_raw
    top = rel.parts[0] if rel.parts else ""
    return top in ALLOW_WRITE_ROOTS


def cmd_status(_: argparse.Namespace) -> None:
    ensure_repo()
    branch = run_git("rev-parse", "--abbrev-ref", "HEAD", check=False).stdout.strip()
    head = run_git("rev-parse", "--short", "HEAD", check=False).stdout.strip()
    print(
        json.dumps(
            {
                "repo": str(REPO),
                "bare": BARE,
                "branch": branch,
                "head": head,
                "dirty": is_dirty(),
            }
        )
    )


def cmd_orient(_: argparse.Namespace) -> None:
    ensure_repo()
    out = {}
    for name in META_FILES:
        p = REPO / name
        if p.is_file():
            text = p.read_text(encoding="utf-8")
            if name == "log.md":
                lines = text.splitlines()
                text = "\n".join(lines[-40:])
            out[name] = text
        else:
            out[name] = None
    print(json.dumps(out))


def _schema_template(domain: str) -> str:
    today = date.today().isoformat()
    return f"""# Wiki Schema

## Domain
{domain}

## Conventions
- File names: lowercase, hyphens, no spaces
- Every wiki page starts with YAML frontmatter
- Use `[[wikilinks]]` (minimum 2 outbound links per page)
- When updating a page, bump the `updated` date
- Every new page must be listed in `index.md`
- Every action must be appended to `log.md`
- No Obsidian-specific features required
- **Archive** = move to `_archive/` + git commit to local bare (not delete)

## Frontmatter
```yaml
---
title: Page Title
created: {today}
updated: {today}
type: entity | concept | comparison | query | summary
tags: []  # MUST be from Tag Taxonomy below
sources: []
confidence: high | medium | low
contested: true  # optional
contradictions: []  # optional page slugs
---
```

## Tag Taxonomy
<!-- Keep small. Add tags here BEFORE using them. Prefer reuse over new tags. -->
- pm
- openproject
- process
- decision
- risk
- stakeholder
- delivery

## Tag Policy (anti-inflation)
- Nur Tags aus dieser Taxonomie verwenden.
- Neue Tags nur vorschlagen, wenn klarer Mehrwert für Auffindbarkeit, Filterung oder Auswertung.
- Vorschlag neuer Tags braucht Nutzer-Bestätigung und Eintrag hier zuerst.
- Semantic Router / LLM (`wiki_tag_route`) mappt Inhalte auf bestehende Tags; keine Tag-Flut.

## Page Thresholds
- Create when entity/concept appears in 2+ sources OR is central to one source
- Don't create for passing mentions
- Archive when fully superseded → `_archive/<layer>/…` + git commit to bare

## Update Policy
Newer sources generally supersede; note contradictions with dates; mark `contradictions:`.
Provenance: on pages synthesizing 3+ sources, append `^[raw/…]` after claims from a specific source.
"""


def cmd_init(ns: argparse.Namespace) -> None:
    domain = ns.domain or "Project management / OpenProject knowledge"
    REPO.mkdir(parents=True, exist_ok=True)
    bare = Path(BARE)
    bare.parent.mkdir(parents=True, exist_ok=True)
    needs_bare = (not bare.exists()) or (not (bare / "HEAD").exists() and not any(bare.iterdir()))
    if needs_bare:
        bare.mkdir(parents=True, exist_ok=True)
        _git_quiet("init", "--bare", str(bare))

    if not (REPO / ".git").exists():
        _git_quiet("init", cwd=REPO)
        _git_quiet("remote", "remove", "origin", cwd=REPO, check=False)
        _git_quiet("remote", "add", "origin", str(bare), cwd=REPO)
        _git_quiet("config", "user.email", "ki-basis-wiki@local", cwd=REPO)
        _git_quiet("config", "user.name", "ki-basis-pm-knowledge", cwd=REPO)

    for d in (
        "raw/articles",
        "raw/papers",
        "raw/transcripts",
        "raw/assets",
        "entities",
        "concepts",
        "comparisons",
        "queries",
        "_archive",
        ".plans",
    ):
        (REPO / d).mkdir(parents=True, exist_ok=True)

    today = date.today().isoformat()
    if not (REPO / "SCHEMA.md").exists():
        (REPO / "SCHEMA.md").write_text(_schema_template(domain), encoding="utf-8")
    if not (REPO / "index.md").exists():
        (REPO / "index.md").write_text(
            f"""# Wiki Index

> Last updated: {today} | Total pages: 0

## Entities

## Concepts

## Comparisons

## Queries
""",
            encoding="utf-8",
        )
    if not (REPO / "log.md").exists():
        (REPO / "log.md").write_text(
            f"""# Wiki Log

> Append-only. Format: `## [YYYY-MM-DD] action | subject`

## [{today}] create | Wiki initialized
- Domain: {domain}
- Workspace binding: ask user — existing AnythingLLM workspace OR create new
""",
            encoding="utf-8",
        )

    # initial commit if empty (quiet — JSON only on stdout)
    _git_quiet("add", "-A", cwd=REPO)
    st = run_git("status", "--porcelain", check=False)
    if st.stdout.strip():
        _git_quiet("commit", "-m", "wiki: initialize PM-knowledge", cwd=REPO)
        _git_quiet("branch", "-M", "main", cwd=REPO, check=False)
        _git_quiet("push", "-u", "origin", "main", cwd=REPO, check=False)

    print(
        json.dumps(
            {
                "status": "ok",
                "repo": str(REPO),
                "bare": str(bare),
                "prompt_workspace": (
                    "Ask the user: attach this wiki to an existing AnythingLLM "
                    "workspace, or create a new workspace? Record choice in log."
                ),
            }
        )
    )


def cmd_write_raw(ns: argparse.Namespace) -> None:
    ensure_repo()
    rel = safe_rel(ns.path)
    if not str(rel).startswith("raw/"):
        die("raw writes must be under raw/", 64)
    body = ns.body if ns.body is not None else sys.stdin.read()
    digest = hashlib.sha256(body.encode("utf-8")).hexdigest()
    today = date.today().isoformat()
    fm = (
        f"---\nsource_url: {ns.source_url or ''}\ningested: {today}\n"
        f"sha256: {digest}\n---\n\n"
    )
    dest = REPO / rel
    dest.parent.mkdir(parents=True, exist_ok=True)
    if dest.exists() and not ns.force:
        old = dest.read_text(encoding="utf-8")
        m = re.search(r"^sha256:\s*(\S+)", old, re.M)
        if m and m.group(1) == digest:
            print(json.dumps({"status": "unchanged", "path": str(rel)}))
            return
        print(json.dumps({"status": "drift", "path": str(rel), "old_sha": m.group(1) if m else None}))
    dest.write_text(fm + body, encoding="utf-8")
    print(json.dumps({"status": "written", "path": str(rel), "sha256": digest}))


def cmd_apply_plan(ns: argparse.Namespace) -> None:
    ensure_repo()
    if not PLAN_ID_RE.match(ns.plan_id):
        die("Invalid plan_id", 64)
    if is_dirty(ignore_plans=True):
        die("Repository dirty; refuse apply", 65)
    plan_dir = REPO / ".plans" / ns.plan_id
    manifest = plan_dir / "manifest.json"
    if not manifest.is_file():
        die(f"Missing plan: {manifest}", 66)
    data = json.loads(manifest.read_text(encoding="utf-8"))
    files = data.get("files") or []
    for item in files:
        rel = safe_rel(item["path"])
        if str(rel).startswith("raw/"):
            die("apply_plan cannot write raw/; use write_raw", 64)
        if not under_allowlist(rel):
            die(f"Path not allowlisted: {rel}", 64)
        content = item.get("content")
        if content is None:
            src = plan_dir / Path(item["path"]).name
            content = src.read_text(encoding="utf-8")
        dest = REPO / rel
        dest.parent.mkdir(parents=True, exist_ok=True)
        dest.write_text(content, encoding="utf-8")

    # optional index/log patches in manifest
    if data.get("index_md"):
        (REPO / "index.md").write_text(data["index_md"], encoding="utf-8")
    if data.get("log_append"):
        with (REPO / "log.md").open("a", encoding="utf-8") as fh:
            fh.write("\n" + data["log_append"].rstrip() + "\n")

    branch = f"{BRANCH_PREFIX}{ns.plan_id}"
    run_git("checkout", "-B", branch)
    run_git("add", "-A")
    has_staged = run_git("diff", "--cached", "--quiet", check=False).returncode != 0
    if has_staged:
        run_git(
            "commit",
            "-m",
            f"wiki: apply {ns.plan_id}",
            "-m",
            "Approved PM-knowledge change set.",
        )
        push = run_git("push", "-u", "origin", branch, check=False)
        print(
            json.dumps(
                {
                    "status": "committed",
                    "branch": branch,
                    "head": run_git("rev-parse", "--short", "HEAD").stdout.strip(),
                    "push_ok": push.returncode == 0,
                }
            )
        )
    else:
        print(json.dumps({"status": "no_changes"}))


def cmd_archive(ns: argparse.Namespace) -> None:
    ensure_repo()
    if is_dirty():
        die("Repository dirty; refuse archive", 65)
    rel = safe_rel(ns.path)
    src = REPO / rel
    if not src.is_file():
        die(f"Missing: {rel}", 66)
    if rel.parts[0] not in LAYER2:
        die("Only Layer-2 pages can be archived", 64)
    dest = REPO / "_archive" / rel
    dest.parent.mkdir(parents=True, exist_ok=True)
    if dest.exists():
        die(f"Archive target exists: {dest.relative_to(REPO)}", 65)
    shutil.move(str(src), str(dest))
    today = date.today().isoformat()
    with (REPO / "log.md").open("a", encoding="utf-8") as fh:
        fh.write(
            f"\n## [{today}] archive | {rel}\n"
            f"- Moved to `_archive/{rel.as_posix()}` (git commit to bare)\n"
        )
    # strip from index naively
    idx = REPO / "index.md"
    if idx.is_file():
        lines = [
            ln
            for ln in idx.read_text(encoding="utf-8").splitlines()
            if rel.stem not in ln and rel.name not in ln
        ]
        idx.write_text("\n".join(lines) + "\n", encoding="utf-8")
    branch = f"{BRANCH_PREFIX}archive-{date.today().strftime('%Y_%m_%d')}-{rel.stem}"[:80]
    run_git("checkout", "-B", branch)
    run_git("add", "-A")
    run_git("commit", "-m", f"wiki: archive {rel}")
    run_git("push", "-u", "origin", branch, check=False)
    print(
        json.dumps(
            {
                "status": "archived",
                "from": str(rel),
                "to": f"_archive/{rel.as_posix()}",
                "branch": branch,
            }
        )
    )


def cmd_lint(_: argparse.Namespace) -> None:
    ensure_repo()
    report: dict = {
        "orphans": [],
        "broken_links": [],
        "missing_from_index": [],
        "bad_frontmatter": [],
        "oversized": [],
        "tags_not_in_taxonomy": [],
        "contested": [],
        "low_confidence": [],
        "source_drift": [],
        "log_rotation_needed": False,
        "tags_in_use": [],
    }
    taxonomy = set(parse_taxonomy())

    pages: list[Path] = []
    for folder in LAYER2:
        pages.extend((REPO / folder).rglob("*.md"))

    link_re = re.compile(r"\[\[([^\]|#]+)(?:[|#][^\]]*)?\]\]")
    inbound: dict[str, int] = {}
    all_slugs = {p.stem for p in pages}
    tags_in_use: set[str] = set()
    required_fm = ("title:", "created:", "updated:", "type:", "tags:", "sources:")

    for p in pages:
        text = p.read_text(encoding="utf-8")
        rel = str(p.relative_to(REPO))
        if text.count("\n") > 200:
            report["oversized"].append(rel)
        if not text.startswith("---") or text.count("---") < 2:
            report["bad_frontmatter"].append(rel)
        else:
            fm_block = text.split("---", 2)[1]
            if any(f not in fm_block for f in required_fm):
                report["bad_frontmatter"].append(rel)
        if re.search(r"^contested:\s*true", text, re.M | re.I):
            report["contested"].append(rel)
        if re.search(r"^confidence:\s*low", text, re.M | re.I):
            report["low_confidence"].append(rel)
        for m in link_re.finditer(text):
            target = m.group(1).strip()
            inbound[target] = inbound.get(target, 0) + 1
            if target not in all_slugs and not (REPO / f"{target}.md").exists():
                if not any(x.stem == target for x in pages):
                    report["broken_links"].append({"from": rel, "to": target})
        tags = re.search(r"^tags:\s*\[([^\]]*)\]", text, re.M)
        if tags:
            for t in re.findall(r"[A-Za-z0-9_-]+", tags.group(1)):
                tags_in_use.add(t)
                if taxonomy and t not in taxonomy:
                    report["tags_not_in_taxonomy"].append({"page": rel, "tag": t})

    for p in pages:
        if inbound.get(p.stem, 0) == 0:
            report["orphans"].append(str(p.relative_to(REPO)))

    index = (REPO / "index.md").read_text(encoding="utf-8") if (REPO / "index.md").exists() else ""
    for p in pages:
        if p.stem not in index and p.name not in index:
            report["missing_from_index"].append(str(p.relative_to(REPO)))

    # source drift: raw sha256 vs body
    for rawp in (REPO / "raw").rglob("*.md") if (REPO / "raw").is_dir() else []:
        text = rawp.read_text(encoding="utf-8")
        if not text.startswith("---"):
            continue
        parts = text.split("---", 2)
        if len(parts) < 3:
            continue
        fm, body = parts[1], parts[2].lstrip("\n")
        m = re.search(r"^sha256:\s*(\S+)", fm, re.M)
        if not m:
            continue
        digest = hashlib.sha256(body.encode("utf-8")).hexdigest()
        if digest != m.group(1):
            report["source_drift"].append(str(rawp.relative_to(REPO)))

    log = REPO / "log.md"
    if log.is_file():
        entries = sum(1 for ln in log.read_text(encoding="utf-8").splitlines() if ln.startswith("## ["))
        report["log_rotation_needed"] = entries > 500
        report["log_entries"] = entries

    report["tags_in_use"] = sorted(tags_in_use)
    print(json.dumps(report, indent=2))


def cmd_search(ns: argparse.Namespace) -> None:
    ensure_repo()
    q = (ns.query or "").lower()
    hits = []
    for p in REPO.rglob("*.md"):
        if ".git" in p.parts or p.parts[0] == ".plans" if len(p.relative_to(REPO).parts) else False:
            continue
        try:
            text = p.read_text(encoding="utf-8")
        except OSError:
            continue
        if q in text.lower() or q in str(p).lower():
            hits.append(str(p.relative_to(REPO)))
    print(json.dumps({"query": ns.query, "hits": hits[:50]}))


def parse_taxonomy() -> list[str]:
    schema = REPO / "SCHEMA.md"
    tags: list[str] = []
    if not schema.is_file():
        return tags
    in_tax = False
    for ln in schema.read_text(encoding="utf-8").splitlines():
        if ln.startswith("## Tag Taxonomy"):
            in_tax = True
            continue
        if in_tax and ln.startswith("## "):
            break
        if in_tax and ln.strip().startswith("- "):
            tags.append(ln.strip()[2:].split()[0].strip(","))
    return tags


def cmd_tag_route(ns: argparse.Namespace) -> None:
    """Map text to taxonomy tags via Semantic Router or OpenAI-compatible LLM."""
    ensure_repo()
    taxonomy = parse_taxonomy()
    text = ns.text or sys.stdin.read()
    if not text.strip():
        die("No text", 64)

    router = os.environ.get("SEMANTIC_ROUTER_URL", "").rstrip("/")
    llm_base = os.environ.get(
        "WIKI_TAG_LLM_BASE",
        os.environ.get("GENERIC_OPEN_AI_BASE_PATH", "http://envoy:8801/v1"),
    ).rstrip("/")
    llm_model = os.environ.get(
        "WIKI_TAG_LLM_MODEL",
        os.environ.get("GENERIC_OPEN_AI_MODEL_PREF", "local"),
    )
    llm_key = os.environ.get("GENERIC_OPEN_AI_API_KEY", "local-not-used")

    prompt = (
        "Du bist Tag-Router für ein PM-knowledge Wiki. "
        "Wähle NUR Tags aus dieser Taxonomie (oder leere Liste). "
        "Keine inflationären neuen Tags. Nur wenn klarer Mehrwert für "
        "Auffindbarkeit/Filter/Auswertung. "
        f"Taxonomie: {taxonomy}. "
        "Antworte als JSON: {\"tags\":[...],\"propose_new\":[{\"tag\":\"...\",\"rationale\":\"...\"}]}. "
        "propose_new nur in Ausnahmefällen; standardmäßig [].\n\n"
        f"Text:\n{text[:6000]}"
    )

    result = {"tags": [], "propose_new": [], "engine": None}

    if router:
        try:
            req = urllib.request.Request(
                f"{router}/v1/classify",
                data=json.dumps({"text": text[:4000], "labels": taxonomy}).encode(),
                headers={"Content-Type": "application/json"},
                method="POST",
            )
            with urllib.request.urlopen(req, timeout=30) as resp:
                data = json.loads(resp.read().decode())
            # best-effort map
            labels = data.get("labels") or data.get("categories") or data.get("routes") or []
            if isinstance(labels, list):
                result["tags"] = [x for x in labels if x in taxonomy][:8]
            result["engine"] = "semantic-router"
        except (urllib.error.URLError, TimeoutError, json.JSONDecodeError) as exc:
            result["router_error"] = str(exc)

    if not result["tags"] and not result.get("engine"):
        try:
            payload = {
                "model": llm_model,
                "messages": [
                    {"role": "system", "content": "Return JSON only."},
                    {"role": "user", "content": prompt},
                ],
                "temperature": 0,
            }
            req = urllib.request.Request(
                f"{llm_base}/chat/completions",
                data=json.dumps(payload).encode(),
                headers={
                    "Content-Type": "application/json",
                    "Authorization": f"Bearer {llm_key}",
                },
                method="POST",
            )
            with urllib.request.urlopen(req, timeout=60) as resp:
                data = json.loads(resp.read().decode())
            content = data["choices"][0]["message"]["content"]
            m = re.search(r"\{[\s\S]*\}", content)
            parsed = json.loads(m.group(0) if m else content)
            tags = [t for t in parsed.get("tags", []) if t in taxonomy]
            result["tags"] = tags[:8]
            # never auto-apply propose_new
            result["propose_new"] = parsed.get("propose_new") or []
            result["engine"] = "llm"
        except Exception as exc:  # noqa: BLE001
            result["error"] = str(exc)
            result["engine"] = "fallback-empty"

    result["taxonomy_size"] = len(taxonomy)
    result["policy"] = "taxonomy-only; propose_new requires human confirm before SCHEMA edit"
    print(json.dumps(result, ensure_ascii=False))


def cmd_save_plan(ns: argparse.Namespace) -> None:
    ensure_repo()
    if not PLAN_ID_RE.match(ns.plan_id):
        die("Invalid plan_id", 64)
    plan_dir = REPO / ".plans" / ns.plan_id
    plan_dir.mkdir(parents=True, exist_ok=True)
    raw = ns.manifest if ns.manifest else sys.stdin.read()
    data = json.loads(raw)
    (plan_dir / "manifest.json").write_text(
        json.dumps(data, ensure_ascii=False, indent=2), encoding="utf-8"
    )
    print(json.dumps({"status": "saved", "plan_id": ns.plan_id, "path": str(plan_dir)}))


def main() -> None:
    ap = argparse.ArgumentParser(prog="wiki_ctl")
    sp = ap.add_subparsers(dest="cmd", required=True)

    sp.add_parser("status")
    sp.add_parser("orient")
    p = sp.add_parser("init")
    p.add_argument("--domain", default="")
    p = sp.add_parser("write-raw")
    p.add_argument("--path", required=True)
    p.add_argument("--source-url", default="")
    p.add_argument("--body", default=None)
    p.add_argument("--force", action="store_true")
    p = sp.add_parser("apply-plan")
    p.add_argument("plan_id")
    p = sp.add_parser("archive")
    p.add_argument("--path", required=True)
    sp.add_parser("lint")
    p = sp.add_parser("search")
    p.add_argument("--query", required=True)
    p = sp.add_parser("tag-route")
    p.add_argument("--text", default=None)
    p = sp.add_parser("save-plan")
    p.add_argument("plan_id")
    p.add_argument("--manifest", default=None)

    ns = ap.parse_args()
    {
        "status": cmd_status,
        "orient": cmd_orient,
        "init": cmd_init,
        "write-raw": cmd_write_raw,
        "apply-plan": cmd_apply_plan,
        "archive": cmd_archive,
        "lint": cmd_lint,
        "search": cmd_search,
        "tag-route": cmd_tag_route,
        "save-plan": cmd_save_plan,
    }[ns.cmd](ns)


if __name__ == "__main__":
    main()
