#!/bin/bash
# Download and update-check counts from GitHub, per release. No sign-in needed
# for a public repo; set GITHUB_TOKEN to raise the rate limit.
#
#   scripts/stats.sh                 # notthamer/shut
#   scripts/stats.sh owner/repo
#
# What the numbers mean:
#   .dmg          people who downloaded that version from the site or the release page
#   appcast.xml   update checks by installed copies (Sparkle fetches it about once a day
#                 per Mac, so checks per day is roughly the number of active installs)
set -euo pipefail
REPO="${1:-notthamer/shut}"
AUTH_HEADER="Accept: application/vnd.github+json"
if [ -n "${GITHUB_TOKEN:-}" ]; then
  JSON=$(curl -sf -H "$AUTH_HEADER" -H "Authorization: Bearer $GITHUB_TOKEN" "https://api.github.com/repos/$REPO/releases?per_page=20")
else
  JSON=$(curl -sf -H "$AUTH_HEADER" "https://api.github.com/repos/$REPO/releases?per_page=20")
fi
RELEASES_JSON="$JSON" python3 - <<'PY'
import os, sys, json, datetime
rel = json.loads(os.environ["RELEASES_JSON"])
if not rel:
    print("no releases yet"); sys.exit()
total = 0
for r in rel:
    day = r["published_at"][:10]
    age = (datetime.date.today() - datetime.date.fromisoformat(day)).days or 1
    print(f'{r["tag_name"]}  ({day}, {age} d ago)')
    for a in r["assets"]:
        n, c = a["name"], a["download_count"]
        if n.endswith(".dmg"):
            total += c; print(f"   {c:7d}  {n}")
        elif n == "appcast.xml":
            print(f"   {c:7d}  {n}   (~{c/age:.0f} update checks/day)")
print(f"\nDMG downloads, all versions: {total}")
PY
