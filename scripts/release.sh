#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
Usage:
  scripts/release.sh <version> (-m "<message>" | --notes-file <path>) [--push] [--candidate <full-sha>]
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

With --push, pushes main and dispatches the complete cloud Publish Release
workflow, then returns immediately. Cloud preflight, version/tag preparation,
builds and Release publication no longer depend on a local background process.
Use --candidate <full-sha> only to recover a historical main release candidate.
Without --push this command is a dry-run; it never creates local release tags.
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
candidate=""
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
    --candidate)
      candidate="$2"
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


candidate="${candidate:-$(git rev-parse HEAD)}"
if [[ ! "$candidate" =~ ^[0-9a-f]{40}$ ]]; then
  echo "Candidate must be a full commit SHA." >&2
  exit 1
fi
git merge-base --is-ancestor "$candidate" main
if [[ "$push_remote" != true ]]; then
  echo "Dry run: publish v$version from $candidate. Add --push to dispatch the complete cloud release."
  exit 0
fi
if [[ "$allow_literal_backslash_n" == true || "$allow_unstructured_notes" == true ]]; then
  echo "Cloud releases require standard notes; exception flags are only supported for local validation." >&2
  exit 1
fi
command -v gh >/dev/null
gh auth status >/dev/null 2>&1
git push origin main
payload="$(mktemp)"
trap 'rm -f "$payload"' EXIT
export FOURIER_RELEASE_VERSION="$version" FOURIER_RELEASE_CANDIDATE="$candidate" FOURIER_RELEASE_NOTES="$message"
python3 - <<'PY_PAYLOAD' > "$payload"
import json, os
print(json.dumps({'ref':'main', 'inputs': {
  'version':os.environ['FOURIER_RELEASE_VERSION'],
  'candidate_sha':os.environ['FOURIER_RELEASE_CANDIDATE'],
  'notes':os.environ['FOURIER_RELEASE_NOTES'],
}}))
PY_PAYLOAD
repo="$(gh repo view --json nameWithOwner --jq .nameWithOwner)"
gh api --method POST "repos/$repo/actions/workflows/publish-release.yml/dispatches" --input "$payload"
echo "Complete cloud release accepted: v$version from $candidate"
echo "https://github.com/$repo/actions/workflows/publish-release.yml"
echo "This confirms dispatch, not release completion. No local process needs to remain running."
