#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
Usage:
  scripts/release.sh <version> -m "<message>" [--push]

Example:
  scripts/release.sh 1.1.7 -m "- fix: list scrolling\n- feat: media controls" --push

The script reads the current pubspec build number, increments it by one,
commits the pubspec bump and documentation footprint, creates an annotated tag
v<version>, and optionally pushes main plus the tag to origin.
EOF
}

if [[ $# -lt 3 ]]; then
  usage
  exit 1
fi

version="$1"
shift

message=""
push_remote=false

while [[ $# -gt 0 ]]; do
  case "$1" in
    -m|--message)
      message="$2"
      shift 2
      ;;
    --push)
      push_remote=true
      shift
      ;;
    *)
      echo "Unknown argument: $1" >&2
      usage
      exit 1
      ;;
  esac
done

if [[ -z "$message" ]]; then
  echo "Error: -m <message> is required. Please provide a brief bullet list of changes." >&2
  exit 1
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

cat <<EOF >> AGENT_HANDOFF.md

---
*🤖 Automated Release Footprint:* 
*执行指令: \`./scripts/release.sh $version -m "$message"$( [[ "$push_remote" == true ]] && echo " --push" )\`*
EOF

git add pubspec.yaml AGENT_HANDOFF.md
git commit -m "chore: bump version to $version+$next_build"
git tag -a "$tag" -m "$message"

echo "Created $tag with pubspec version $version+$next_build."

if [[ "$push_remote" == true ]]; then
  git push origin main
  git push origin "$tag"
else
  echo "Next steps:"
  echo "  git push origin main"
  echo "  git push origin $tag"
fi
