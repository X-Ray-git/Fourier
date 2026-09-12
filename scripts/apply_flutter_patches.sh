#!/usr/bin/env bash
set -euo pipefail

expected_revision="4cf24164269a5ebf0c16a028a00727d0e77bbb05"
patch_path="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/tool/flutter_patches/3.47.0-selection.patch"

flutter_root="${FLUTTER_ROOT:-}"
if [[ -z "$flutter_root" ]]; then
  flutter_bin="$(command -v flutter || true)"
  if [[ -z "$flutter_bin" ]]; then
    echo "Flutter executable was not found." >&2
    exit 1
  fi
  while [[ -L "$flutter_bin" ]]; do
    link_target="$(readlink "$flutter_bin")"
    if [[ "$link_target" == /* ]]; then
      flutter_bin="$link_target"
    else
      flutter_bin="$(cd "$(dirname "$flutter_bin")" && pwd)/$link_target"
    fi
  done
  flutter_root="$(cd "$(dirname "$flutter_bin")/.." && pwd)"
fi

actual_revision="$(git -C "$flutter_root" rev-parse HEAD)"
if [[ "$actual_revision" != "$expected_revision" ]]; then
  echo "Flutter revision mismatch." >&2
  echo "Expected: $expected_revision" >&2
  echo "Actual:   $actual_revision" >&2
  exit 1
fi

if git -C "$flutter_root" apply --check "$patch_path" 2>/dev/null; then
  git -C "$flutter_root" apply "$patch_path"
  echo "Applied Fourier Flutter selection patch."
elif git -C "$flutter_root" apply --reverse --check "$patch_path" 2>/dev/null; then
  echo "Fourier Flutter selection patch is already applied."
elif grep -q "super.rawText" \
    "$flutter_root/packages/flutter/lib/src/widgets/widget_span.dart" && \
  grep -q "boxHeightStyle: ui.BoxHeightStyle.max" \
    "$flutter_root/packages/flutter/lib/src/rendering/paragraph.dart"; then
  echo "Flutter SDK already contains compatible selection support."
else
  echo "Flutter selection patch cannot be applied cleanly." >&2
  echo "Restore a clean Flutter 3.47.0 SDK before retrying." >&2
  exit 1
fi
