#!/usr/bin/env python3
"""Render docs/PRD.md into a standalone, print-friendly HTML page.

Deliberately dependency-free: the project has no third-party packages, and a
markdown library would only be needed for a handful of constructs. The subset
supported here is exactly what PRD.md uses - headings, tables, lists, fenced
code, blockquotes, horizontal rules, and inline code/bold/links.

Usage: python3 scripts/prd2html.py [input.md] [output.html]
"""

from __future__ import annotations

import html
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
DEFAULT_IN = ROOT / "docs" / "PRD.md"
DEFAULT_OUT = ROOT / "docs" / "PRD.html"


def slugify(text: str) -> str:
    """Stable anchor from heading text; keeps CJK, drops punctuation."""
    cleaned = re.sub(r"[`*_\[\]()#>]", "", text).strip()
    cleaned = re.sub(r"[^\w\u4e00-\u9fff\- ]", "", cleaned)
    return re.sub(r"\s+", "-", cleaned).lower()


def inline(text: str) -> str:
    """Escape, then apply inline markdown. Code spans are protected first."""
    escapes: list[str] = []

    def stash(match: re.Match[str]) -> str:
        escapes.append(f"<code>{html.escape(match.group(1))}</code>")
        return f"\x00{len(escapes) - 1}\x00"

    text = re.sub(r"`([^`]+)`", stash, text)
    text = html.escape(text, quote=False)
    text = re.sub(r"\*\*([^*]+)\*\*", r"<strong>\1</strong>", text)
    text = re.sub(r"(?<![\w*])\*([^*\n]+)\*(?![\w*])", r"<em>\1</em>", text)
    text = re.sub(
        r"\[([^\]]+)\]\(([^)]+)\)",
        r'<a href="\2">\1</a>',
        text,
    )
    for index, snippet in enumerate(escapes):
        text = text.replace(f"\x00{index}\x00", snippet)
    return text


def split_row(line: str) -> list[str]:
    """Split a table row on unescaped pipes, honouring ``\\|`` inside cells."""
    cells, buffer, escaped = [], [], False
    for char in line.strip().strip("|"):
        if escaped:
            buffer.append(char)
            escaped = False
        elif char == "\\":
            escaped = True
        elif char == "|":
            cells.append("".join(buffer).strip())
            buffer = []
        else:
            buffer.append(char)
    cells.append("".join(buffer).strip())
    return cells


