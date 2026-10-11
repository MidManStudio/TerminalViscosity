#!/usr/bin/env python3
# ============================================================================
# NOTICE: Full documentation, design decisions, and fix history for this file
# live in docs/CI.md, section "check_headers.py"
# ============================================================================
"""Enforces the documentation rules from DOCUMENTATION_AND_COMMENTING_GUIDELINES.md.

Checks:
  1. Every source file opens with the NOTICE header.
  2. The doc file named in the header exists and has a section for that file.
  3. Crate docs end with a "Fixes and Problems" section.
  4. Docs avoid em dashes and filler words.

Usage: python3 scripts/check_headers.py [repo_root]
"""
import re
import sys
from pathlib import Path

COMMENT = {
    ".rs": "//", ".odin": "//", ".h": "//", ".c": "//", ".fs": "//", ".vs": "//",
    ".py": "#", ".sh": "#", ".toml": "#",
}
SKIP_DIRS = {"target", ".git", "node_modules", "build", "references", ".mdix"}
BANNED = [r"\u2014", r"\bleverage[ds]?\b", r"\butiliz(e|es|ed|ing)\b", r"\bseamless(ly)?\b"]

HEADER_RE = re.compile(
    r'^(?P<c>//|#) ={20,}\n'
    r'(?P=c) NOTICE: Full documentation, design decisions, and fix history for this file\n'
    r'(?P=c) live in (?P<doc>docs/[\w./-]+\.md), section "(?P<section>[^"]+)"\n'
    r'(?P=c) ={20,}\n'
)


def source_files(root: Path):
    for path in sorted(root.rglob("*")):
        if not path.is_file() or path.suffix not in COMMENT:
            continue
        rel = path.relative_to(root)
        if any(part in SKIP_DIRS for part in rel.parts):
            continue
        yield path


def doc_root_for(path: Path, root: Path) -> Path:
    """Nearest ancestor directory that has a docs/ folder."""
    for parent in path.parents:
        if (parent / "docs").is_dir():
            return parent
        if parent == root:
            break
    return root


def has_section(doc_text: str, name: str) -> bool:
    pat = re.compile(rf"^#{{2,4}} `?{re.escape(name)}`?\s*$", re.MULTILINE)
    return bool(pat.search(doc_text))


def check_source(path: Path, root: Path, errors: list):
    rel = path.relative_to(root)
    text = path.read_text(encoding="utf-8")
    if text.startswith("#!"):
        text = text.split("\n", 1)[1] if "\n" in text else ""
    m = HEADER_RE.match(text)
    if not m:
        errors.append(f"{rel}: missing or malformed NOTICE header")
        return
    expected = COMMENT[path.suffix]
    if m.group("c") != expected:
        errors.append(f"{rel}: header uses '{m.group('c')}' but {path.suffix} files use '{expected}'")
    doc = doc_root_for(path, root) / m.group("doc")
    if not doc.is_file():
        errors.append(f"{rel}: header points at {m.group('doc')} which does not exist")
        return
    if not has_section(doc.read_text(encoding="utf-8"), m.group("section")):
        errors.append(f"{rel}: {doc.relative_to(root)} has no section for \"{m.group('section')}\"")
    elif m.group("section") != path.name:
        errors.append(f"{rel}: header section \"{m.group('section')}\" should be \"{path.name}\"")


def check_docs(root: Path, errors: list):
    for doc in sorted(root.rglob("*.md")):
        rel = doc.relative_to(root)
        if any(part in SKIP_DIRS for part in rel.parts):
            continue
        text = doc.read_text(encoding="utf-8")
        for pat in BANNED:
            hit = re.search(pat, text, re.IGNORECASE)
            if hit:
                line = text[: hit.start()].count("\n") + 1
                errors.append(f"{rel}:{line}: banned wording {hit.group(0)!r}")
        if "## Modules" in text:
            h2 = re.findall(r"^## (.+?)\s*$", text, re.MULTILINE)
            if not h2 or h2[-1] != "Fixes and Problems":
                errors.append(f"{rel}: last '##' section must be 'Fixes and Problems'")


def main() -> int:
    root = Path(sys.argv[1] if len(sys.argv) > 1 else ".").resolve()
    errors: list = []
    count = 0
    for path in source_files(root):
        count += 1
        check_source(path, root, errors)
    check_docs(root, errors)
    if errors:
        print(f"{len(errors)} problem(s) in {count} source files:")
        for e in errors:
            print(f"  {e}")
        return 1
    print(f"ok: {count} source files and all docs pass")
    return 0


if __name__ == "__main__":
    sys.exit(main())
