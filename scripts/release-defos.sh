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
    echo "" >> "$ROLE_META"
    echo "role_version: \"$NEW_VERSION\"" >> "$ROLE_META"
    echo "Appended role_version to $ROLE_META"
  fi
else
  echo "ERROR: $ROLE_META not found; aborting."
  exit 4
fi

# 2) Move Unreleased content into new version header and normalize Unreleased stub using Python
if [ ! -f "$CHANGELOG" ]; then
  echo "ERROR: $CHANGELOG not found; aborting."
  exit 5
fi

python3 - <<PY
import re, sys, datetime, io

changelog_path = "${CHANGELOG}"
ver = "${NEW_VERSION}"
date = "${DATE}"

with open(changelog_path, "r", encoding="utf-8") as f:
    text = f.read()

# Ensure file has a top-level header; if not, add a basic header
if not re.search(r"(?m)^# Changelog", text):
    text = "# Changelog\n\n" + text

# Locate the '## [Unreleased]' header (exact match)
m_unrel = re.search(r"(?m)^## \[Unreleased\].*$", text)
if not m_unrel:
    # Prepend an Unreleased header if missing
    text = "## [Unreleased]\n\n### Added\n- N/A\n\n" + text
    m_unrel = re.search(r"(?m)^## \[Unreleased\].*$", text)

start = m_unrel.end()  # start index right after the 'Unreleased' header line

# find next version header "## [" after start
m_next = re.search(r"(?m)^## \[", text[start:])
if m_next:
    end = start + m_next.start()
else:
    end = len(text)

# Extract the unreleased content (slice between header line end and next header start)
unreleased_raw = text[start:end]

# Normalize preserved unreleased content by trimming leading/trailing whitespace
unreleased_stripped = unreleased_raw.strip("\n")

# Build new version block from the unreleased content (if any)
if unreleased_stripped:
    # Keep content as-is but ensure it doesn't start or end with extra blank lines
    moved_content = unreleased_stripped
else:
    moved_content = "- N/A"

new_version_block = "\n\n## [{}] - {}\n{}\n".format(ver, date, moved_content)

# Construct a normalized Unreleased stub:
# If the original Unreleased had no non-whitespace content, create a clean stub.
# If it had content that we moved, create an empty, normalized Unreleased stub ready for future entries.
unreleased_stub = "## [Unreleased]\n\n### Added\n- N/A\n\n"

# Build new text:
pre = text[:m_unrel.start()]  # everything before the Unreleased header
post = text[end:]             # everything after the moved block (the remainder of changelog)

# Compose: pre + unreleased_stub + new_version_block + post
new_text = pre + unreleased_stub + new_version_block + post

# Clean up multiple blank lines (collapse 3+ newlines into two), but preserve paragraph spacing
new_text = re.sub(r'\n{3,}', '\n\n', new_text)

# Trim trailing whitespace at EOF to single newline
new_text = new_text.rstrip() + "\n"

with open(changelog_path, "w", encoding="utf-8") as f:
    f.write(new_text)

print("Changelog updated: moved Unreleased content (if any) into new version header and normalized Unreleased stub.", file=sys.stderr)
PY

# 3) Git add, commit, tag, push
git add "$ROLE_META" "$CHANGELOG"
if git diff --staged --quiet; then
  echo "No staged changes to commit."
else
  git commit -m "chore(defos): release $NEW_VERSION (update role_version and changelog)"
fi

git tag -a "$TAG" -m "Release $NEW_VERSION"
git push origin "$BRANCH"
git push origin "$TAG"

echo "Done. Tagged $TAG and pushed branch + tag. The GitHub action will create a Release from the tag."
