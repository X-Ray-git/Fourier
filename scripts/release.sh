#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
Usage:
  scripts/release.sh <version> -m "<message>" [--push] [--allow-literal-backslash-n]

Example:
  scripts/release.sh 1.1.7 -m $'- fix: list scrolling\n- feat: media controls' --push

If the release notes intentionally need to contain the literal characters \n,
pass --allow-literal-backslash-n. Otherwise literal \n is treated as a likely
quoting mistake and the script exits before creating commits or tags.

The script reads the current pubspec build number, increments it by one,
commits the pubspec bump and documentation footprint, creates an annotated tag
v<version>, and optionally pushes main plus the tag to origin. Releases must be
created from the main branch.
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
allow_literal_backslash_n=false

while [[ $# -gt 0 ]]; do
  case "$1" in
    -m|--message)
      message="$2"
      shift 2
      ;;
    --allow-literal-backslash-n)
      allow_literal_backslash_n=true
      shift
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

literal_backslash_n='\n'
if [[ "$allow_literal_backslash_n" != true && "$message" == *"$literal_backslash_n"* ]]; then
  cat >&2 <<'EOF'
Error: release notes contain the literal characters \n.

Use a real newline instead, for example:
  scripts/release.sh 1.2.3 -m $'- fix: first item\n- feat: second item' --push

If you intentionally want the release notes to display the literal characters \n,
rerun with --allow-literal-backslash-n.
EOF
  exit 1
fi

if [[ ! "$version" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
  echo "Version must look like 1.2.3, got: $version" >&2
  exit 1
fi

current_branch="$(git branch --show-current)"
if [[ "$current_branch" != "main" ]]; then
  echo "Releases must be created from main, current branch: ${current_branch:-detached HEAD}" >&2
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

release_history="docs/agent_handoff/history/releases.html"
printf -v message_arg '%q' "$message"
release_flags=""
if [[ "$allow_literal_backslash_n" == true ]]; then
  release_flags+=" --allow-literal-backslash-n"
fi
if [[ "$push_remote" == true ]]; then
  release_flags+=" --push"
fi
{
  printf '\n## %s\n\n```bash\n' "$tag"
  printf './scripts/release.sh %s -m %s%s\n' "$version" "$message_arg" "$release_flags"
  printf '```\n'
} | python3 -c '
import sys
frag = sys.stdin.read().replace("</script>", "<\\\\/script>")
path = sys.argv[1]
src = open(path, encoding="utf-8").read()
marker = "</script>"
idx = src.find(marker)
assert idx != -1 and "id=\"wiki-content\"" in src[:idx], "releases.html wiki-content block not found"
open(path, "w", encoding="utf-8").write(src[:idx] + frag + src[idx:])
' "$release_history"

git add pubspec.yaml "$release_history"
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
