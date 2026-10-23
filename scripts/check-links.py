#!/usr/bin/env python3
"""Check relative links and heading anchors in the repo's Markdown and HTML files.

Usage: python3 scripts/check-links.py
Exits non-zero and lists every broken link. External (http/https/mailto) links are not fetched.
"""
import pathlib
import re
import sys

ROOT = pathlib.Path(__file__).resolve().parent.parent
LINK = re.compile(r"(?<!\!)\[[^\]]*\]\(([^)\s]+)\)")
HREF = re.compile(r'href="([^"]+)"')
FENCE = re.compile(r"^\s*```")


def slug(heading: str) -> str:
    """GitHub-style heading anchor."""
    text = re.sub(r"[`*_]", "", heading.strip().lower())
    text = re.sub(r"[^\w\- ]", "", text)
    return text.replace(" ", "-")


def anchors(path: pathlib.Path) -> set:
    found, seen, in_fence = set(), {}, False
    for line in path.read_text(encoding="utf-8").splitlines():
        if FENCE.match(line):
            in_fence = not in_fence
            continue
        m = re.match(r"^#{1,6}\s+(.*)$", line)
        if m and not in_fence:
            base = slug(m.group(1))
            n = seen.get(base, 0)
            seen[base] = n + 1
            found.add(base if n == 0 else f"{base}-{n}")
    return found


def main() -> int:
    errors = []
    md_files = sorted(
        p for p in list(ROOT.rglob("*.md")) + list(ROOT.rglob("*.html")) if ".git" not in p.parts
    )
    cache = {}
    for md in md_files:
        in_fence = False
        for lineno, line in enumerate(md.read_text(encoding="utf-8").splitlines(), 1):
            if md.suffix == ".md" and FENCE.match(line):
                in_fence = not in_fence
                continue
            if in_fence:
                continue
            for target in LINK.findall(line) + HREF.findall(line):
                if re.match(r"^[a-z][a-z0-9+.-]*:", target):
                    continue
                path_part, _, frag = target.partition("#")
                dest = md if not path_part else (md.parent / path_part).resolve()
                rel = md.relative_to(ROOT)
                if not dest.exists():
                    errors.append(f"{rel}:{lineno}: missing file {target}")
                    continue
                if frag and dest.suffix == ".md":
                    cache.setdefault(dest, anchors(dest))
                    if frag not in cache[dest]:
                        errors.append(f"{rel}:{lineno}: missing anchor {target}")
    for e in errors:
        print(e)
    print(f"checked {len(md_files)} files, {len(errors)} problem(s)")
    return 1 if errors else 0


if __name__ == "__main__":
    sys.exit(main())
