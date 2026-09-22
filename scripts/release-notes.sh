#!/bin/bash
# Prints one version's section of CHANGELOG.md: the single source for the GitHub release
# notes, the notes in Sparkle's update window, and the "What's new" card in the app.
#
#   scripts/release-notes.sh            # this version (App/Info.plist), as Markdown
#   scripts/release-notes.sh 0.3.0      # that version
#   scripts/release-notes.sh 0.3.0 --html   # as a small HTML page, for Sparkle
set -euo pipefail
cd "$(dirname "$0")/.."
VERSION="${1:-$(scripts/version.sh)}"
FORMAT="${2:-}"
NOTES=$(awk -v v="$VERSION" '$0 ~ "^## " { on = ($2 == v); next } on { print }' CHANGELOG.md)
[ -n "$(echo "$NOTES" | tr -d '[:space:]')" ] || NOTES="Shut $VERSION"
if [ "$FORMAT" != "--html" ]; then echo "$NOTES"; exit 0; fi
# Only the Markdown this changelog uses: **bold**, `code`, "- " lists, paragraphs.
NOTES="$NOTES" python3 - <<'PY'
import html, os, re
def inline(text):
    text = html.escape(text, quote=False)
    text = re.sub(r"\*\*(.+?)\*\*", r"<b>\1</b>", text)
    return re.sub(r"`(.+?)`", r"<code>\1</code>", text)
out, in_list = [], False
for line in os.environ["NOTES"].splitlines():
    if line.startswith("- "):
        if not in_list: out.append("<ul>"); in_list = True
        out.append("<li>" + inline(line[2:]) + "</li>")
        continue
    if in_list: out.append("</ul>"); in_list = False
    if line.strip(): out.append("<p>" + inline(line) + "</p>")
if in_list: out.append("</ul>")
print('<html><head><meta charset="utf-8"><style>body{font:13px -apple-system,sans-serif;line-height:1.45;margin:14px}'
      'li{margin-bottom:6px}code{font:12px ui-monospace,monospace}</style></head><body>' + "\n".join(out) + "</body></html>")
PY
