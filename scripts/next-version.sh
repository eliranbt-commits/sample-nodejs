#!/usr/bin/env bash
# Print the next semver for CURRENT given bump: patch|minor|major
set -euo pipefail

current="${1:?usage: next-version.sh <x.y.z> [patch|minor|major]}"
bump="${2:-patch}"

case $current in
  *[!0-9.]*|'')
    echo "invalid version: $current" >&2
    exit 1
    ;;
  *.*.*.*|*.*.*.*.*)
    echo "invalid version: $current" >&2
    exit 1
    ;;
  *.*.*)
    ;;
  *)
    echo "invalid version: $current" >&2
    exit 1
    ;;
esac

major=${current%%.*}
rest=${current#*.}
minor=${rest%%.*}
patch=${rest#*.}

case $major$minor$patch in
  *[!0-9]*|'')
    echo "invalid version: $current" >&2
    exit 1
    ;;
esac

case $bump in
  major)
    major=$((major + 1))
    minor=0
    patch=0
    ;;
  minor)
    minor=$((minor + 1))
    patch=0
    ;;
  patch)
    patch=$((patch + 1))
    ;;
  *)
    echo "invalid bump: $bump" >&2
    exit 1
    ;;
esac

printf '%s.%s.%s\n' "$major" "$minor" "$patch"
