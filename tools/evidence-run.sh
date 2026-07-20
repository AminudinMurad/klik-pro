#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SDK="${KLIK_PRO_SDK_PATH:-$(xcrun --sdk macosx --show-sdk-path)}"
ARCH="$(uname -m)"

usage() {
  cat <<'USAGE' >&2
Usage:
  tools/evidence-run.sh inspect --app /Applications/App.app --workspace /tmp/ws
  tools/evidence-run.sh create --app /Applications/App.app --workspace /tmp/ws
  tools/evidence-run.sh launch --workspace /tmp/ws
  tools/evidence-run.sh attest --workspace /tmp/ws --phase relaunch --login-persisted yes|no
  tools/evidence-run.sh attest --workspace /tmp/ws --phase post-update --login-persisted yes|no --primary-untouched yes|no
  tools/evidence-run.sh report --workspace /tmp/ws
USAGE
}

workspace=""
args=("$@")
for ((i = 0; i < ${#args[@]}; i++)); do
  if [[ "${args[$i]}" == "--workspace" ]]; then
    if (( i + 1 >= ${#args[@]} )); then
      usage
      exit 2
    fi
    workspace="${args[$((i + 1))]}"
  fi
done

if [[ -z "$workspace" ]]; then
  echo "ERROR: --workspace is required" >&2
  usage
  exit 2
fi

workspace="$(python3 -c 'import os,sys; print(os.path.realpath(os.path.expanduser(sys.argv[1])))' "$workspace")"
live_support="$(python3 -c 'import os; print(os.path.realpath(os.path.expanduser("~/Library/Application Support/Klik PRO")))' )"

case "$workspace" in
  "$live_support"|"$live_support"/*)
    echo "ERROR: evidence workspace must not be inside live Klik PRO Application Support" >&2
    exit 2
    ;;
esac

mkdir -p "$workspace/.build" "$workspace/module-cache"

DUPLICATION_SOURCES=("$ROOT"/Sources/Duplication/*.swift)
LAUNCHER_RUNTIME_SOURCES=(
  "$ROOT/Sources/Duplication/InstalledApp.swift"
  "$ROOT/Sources/Duplication/EngineDetector.swift"
  "$ROOT/Sources/Duplication/AppScanner.swift"
  "$ROOT/Sources/Duplication/ManagedLauncherPayload.swift"
)

runner="$workspace/.build/KlikProManagedLauncher"
harness="$workspace/.build/EvidenceMain"

xcrun swiftc \
  -sdk "$SDK" \
  -module-cache-path "$workspace/module-cache" \
  -target "$ARCH-apple-macosx13.0" \
  -warnings-as-errors \
  "${LAUNCHER_RUNTIME_SOURCES[@]}" \
  "$ROOT/Sources/KlikProManagedLauncher.swift" \
  -o "$runner"

xcrun swiftc \
  -sdk "$SDK" \
  -module-cache-path "$workspace/module-cache" \
  -target "$ARCH-apple-macosx13.0" \
  -warnings-as-errors \
  "$ROOT/Sources/KlikProConfig.swift" \
  "${DUPLICATION_SOURCES[@]}" \
  "$ROOT/tools/EvidenceMain.swift" \
  -o "$harness"

KLIK_PRO_EVIDENCE_RUNNER="$runner" "$harness" "$@"
