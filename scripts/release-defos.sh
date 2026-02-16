#!/usr/bin/env bash
set -euo pipefail

# Usage: ./scripts/release-defos.sh 1.4.0
# This script:
# - validates the provided semver
# - updates roles/defos/meta/main.yml role_version (adds line if missing)
# - moves the content from "## [Unreleased]" into a new version header "## [X.Y.Z] - YYYY-MM-DD"
# - leaves the "## [Unreleased]" header in place (so you can keep adding to it)
# - commits, tags, and pushes

ROLE_META="roles/defos/meta/main.yml"
CHANGELOG="roles/defos/CHANGELOG.md"
BRANCH="$(git rev-parse --abbrev-ref HEAD || echo "")"

if [ $# -ne 1 ]; then
  echo "Usage: $0 <new-version>   (example: $0 1.4.0)"
  exit 2
fi

NEW_VERSION="$1"
# simple semver check (major.minor.patch)
if ! [[ "$NEW_VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
  echo "Version must be semantic (X.Y.Z). Got: $NEW_VERSION"
  exit 3
fi

DATE="$(date -u +%Y-%m-%d)"
TAG="v$NEW_VERSION"

echo "Releasing $NEW_VERSION (tag $TAG) on branch ${BRANCH:-unknown}"

# 1) Update role_version in meta/main.yml (if exists, replace; if not, append)
if [ -f "$ROLE_META" ]; then
  if grep -q '^[[:space:]]*role_version:' "$ROLE_META"; then
    # replace existing line (preserve indentation)
    sed -E -i.bak "s/^[[:space:]]*role_version:.*/role_version: \"${NEW_VERSION}\"/" "$ROLE_META"
    rm -f "${ROLE_META}.bak"
    echo "Updated role_version in $ROLE_META"
  else
    # append role_version at end of file
    echo "" >> "$ROLE_META"
    echo "role_version: \"${NEW_VERSION}\"" >> "$ROLE_META"
    echo "Appended role_version to $ROLE_META"
  fi
else
  echo "ERROR: $ROLE_META not found"
  exit 4
fi

# 2) Extract Unreleased block
if [ ! -f "$CHANGELOG" ]; then
  echo "ERROR: CHANGELOG not found at $CHANGELOG"
  exit 5
fi

# Read the content under "## [Unreleased]" until next "## [" (or EOF)
UNRELEASED_CONTENT="$(awk '
  BEGIN{in_un=0}
  /^## \[Unreleased\]/{in_un=1; next}
  /^## \[/{ if(in_un) exit }
  { if(in_un) print }
' "$CHANGELOG")"

if [ -z "$(echo "$UNRELEASED_CONTENT" | sed -e '/^\s*$/d')" ]; then
  echo "WARNING: No content under 'Unreleased' — nothing to move. Will still create a release header with an empty body."
fi

# 3) Insert new version header + the unreleased content right AFTER the '## [Unreleased]' header
# We'll rebuild the changelog: print lines up to header, print header, then the new version header and its content, then the remainder.

awk -v ver="$NEW_VERSION" -v date="$DATE" -v mapfile="/dev/stdout" '
  BEGIN{in_un=0; printed_new=0}
  {
    if($0=="## [Unreleased]") {
      print $0
      in_un=1
      next
    }
    if(in_un && $0 ~ /^## \[/ && printed_new==0) {
      # we reached the next section after Unreleased -> insert new version header here
      print ""
      print "## [" ver "] - " date
      printed_new=1
    }
    if(in_un){
      # buffer unreleased lines to print under the new header later,
      # but since we are inserting the header immediately before the next section,
      # we need to print the buffered lines now. Simpler approach: print lines as we go.
      # print the line (belongs to the unreleased content)
      print $0
      next
    }
    print $0
  }
  END{
    if(in_un && printed_new==0){
      # file ended while still in unreleased section -> append new version header and the buffered content (already printed).
      print ""
      print "## " ver " - " date
    }
  }
' "$CHANGELOG" > "$CHANGELOG.tmp" && mv "$CHANGELOG.tmp" "$CHANGELOG"

echo "Inserted new version header ## [$NEW_VERSION] - $DATE into $CHANGELOG (content from Unreleased preserved)."

# 4) Commit changes
git add "$ROLE_META" "$CHANGELOG"
git commit -m "chore(defos): release $NEW_VERSION (update role_version and changelog)" || {
  echo "No changes to commit (did meta/main.yml or CHANGELOG actually change?)"
}

# 5) Tag and push
git tag -a "$TAG" -m "Release $NEW_VERSION"
git push origin "$BRANCH"
git push origin "$TAG"

echo "Released $NEW_VERSION — tag $TAG pushed. CI (release workflow) should create a GitHub Release automatically."
