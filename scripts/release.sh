#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
Usage:
  scripts/release.sh <version> (-m "<message>" | --notes-file <path>) [--push]
    [--allow-literal-backslash-n] [--allow-unstructured-notes]

Example:
  scripts/release.sh 1.2.3 --notes-file /tmp/v1.2.3-notes.md --push

Release notes normally need these sections:
  ## 本版重点
  At least one content section, such as ## 新功能 or ## 修复与改进
  **完整变更**

For an intentionally different format, pass --allow-unstructured-notes.

If the release notes intentionally need to contain the literal characters \n,
pass --allow-literal-backslash-n. Otherwise literal \n is treated as a likely
quoting mistake and the script exits before creating commits or tags.

With --push, the script first pushes the clean candidate commit and waits for
the GitHub Release Preflight workflow to pass against the pinned official
Flutter SDK. It then reads the current pubspec build number, increments it by
one, commits the pubspec bump and documentation footprint, creates an annotated
tag v<version>, and pushes main plus the tag to origin. Releases must be created
from the main branch.
EOF
}

if [[ $# -lt 3 ]]; then
  usage
  exit 1
fi

version="$1"
shift

message=""
notes_file=""
push_remote=false
allow_literal_backslash_n=false
allow_unstructured_notes=false

while [[ $# -gt 0 ]]; do
  case "$1" in
    -m|--message)
      message="$2"
      shift 2
      ;;
    --notes-file)
      notes_file="$2"
      shift 2
      ;;
    --allow-literal-backslash-n)
      allow_literal_backslash_n=true
      shift
      ;;
    --allow-unstructured-notes)
      allow_unstructured_notes=true
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

if [[ -n "$message" && -n "$notes_file" ]]; then
  echo "Error: use either -m or --notes-file, not both." >&2
  exit 1
fi

if [[ -n "$notes_file" ]]; then
  if [[ ! -f "$notes_file" ]]; then
    echo "Release notes file does not exist: $notes_file" >&2
    exit 1
  fi
  message="$(<"$notes_file")"
fi

if [[ -z "$message" ]]; then
  echo "Error: provide release notes with -m or --notes-file." >&2
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

if [[ "$allow_unstructured_notes" != true ]]; then
  has_content_section=false
  for heading in \
    "## 重要变更" \
    "## 新功能" \
    "## 修复与改进" \
    "## 性能改进" \
    "## 升级说明"; do
    if [[ "$message" == *"$heading"* ]]; then
      has_content_section=true
      break
    fi
  done

  if [[ "$message" != *"## 本版重点"* || \
        "$has_content_section" != true || \
        "$message" != *"**完整变更**"* ]]; then
    cat >&2 <<'EOF'
Error: release notes do not use the standard structure.

Expected:
  ## 本版重点
  At least one of: ## 重要变更 / ## 新功能 / ## 修复与改进 /
                   ## 性能改进 / ## 升级说明
  **完整变更**

Use --allow-unstructured-notes only when a release intentionally needs a
different public format.
EOF
    exit 1
  fi
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

if [[ "$push_remote" == true ]]; then
  if ! command -v gh >/dev/null 2>&1; then
    echo "GitHub CLI is required for the release preflight." >&2
    exit 1
  fi
  if ! gh auth status >/dev/null 2>&1; then
    echo "GitHub CLI is not authenticated. Run gh auth login first." >&2
    exit 1
  fi

  source_sha="$(git rev-parse HEAD)"
  echo "Pushing release candidate $source_sha for clean-SDK preflight..."
  git push origin main

  previous_run_id="$(
    gh run list \
      --workflow release-preflight.yml \
      --event workflow_dispatch \
      --branch main \
      --limit 1 \
      --json databaseId \
      --jq '.[0].databaseId // 0'
  )"
  gh workflow run release-preflight.yml \
    --ref main \
    -f "commit_sha=$source_sha"

  preflight_run_id=""
  for _ in {1..30}; do
    preflight_run_id="$(
      gh run list \
        --workflow release-preflight.yml \
        --event workflow_dispatch \
        --branch main \
        --limit 20 \
        --json databaseId,headSha \
        --jq ".[] | select(.headSha == \"$source_sha\" and .databaseId > $previous_run_id) | .databaseId" \
        | head -n 1
    )"
    [[ -n "$preflight_run_id" ]] && break
    sleep 2
  done

  if [[ -z "$preflight_run_id" ]]; then
    echo "Could not locate the dispatched release preflight run." >&2
    exit 1
  fi

  echo "Waiting for release preflight run $preflight_run_id..."
  preflight_completed=false
  for _ in {1..180}; do
    if preflight_state="$(
      gh run view "$preflight_run_id" \
        --json status,conclusion \
        --jq '[.status, (.conclusion // "")] | @tsv'
    )"; then
      IFS=$'\t' read -r run_status run_conclusion <<<"$preflight_state"
      if [[ "$run_status" == "completed" ]]; then
        if [[ "$run_conclusion" != "success" ]]; then
          echo "Release preflight failed with conclusion: $run_conclusion" >&2
          echo "Inspect it with: gh run view $preflight_run_id --log-failed" >&2
          exit 1
        fi
        preflight_completed=true
        break
      fi
    else
      echo "GitHub status check failed temporarily; retrying..." >&2
    fi
    sleep 10
  done

  if [[ "$preflight_completed" != true ]]; then
    echo "Timed out waiting for release preflight run $preflight_run_id." >&2
    exit 1
  fi
fi

perl -0pi -e "s/^version:\\s*\\d+\\.\\d+\\.\\d+\\+\\d+$/version: $version+$next_build/m" pubspec.yaml

release_history="docs/agent_handoff/history/releases.html"
# macOS ships an older Bash whose printf %q can split UTF-8 code points under
# some locales. Python's shell quoting keeps release history valid and remains
# readable when notes contain Chinese or real newlines.
message_arg="$(printf '%s' "$message" | python3 -c '
import shlex
import sys
sys.stdout.write(shlex.quote(sys.stdin.read()))
')"
release_flags=""
if [[ "$allow_literal_backslash_n" == true ]]; then
  release_flags+=" --allow-literal-backslash-n"
fi
if [[ "$allow_unstructured_notes" == true ]]; then
  release_flags+=" --allow-unstructured-notes"
fi
if [[ "$push_remote" == true ]]; then
  release_flags+=" --push"
fi
{
  printf '\n## %s\n\n```bash\n' "$tag"
  printf './scripts/release.sh %s -m %s%s\n' "$version" "$message_arg" "$release_flags"
  printf '```\n'
} | python3 -c '
import os
import sys
frag = sys.stdin.read().replace("</script>", "<\\\\/script>")
path = sys.argv[1]
src = open(path, encoding="utf-8").read()
marker = "</script>"
idx = src.find(marker)
assert idx != -1 and "id=\"wiki-content\"" in src[:idx], "releases.html wiki-content block not found"
payload = (src[:idx] + frag + src[idx:]).encode("utf-8")
tmp = path + ".tmp"
with open(tmp, "wb") as handle:
    handle.write(payload)
os.replace(tmp, path)
' "$release_history"

./scripts/docs.sh index
./scripts/docs.sh check

git add pubspec.yaml "$release_history" docs/agent_handoff/assets/data/search-index.js
git commit -m "chore: bump version to $version+$next_build"
git tag -a "$tag" --cleanup=verbatim -m "$message"

echo "Created $tag with pubspec version $version+$next_build."

if [[ "$push_remote" == true ]]; then
  git push origin main
  git push origin "$tag"
else
  echo "Next steps:"
  echo "  git push origin main"
  echo "  git push origin $tag"
fi
