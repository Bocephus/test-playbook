#!/usr/bin/env bash
set -euo pipefail

# Usage: ./scripts/release-defos.sh 1.4.0
ROLE_META="roles/defos/meta/main.yml"
CHANGELOG="roles/defos/CHANGELOG.md"

if [ $# -ne 1 ]; then
  echo "Usage: $0 <new-version>   (example: $0 1.4.0)"
  exit 2
fi

NEW_VERSION="$1"
if ! [[ "$NEW_VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
  echo "Version must be semantic (X.Y.Z). Got: $NEW_VERSION"
  exit 3
fi

DATE="$(date -u +%Y-%m-%d)"
TAG="v$NEW_VERSION"
BRANCH="$(git rev-parse --abbrev-ref HEAD || echo "unknown")"

echo "Releasing $NEW_VERSION on branch $BRANCH"

# 1) Update role_version in meta/main.yml (replace or append)
if [ -f "$ROLE_META" ]; then
  if grep -q '^[[:space:]]*role_version:' "$ROLE_META"; then
    # replace existing line (portable)
    awk -v ver="$NEW_VERSION" '
      BEGIN{replaced=0}
      /^[[:space:]]*role_version:/ {
        print "role_version: \"" ver "\""
        replaced=1
        next
      }
      { print }
      END { if(!replaced) { print ""; print "role_version: \"" ver "\""} }
    ' "$ROLE_META" > "${ROLE_META}.tmp" && mv "${ROLE_META}.tmp" "$ROLE_META"
    echo "Updated existing role_version in $ROLE_META"
  else
    # append at end
    echo "" >> "$ROLE_META"
    echo "role_version: \"$NEW_VERSION\"" >> "$ROLE_META"
    echo "Appended role_version to $ROLE_META"
  fi
else
  echo "ERROR: $ROLE_META not found; aborting."
  exit 4
fi

# 2) Move Unreleased content into new version header using Python for correctness
if [ ! -f "$CHANGELOG" ]; then
  echo "ERROR: $CHANGELOG not found; aborting."
  exit 5
fi

python3 - <<PY
import re, sys, datetime
changelog_path = "${CHANGELOG}"
ver = "${NEW_VERSION}"
date = "${DATE}"

with open(changelog_path, "r", encoding="utf-8") as f:
    text = f.read()

# Patterns (multiline aware)
unreleased_header_pattern = re.compile(r"(^## \[Unreleased\].*?$)", re.MULTILINE)
next_header_pattern = re.compile(r"^## \[", re.MULTILINE)

m = unreleased_header_pattern.search(text)
if not m:
    # If no Unreleased header, create one at top and proceed.
    print("No '## [Unreleased]' header found. Prepending one.", file=sys.stderr)
    text = "## [Unreleased]\n\n" + text
    m = unreleased_header_pattern.search(text)

start = m.end()  # start of content after '## [Unreleased]' line

# find next '## [' header after start
next_m = next_header_pattern.search(text, start)
if next_m:
    end = next_m.start()
else:
    end = len(text)

unreleased_content = text[start:end].rstrip("\n")
# Trim leading/trailing blank lines
unreleased_content = unreleased_content.strip("\n")

# Build new version block
if unreleased_content:
    new_block = "\n\n## [{}] - {}\n{}\n".format(ver, date, unreleased_content)
else:
    new_block = "\n\n## [{}] - {}\n\n- N/A\n".format(ver, date)

# Now construct new text:
# Keep everything up to end of unreleased header, then append the new_block,
# then append remainder starting at 'end'
new_text = text[:start].rstrip() + "\n" + new_block + "\n" + text[end:].lstrip()

# After moving content, ensure Unreleased section does not still contain moved content.
# Clean up: collapse multiple blank lines to two, keep formatting tidy
new_text = re.sub(r'\n{3,}', '\n\n', new_text)

with open(changelog_path, "w", encoding="utf-8") as f:
    f.write(new_text)

print("Changelog updated: moved Unreleased content (if any) into new version header.", file=sys.stderr)
PY

# 3) Git add, commit, tag, push
git add "$ROLE_META" "$CHANGELOG"
if git diff --staged --quiet; then
  echo "No staged changes (nothing to commit)."
else
  git commit -m "chore(defos): release $NEW_VERSION (update role_version and changelog)"
fi

git tag -a "$TAG" -m "Release $NEW_VERSION"
git push origin "$BRANCH"
git push origin "$TAG"

echo "Done. Tagged $TAG and pushed branch + tag. The GitHub action will create a Release from the tag."
