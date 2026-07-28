#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DEFAULT_XCODE="/Applications/Xcode.app/Contents/Developer"
PROFILE_DIRECTORY="$ROOT/build/profiles"

usage() {
  cat <<'EOF'
Usage: ./tools/xcode-dev.sh <command> [arguments]

Commands:
  doctor
      Show the Xcode, Swift, SDK, and Instruments versions used by this repo.

  open
      Open the repository folder in Xcode for source navigation and editing.

  check
      Run the repository verification suite with the full Xcode toolchain.

  build
      Build the verified universal release artifacts with the full Xcode toolchain.

  templates
      List the Instruments templates available to xctrace.

  profile [process] [template] [duration]
      Attach Instruments to a running process. Defaults:
      process="Klik PRO", template="Time Profiler", duration="30s".

  profile-launch [app] [template] [duration]
      Record a clean app launch. Defaults:
      app="/Applications/Klik PRO.app", template="App Launch", duration="15s".

Examples:
  ./tools/xcode-dev.sh doctor
  ./tools/xcode-dev.sh profile "Klik PRO" "Time Profiler" 30s
  ./tools/xcode-dev.sh profile "klik-pro-input" "Activity Monitor" 30s
  ./tools/xcode-dev.sh profile-launch
EOF
}

resolve_developer_directory() {
  if [[ -n "${DEVELOPER_DIR:-}" ]] \
    && [[ -x "$DEVELOPER_DIR/usr/bin/xcodebuild" ]]; then
    return
  fi

  local selected
  selected="$(xcode-select -p 2>/dev/null || true)"
  if [[ -n "$selected" && -x "$selected/usr/bin/xcodebuild" ]]; then
    DEVELOPER_DIR="$selected"
  elif [[ -x "$DEFAULT_XCODE/usr/bin/xcodebuild" ]]; then
    DEVELOPER_DIR="$DEFAULT_XCODE"
  else
    echo "A full Xcode installation was not found." >&2
    echo "Install Xcode in /Applications or set DEVELOPER_DIR explicitly." >&2
    exit 1
  fi
  export DEVELOPER_DIR
}

trace_output_path() {
  local template="$1"
  local safe_template
  safe_template="$(tr '[:upper:] /' '[:lower:]--' <<<"$template" | tr -cd '[:alnum:]_-')"
  mkdir -p "$PROFILE_DIRECTORY"
  printf '%s/%s-%s.trace\n' \
    "$PROFILE_DIRECTORY" \
    "$(date +%Y%m%d-%H%M%S)" \
    "$safe_template"
}

record_attached_process() {
  local process="${1:-Klik PRO}"
  local template="${2:-Time Profiler}"
  local duration="${3:-30s}"
  local output
  local pid

  if [[ "$template" == "Power Profiler" ]]; then
    echo "Power Profiler is exposed by xctrace but is not supported on macOS." >&2
    echo "Use Activity Monitor plus Time Profiler for a macOS process." >&2
    exit 64
  fi

  # Instruments can make a launchd-managed helper exit cleanly when an attached
  # recording ends. Give KeepAlive time to restart it, then attach to the resolved
  # PID so a name-resolution race cannot target the disappearing process.
  for _ in {1..15}; do
    pid="$(pgrep -x "$process" | head -1 || true)"
    [[ -n "$pid" ]] && break
    sleep 1
  done
  if [[ -z "$pid" ]]; then
    echo "Process is not running: $process" >&2
    echo "Open it first, then rerun this command." >&2
    exit 1
  fi

  output="$(trace_output_path "$template")"
  echo "Recording $template for $process (pid $pid, $duration)"
  xcrun xctrace record \
    --template "$template" \
    --time-limit "$duration" \
    --output "$output" \
    --attach "$pid"
  echo "Trace saved to: $output"
  echo "Open it with: open \"$output\""
}

record_app_launch() {
  local app="${1:-/Applications/Klik PRO.app}"
  local template="${2:-App Launch}"
  local duration="${3:-15s}"
  local output

  if [[ ! -d "$app" ]]; then
    echo "App bundle not found: $app" >&2
    echo "Build/install Klik PRO first, or pass a different .app path." >&2
    exit 1
  fi

  output="$(trace_output_path "$template")"
  echo "Recording $template for a clean launch of $app ($duration)"
  xcrun xctrace record \
    --template "$template" \
    --time-limit "$duration" \
    --output "$output" \
    --launch -- "$app"
  echo "Trace saved to: $output"
  echo "Open it with: open \"$output\""
}

resolve_developer_directory

case "${1:-}" in
  doctor)
    echo "Developer directory: $DEVELOPER_DIR"
    xcodebuild -version
    swiftc --version
    echo "macOS SDK: $(xcrun --sdk macosx --show-sdk-path)"
    xcrun xctrace version
    ;;
  open)
    xcrun xed "$ROOT"
    ;;
  check)
    "$ROOT/tools/check.sh"
    ;;
  build)
    "$ROOT/tools/build-release.sh"
    ;;
  templates)
    xcrun xctrace list templates
    ;;
  profile)
    record_attached_process "${2:-}" "${3:-}" "${4:-}"
    ;;
  profile-launch)
    record_app_launch "${2:-}" "${3:-}" "${4:-}"
    ;;
  help|-h|--help)
    usage
    ;;
  *)
    usage >&2
    exit 2
    ;;
esac