def convert(markdown: str) -> tuple[str, list[tuple[int, str, str]]]:
    lines = markdown.splitlines()
    out: list[str] = []
    toc: list[tuple[int, str, str]] = []
    index = 0
    list_stack: list[str] = []

    def close_lists() -> None:
        while list_stack:
            out.append(f"</{list_stack.pop()}>")

    while index < len(lines):
        line = lines[index]

        # Fenced code
        if line.startswith("```"):
            close_lists()
            language = line[3:].strip()
            index += 1
            block: list[str] = []
            while index < len(lines) and not lines[index].startswith("```"):
                block.append(lines[index])
                index += 1
            index += 1
            cls = f' class="language-{language}"' if language else ""
            out.append(f"<pre><code{cls}>{html.escape(chr(10).join(block))}</code></pre>")
            continue

        stripped = line.strip()

        # Blank line
        if not stripped:
            close_lists()
            index += 1
            continue

        # Horizontal rule
        if re.fullmatch(r"-{3,}", stripped):
            close_lists()
            out.append("<hr>")
            index += 1
            continue

        # Heading
        heading = re.match(r"^(#{1,6})\s+(.*)$", stripped)
        if heading:
            close_lists()
            level = len(heading.group(1))
            text = heading.group(2).strip()
            anchor = slugify(text)
            toc.append((level, text, anchor))
            out.append(f'<h{level} id="{anchor}">{inline(text)}</h{level}>')
            index += 1
            continue

        # Table
        if stripped.startswith("|") and index + 1 < len(lines) and re.match(
            r"^\|[\s:\-|]+\|$", lines[index + 1].strip()
        ):
            close_lists()
            header = split_row(stripped)
            index += 2
            rows: list[list[str]] = []
            while index < len(lines) and lines[index].strip().startswith("|"):
                rows.append(split_row(lines[index]))
                index += 1
            out.append("<table>")
            out.append(
                "<thead><tr>"
                + "".join(f"<th>{inline(cell)}</th>" for cell in header)
                + "</tr></thead>"
            )
            out.append("<tbody>")
            for row in rows:
                out.append(
                    "<tr>" + "".join(f"<td>{inline(cell)}</td>" for cell in row) + "</tr>"
                )
            out.append("</tbody></table>")
            continue

        # Blockquote (consecutive ">" lines merge into one block)
        if stripped.startswith(">"):
            close_lists()
            quote: list[str] = []
            while index < len(lines) and lines[index].strip().startswith(">"):
                quote.append(lines[index].strip()[1:].strip())
                index += 1
            out.append(f"<blockquote>{inline(' '.join(part for part in quote if part))}</blockquote>")
            continue

        # List item (with optional checkbox)
        item = re.match(r"^(\s*)([-*]|\d+\.)\s+(.*)$", line)
        if item:
            indent = len(item.group(1))
            depth = indent // 2
            ordered = item.group(2).endswith(".")
            tag = "ol" if ordered else "ul"
            # An open list at depth d means the stack holds d+1 entries, so
            # pop while the stack is deeper than this item's own level, then
            # switch list type or open a new list as needed.
            while len(list_stack) > depth + 1:
                out.append(f"</{list_stack.pop()}>")
            if list_stack and len(list_stack) == depth + 1 and list_stack[-1] != tag:
                out.append(f"</{list_stack.pop()}>")
            if len(list_stack) == depth:
                out.append(f"<{tag}>")
                list_stack.append(tag)
            content = item.group(3)
            checkbox = re.match(r"^\[( |x|X)\]\s*(.*)$", content)
            if checkbox:
                checked = " checked" if checkbox.group(1).lower() == "x" else ""
                content = (
                    f'<input type="checkbox" disabled{checked}> ' + checkbox.group(2)
                )
            out.append(f"<li>{inline(content)}</li>")
            index += 1
            continue

        # Paragraph
        close_lists()
        out.append(f"<p>{inline(stripped)}</p>")
        index += 1

    close_lists()
    return "\n".join(out), toc


