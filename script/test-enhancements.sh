#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/gpt-niang-core.XXXXXX")"
trap 'rm -rf "$TMP"' EXIT
mkdir -p "$ROOT/macos/.build-cache/clang"
export CLANG_MODULE_CACHE_PATH="$ROOT/macos/.build-cache/clang"
SDK="${GPT_NIANG_SDK:-$(xcrun --sdk macosx --show-sdk-path)}"
swiftc -sdk "$SDK" \
  "$ROOT/macos/Sources/GPTNiangCore/Placement.swift" \
  "$ROOT/macos/Sources/GPTNiangCore/PetEnhancements.swift" \
  "$ROOT/macos/Sources/GPTNiangCore/PetInteraction.swift" \
  "$ROOT/macos/Sources/GPTNiangCore/PetRigMotion.swift" \
  "$ROOT/script/EnhancementChecks.swift" -o "$TMP/checks"
"$TMP/checks"
