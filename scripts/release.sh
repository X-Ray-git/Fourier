#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
Usage:
  scripts/release.sh <version> [--push]

Example:
  scripts/release.sh 1.1.7 --push

The script reads the current pubspec build number, increments it by one,
commits the pubspec bump, creates tag v<version>, and optionally pushes
main plus the tag to origin.
EOF
}

if [[ $# -lt 1 || $# -gt 2 ]]; then
  usage
  exit 1
fi

version="$1"
push_remote=false
if [[ $# -eq 2 ]]; then
  if [[ "$2" != "--push" ]]; then
    usage
    exit 1
  fi
  push_remote=true
fi

if [[ ! "$version" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
  echo "Version must look like 1.2.3, got: $version" >&2
  exit 1
fi

if [[ -n "$(git status --short)" ]]; then
  echo "Working tree is not clean. Commit or stash changes before releasing." >&2
  exit 1
fi

current_line="$(grep -E '^version:[[:space:]]*[0-9]+\.[0-9]+\.[0-9]+\+[0-9]+$' pubspec.yaml || true)"
if [[ -z "$current_line" ]]; then
  echo "Could not parse pubspec.yaml version line." >&2
  exit 1
fi

current_build="${current_line##*+}"
next_build=$((current_build + 1))
tag="v$version"

if git rev-parse "$tag" >/dev/null 2>&1; then
  echo "Tag already exists locally: $tag" >&2
  exit 1
fi

if git ls-remote --exit-code --tags origin "refs/tags/$tag" >/dev/null 2>&1; then
  echo "Tag already exists on origin: $tag" >&2
  exit 1
fi

perl -0pi -e "s/^version:\\s*\\d+\\.\\d+\\.\\d+\\+\\d+$/version: $version+$next_build/m" pubspec.yaml

git add pubspec.yaml
git commit -m "chore: bump version to $version+$next_build"
git tag "$tag"

echo "Created $tag with pubspec version $version+$next_build."

if [[ "$push_remote" == true ]]; then
  git push origin main
  git push origin "$tag"
else
  echo "Next steps:"
  echo "  git push origin main"
  echo "  git push origin $tag"
fi