STYLE = """
:root {
  --ink: #1c1c1e;
  --muted: #6b6b70;
  --rule: #e3e3e6;
  --page: #fbfbfa;
  --card: #ffffff;
  --accent: #2f6f4f;
  --code-bg: #f4f4f2;
}
* { box-sizing: border-box; }
html { -webkit-text-size-adjust: 100%; }
body {
  margin: 0;
  background: var(--page);
  color: var(--ink);
  font: 15px/1.75 -apple-system, "SF Pro Text", "PingFang SC", "Helvetica Neue", sans-serif;
}
.layout { display: grid; grid-template-columns: 248px minmax(0, 1fr); gap: 48px;
  max-width: 1180px; margin: 0 auto; padding: 48px 32px 96px; }
nav.toc { position: sticky; top: 32px; align-self: start; max-height: calc(100vh - 64px);
  overflow-y: auto; font-size: 12.5px; line-height: 1.5; }
nav.toc h2 { font-size: 11px; letter-spacing: .09em; text-transform: uppercase;
  color: var(--muted); font-weight: 600; margin: 0 0 12px; }
nav.toc a { display: block; color: var(--muted); text-decoration: none;
  padding: 3px 0 3px 10px; border-left: 2px solid transparent; }
nav.toc a:hover { color: var(--ink); border-left-color: var(--accent); }
nav.toc a.lv1 { color: var(--ink); font-weight: 600; margin-top: 10px; }
nav.toc a.lv3 { padding-left: 22px; font-size: 12px; }
main { background: var(--card); border: 1px solid var(--rule); border-radius: 12px;
  padding: 52px 56px 64px; box-shadow: 0 1px 2px rgba(0,0,0,.03); }
h1 { font-size: 30px; line-height: 1.25; margin: 0 0 8px; letter-spacing: -.01em; }
h2 { font-size: 21px; margin: 44px 0 14px; padding-top: 20px; border-top: 1px solid var(--rule);
  letter-spacing: -.005em; }
h1 + h2 { border-top: 0; padding-top: 0; margin-top: 28px; }
h3 { font-size: 16px; margin: 30px 0 10px; }
h4 { font-size: 14px; margin: 22px 0 8px; color: #333; }
p { margin: 10px 0; }
ul, ol { margin: 10px 0; padding-left: 22px; }
li { margin: 4px 0; }
strong { font-weight: 600; }
a { color: var(--accent); }
hr { border: 0; border-top: 1px solid var(--rule); margin: 34px 0; }
blockquote { margin: 16px 0; padding: 10px 16px; background: #f7f7f4;
  border-left: 3px solid #d8d8d2; color: #4a4a4f; font-size: 14px; }
blockquote p { margin: 0; }
code { font-family: "SF Mono", ui-monospace, Menlo, monospace; font-size: 12.5px;
  background: var(--code-bg); padding: 1px 5px; border-radius: 4px; }
pre { background: var(--code-bg); padding: 16px 18px; border-radius: 8px; overflow-x: auto;
  margin: 14px 0; border: 1px solid #ecece8; }
pre code { background: none; padding: 0; font-size: 12px; line-height: 1.65; }
table { width: 100%; border-collapse: collapse; margin: 16px 0; font-size: 13px; }
th, td { text-align: left; padding: 8px 10px; border-bottom: 1px solid var(--rule);
  vertical-align: top; }
th { background: #fafaf7; font-weight: 600; font-size: 12px; color: #3a3a3d;
  border-bottom: 1px solid #d9d9d4; white-space: nowrap; }
tbody tr:last-child td { border-bottom: 0; }
td code, th code { font-size: 11.5px; }
input[type=checkbox] { margin-right: 4px; }
@media (max-width: 900px) {
  .layout { grid-template-columns: 1fr; padding: 24px 16px 64px; }
  nav.toc { position: static; max-height: none; border-bottom: 1px solid var(--rule); padding-bottom: 16px; }
  main { padding: 28px 20px 40px; }
  table { display: block; overflow-x: auto; }
}
@media print {
  body { background: #fff; font-size: 11pt; }
  .layout { display: block; max-width: none; padding: 0; }
  nav.toc { display: none; }
  main { border: 0; box-shadow: none; padding: 0; border-radius: 0; }
  h2 { break-after: avoid; }
  table, pre, blockquote { break-inside: avoid; }
}
"""


def render(markdown: str, source_name: str) -> str:
    body, toc = convert(markdown)
    entries = "\n".join(
        f'<a class="lv{min(level, 3)}" href="#{anchor}">{inline(text)}</a>'
        for level, text, anchor in toc
        if level <= 3 and level > 1
    )
    return f"""<!DOCTYPE html>
<html lang="zh-CN">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>Quicklet 产品需求文档</title>
<style>{STYLE}</style>
</head>
<body>
<div class="layout">
<nav class="toc">
<h2>目录</h2>
{entries}
</nav>
<main>
{body}
</main>
</div>
</body>
</html>
"""


def main() -> int:
    source = Path(sys.argv[1]) if len(sys.argv) > 1 else DEFAULT_IN
    target = Path(sys.argv[2]) if len(sys.argv) > 2 else DEFAULT_OUT
    markdown = source.read_text(encoding="utf-8")
    target.write_text(render(markdown, source.name), encoding="utf-8")
    print(f"wrote {target} ({target.stat().st_size} bytes)")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
