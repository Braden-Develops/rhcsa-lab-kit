#!/usr/bin/env python3
"""Bundle the lab kit's Markdown into docs/content.js for the GitHub Pages site.

Run from the repo root after editing any guide or lab file:
    python3 tools/build-site.py
"""
import json
import pathlib
import re

ROOT = pathlib.Path(__file__).resolve().parent.parent
OUT = ROOT / "docs" / "content.js"


def read(p):
    return p.read_text(encoding="utf-8") if p.exists() else ""


def slugify(s):
    s = re.sub(r"`[^`]*`", "", s)
    s = re.split(r"→\s*`?labs/", s)[0]
    s = re.sub(r"[^a-z0-9]+", "-", s.lower()).strip("-")
    return s


def split_sections(md):
    """Split a Markdown file on '## ' headings (ignoring fenced code)."""
    intro, sections, cur, fence = [], [], None, False
    for line in md.splitlines():
        if line.startswith("```"):
            fence = not fence
        if not fence and line.startswith("## "):
            title = line[3:].strip()
            cur = {"title": title, "body": []}
            sections.append(cur)
            continue
        (cur["body"] if cur else intro).append(line)
    for s in sections:
        s["body"] = "\n".join(s["body"]).strip().strip("-").strip()
    return "\n".join(intro).strip(), sections


def parse_conf(text):
    conf = {}
    for line in text.splitlines():
        m = re.match(r'^(\w+)="?(.*?)"?$', line.strip())
        if m:
            conf[m.group(1)] = m.group(2)
    return conf


def guide():
    intro, secs = split_sections(read(ROOT / "STUDY-GUIDE.md"))
    title_line, _, intro_body = intro.partition("\n")
    out = []
    for s in secs:
        m = re.match(r"^(\d+)\.\s+(.*)$", s["title"])
        num = m.group(1) if m else None
        name = re.split(r"\s*→\s*`labs/", m.group(2) if m else s["title"])[0].strip()
        labs = sorted(set(re.findall(r"labs/(\d\d)-", s["title"])))
        out.append({
            "slug": (f"{num}-" if num else "") + slugify(name),
            "num": num,
            "title": name,
            "labs": labs,
            "body": s["body"],
        })
    return {"title": title_line.lstrip("# ").strip(), "intro": intro_body.strip(), "sections": out}


def objectives():
    intro, secs = split_sections(read(ROOT / "OBJECTIVES.md"))
    groups, notes = [], []
    for s in secs:
        rows = []
        for line in s["body"].splitlines():
            cells = [c.strip().replace("\\|", "|") for c in re.split(r"(?<!\\)\|", line.strip())[1:-1]]
            if len(cells) == 3 and re.fullmatch(r"\d+\.\d+", cells[0]):
                rows.append(cells)
        if rows:
            m = re.match(r"^(\d+)\.\s+(.*)$", s["title"])
            groups.append({
                "num": m.group(1) if m else "",
                "title": m.group(2) if m else s["title"],
                "items": [{"id": i, "text": t, "labs": l} for i, t, l in rows],
            })
        else:
            notes.append(f"## {s['title']}\n\n{s['body']}")
    return {"intro": "\n".join(intro.splitlines()[1:]).strip(), "groups": groups, "notes": "\n\n".join(notes)}


def labs():
    out = []
    for d in sorted((ROOT / "labs").iterdir()):
        if not d.is_dir():
            continue
        conf = parse_conf(read(d / "lab.conf"))
        files = {}
        for name in ("setup.sh", "check.sh", "Dockerfile", "lab.conf"):
            if (d / name).exists():
                files[name] = read(d / name)
        out.append({
            "id": d.name[:2],
            "dir": d.name,
            "title": conf.get("TITLE", d.name),
            "runtime": conf.get("RUNTIME", "container"),
            "tasks": read(d / "TASKS.md"),
            "solution": read(d / "SOLUTION.md"),
            "files": files,
        })
    return out


def lectures():
    """lectures/NN-name.md: long-form reading, one per exam section (NN = section number)."""
    out = []
    d = ROOT / "lectures"
    if not d.exists():
        return out
    for f in sorted(d.glob("[0-9][0-9]-*.md")):
        text = read(f)
        first, _, body = text.partition("\n")
        title = re.sub(r"^#\s*(Lecture\s+\d+:\s*)?", "", first).strip()
        out.append({
            "num": str(int(f.name[:2])),
            "slug": f.stem,
            "title": title,
            "body": body.strip(),
            "words": len(re.sub(r"```.*?```", "", body, flags=re.S).split()),
        })
    return out


def main():
    data = {
        "readme": read(ROOT / "README.md"),
        "guide": guide(),
        "objectives": objectives(),
        "labs": labs(),
        "lectures": lectures(),
    }
    OUT.parent.mkdir(exist_ok=True)
    OUT.write_text("window.KIT = " + json.dumps(data, ensure_ascii=False, indent=1) + ";\n", encoding="utf-8")
    n = sum(len(g["items"]) for g in data["objectives"]["groups"])
    print(f"wrote {OUT.relative_to(ROOT)}: {len(data['guide']['sections'])} guide sections, "
          f"{n} objectives, {len(data['labs'])} labs, {len(data['lectures'])} lectures "
          f"({sum(l['words'] for l in data['lectures'])} words)")


if __name__ == "__main__":
    main()
