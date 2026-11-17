#!/usr/bin/env bash
#
# helpme.sh — Expensy build / deploy / run helper
#
# A single entry point for the day-to-day workflow on this machine:
#   env setup, doctor, build, install, live-run, tests, logs, cleanup.
#
# Usage:
#   ./helpme.sh <command> [args]
#   ./helpme.sh help            # show all commands
#
# The script is self-contained: it pins the correct JDK 17 / Android SDK /
# Flutter / adb on PATH itself, so it works even from a shell that hasn't
# sourced ~/.bashrc.

set -uo pipefail

# ---------------------------------------------------------------------------
# Environment (overridable via existing env vars)
# ---------------------------------------------------------------------------
export JAVA_HOME="${JAVA_HOME:-$HOME/jdk/jdk-17.0.21+9}"
export ANDROID_HOME="${ANDROID_HOME:-$HOME/Android/Sdk}"
export PATH="$HOME/flutter/bin:$ANDROID_HOME/platform-tools:$JAVA_HOME/bin:$PATH"

FLUTTER="${FLUTTER:-$HOME/flutter/bin/flutter}"
ADB="${ADB:-$ANDROID_HOME/platform-tools/adb}"
PACKAGE="${PACKAGE:-com.ma.expensy}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
APK_DEBUG="build/app/outputs/flutter-apk/app-debug.apk"
APK_RELEASE="build/app/outputs/flutter-apk/app-release.apk"

# ---------------------------------------------------------------------------
# Colors / logging
# ---------------------------------------------------------------------------
if [[ -t 1 ]]; then
  C_RESET=$'\033[0m'; C_BOLD=$'\033[1m'; C_DIM=$'\033[2m'
  C_RED=$'\033[31m'; C_GREEN=$'\033[32m'; C_YELLOW=$'\033[33m'
  C_BLUE=$'\033[34m'; C_CYAN=$'\033[36m'
else
  C_RESET=""; C_BOLD=""; C_DIM=""; C_RED=""; C_GREEN=""; C_YELLOW=""; C_BLUE=""; C_CYAN=""
fi

info()  { printf '%s\n' "${C_BLUE}ℹ${C_RESET} $*"; }
ok()    { printf '%s\n' "${C_GREEN}✔${C_RESET} $*"; }
warn()  { printf '%s\n' "${C_YELLOW}⚠${C_RESET} $*"; }
err()   { printf '%s\n' "${C_RED}✖${C_RESET} $*" >&2; }
step()  { printf '\n%s\n' "${C_BOLD}${C_CYAN}▶ $*${C_RESET}"; }
die()   { err "$*"; exit 1; }

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------
require() {
  command -v "$1" >/dev/null 2>&1 || die "'$1' not found on PATH. Check your environment (run: $0 env)."
}

# Print the first connected adb device serial, or die.
device() {
  local serial
  serial="$("$ADB" devices | awk 'NR>1 && $2=="device" {print $1; exit}')"
  [[ -n "$serial" ]] || { "$ADB" devices >&2; die "No device connected. Plug in your phone, enable USB debugging, then re-run."; }
  printf '%s' "$serial"
}

# Ensure the adb server is alive (the phone has dropped off USB before).
ensure_adb() {
  "$ADB" start-server >/dev/null 2>&1 || true
}

# ---------------------------------------------------------------------------
# Commands
# ---------------------------------------------------------------------------
cmd_env() {
  step "Environment"
  printf '  JAVA_HOME   : %s\n' "$JAVA_HOME"
  printf '  ANDROID_HOME: %s\n' "$ANDROID_HOME"
  printf '  flutter     : %s\n' "$(command -v flutter || echo 'NOT FOUND')"
  printf '  adb         : %s\n' "$(command -v adb || echo 'NOT FOUND')"
  printf '  java        : %s\n' "$(command -v java || echo 'NOT FOUND')"
  printf '  package     : %s\n' "$PACKAGE"
  echo
  info "Versions:"
  flutter --version 2>/dev/null | sed 's/^/    /' | head -1
  java -version 2>&1 | sed 's/^/    /' | head -1
  "$ADB" version 2>/dev/null | sed 's/^/    /' | head -1
  echo
  info "Connected devices:"
  "$ADB" devices | sed 's/^/    /'
}

cmd_doctor() {
  step "flutter doctor"
  flutter doctor -v
}

cmd_pub() {
  step "flutter pub get"
  flutter pub get
}

cmd_clean() {
  step "flutter clean"
  flutter clean
  info "Re-fetching dependencies..."
  flutter pub get
}

cmd_build() {
  local flavor="${1:-debug}"
  case "$flavor" in
    debug)   step "Building DEBUG apk";  flutter build apk --debug ;;
    release) step "Building RELEASE apk"; flutter build apk --release ;;
    *) die "Unknown flavor '$flavor' (use: debug | release)" ;;
  esac
  local apk
  apk="$([[ "$flavor" == release ]] && echo "$APK_RELEASE" || echo "$APK_DEBUG")"
  [[ -f "$SCRIPT_DIR/$apk" ]] || die "Build finished but $apk not found."
  ok "APK ready: $SCRIPT_DIR/$apk"
}

cmd_install() {
  local flavor="${1:-debug}"
  local apk
  apk="$([[ "$flavor" == release ]] && echo "$APK_RELEASE" || echo "$APK_DEBUG")"
  [[ -f "$SCRIPT_DIR/$apk" ]] || die "APK not found: $apk — run '$0 build $flavor' first."
  local serial
  ensure_adb
  serial="$(device)"
  step "Installing $flavor apk on $serial"
  "$ADB" -s "$serial" install -r "$SCRIPT_DIR/$apk"
  ok "Installed."
}

cmd_launch() {
  local serial
  ensure_adb
  serial="$(device)"
  step "Launching $PACKAGE on $serial"
  "$ADB" -s "$serial" shell monkey -p "$PACKAGE" -c android.intent.category.LAUNCHER 1 >/dev/null 2>&1
  ok "Launched. (Check the phone — it should be on the foreground.)"
}

cmd_uninstall() {
  local serial
  ensure_adb
  serial="$(device)"
  step "Uninstalling $PACKAGE from $serial"
  "$ADB" -s "$serial" uninstall "$PACKAGE"
  ok "Uninstalled."
}

# Live mode: hot-reload / hot-restart over the wire. Ctrl-C to stop.
cmd_run() {
  local serial
  ensure_adb
  serial="$(device)"
  step "flutter run (LIVE) on $serial — press 'r' to hot-reload, 'R' to hot-restart, 'q' to quit"
  flutter run -d "$serial"
}

# Full pipeline: build -> install -> launch (no live session).
cmd_deploy() {
  local flavor="${1:-debug}"
  cmd_build "$flavor"
  cmd_install "$flavor"
  cmd_launch
  step "Deploy complete 🎉"
  info "App is installed and running. For live hot-reload use: $0 run"
}

cmd_test() {
  step "flutter test"
  flutter test "$@"
}

cmd_golden() {
  step "Golden backup round-trip test"
  flutter test test/golden_backup_roundtrip_test.dart
}

cmd_guard() {
  local mode="${1:-report}"
  step "CI guard ($mode)"
  if [[ "$mode" == "enforce" ]]; then
    dart run tool/ci_guard.dart --enforce
  else
    dart run tool/ci_guard.dart
  fi
}

cmd_logs() {
  local serial
  ensure_adb
  serial="$(device)"
  step "Tail logcat for $PACKAGE (Ctrl-C to stop)"
  "$ADB" -s "$serial" logcat -c || true
  "$ADB" -s "$serial" logcat | grep --line-buffered -E "$PACKAGE|Flutter|AndroidRuntime|FATAL"
}

cmd_devices() {
  ensure_adb
  step "adb devices"
  "$ADB" devices -l
}

cmd_apk() {
  step "APK locations"
  for f in "$APK_DEBUG" "$APK_RELEASE"; do
    if [[ -f "$SCRIPT_DIR/$f" ]]; then
      printf '  %s  %s\n' "$(du -h "$SCRIPT_DIR/$f" | cut -f1)" "$SCRIPT_DIR/$f"
    else
      printf '  %s  %s\n' "-" "$SCRIPT_DIR/$f (not built)"
    fi
  done
}

# Poll lib/ + test/ for changes and rebuild (no inotify on this box).
cmd_watch() {
  local mode="${1:-build}"
  local serial
  ensure_adb
  serial="$(device)"
  case "$mode" in
    run)
      step "flutter run (LIVE) on $serial — 'r' reload, 'R' restart, 'q' quit"
      flutter run -d "$serial"
      ;;
    build|apk)
      step "Watching lib/ + test/ — rebuilding DEBUG apk on change (Ctrl-C to stop)"
      local marker changed
      marker="$(mktemp)"
      touch "$marker"
      trap 'rm -f "$marker"' EXIT
      while true; do
        changed="$(find lib test pubspec.yaml -type f \( -name '*.dart' -o -name '*.yaml' \) -newer "$marker" 2>/dev/null | head -1)"
        if [[ -n "$changed" ]]; then
          ok "Change detected: $changed"
          if flutter build apk --debug; then
            ok "Rebuilt debug APK."
          else
            warn "Build failed — will retry on the next change."
          fi
          touch "$marker"
        fi
        sleep 2
      done
      ;;
    *) die "Unknown watch mode '$mode' (use: build | run)" ;;
  esac
}

# Pull the app's private SQLite DB + shared_prefs to a local timestamped folder.
# Requires a DEBUG build (uses adb run-as).
cmd_backup() {
  local serial
  ensure_adb
  serial="$(device)"
  local ts dest
  ts="$(date +%Y%m%d_%H%M%S)"
  dest="backups/expensy_backup_$ts"
  mkdir -p "$dest"
  step "Backing up $PACKAGE (device $serial) → $dest/"
  "$ADB" -s "$serial" shell "run-as $PACKAGE cat databases/expensy.db" > "$dest/expensy.db" 2>/dev/null
  local dbbytes
  dbbytes="$(wc -c < "$dest/expensy.db" 2>/dev/null || echo 0)"
  [[ "$dbbytes" -gt 0 ]] || die "Failed to pull expensy.db (0 bytes). backup/restore need a DEBUG build (run: $0 build debug && $0 install debug)."
  while IFS= read -r f; do
    [[ -n "$f" ]] || continue
    "$ADB" -s "$serial" shell "run-as $PACKAGE cat shared_prefs/$f" > "$dest/$f" 2>/dev/null
  done < <("$ADB" -s "$serial" shell "run-as $PACKAGE ls shared_prefs/ 2>/dev/null")
  if command -v sqlite3 >/dev/null 2>&1; then
    local tables
    tables="$(sqlite3 "$dest/expensy.db" ".tables" 2>/dev/null | wc -w)"
    ok "Pulled expensy.db ($dbbytes bytes, $tables tables) + shared_prefs."
  else
    ok "Pulled expensy.db ($dbbytes bytes) + shared_prefs. (sqlite3 not installed — skipped table validation)"
  fi
  ok "Backup saved to: $SCRIPT_DIR/$dest"
}

# List local backups, newest first.
cmd_backups() {
  step "Local backups (backups/)"
  local found=0
  local d
  for d in $(ls -1d backups/expensy_backup_* backups/expensy_prerestore_* 2>/dev/null | sort -r); do
    found=1
    local db
    db="$([[ -f "$d/expensy.db" ]] && du -h "$d/expensy.db" | cut -f1 || echo '-')"
    printf '  %s  (db: %s)\n' "$d" "$db"
  done
  [[ "$found" -eq 1 ]] || info "No backups yet. Create one with: $0 backup"
}

# Push a local backup back to the device. Takes a pre-restore safety snapshot
# first (project safety-net rule), then force-stops, restores, and relaunches.
cmd_restore() {
  local serial
  ensure_adb
  serial="$(device)"
  local src="${1:-}"
  if [[ -z "$src" ]]; then
    src="$(ls -1d backups/expensy_backup_* 2>/dev/null | sort | tail -1)"
    [[ -n "$src" ]] || die "No backups found in backups/. Create one with: $0 backup"
    info "Using latest backup: $src"
  fi
  [[ -f "$src/expensy.db" ]] || die "No expensy.db in $src"
  local ts snap
  ts="$(date +%Y%m%d_%H%M%S)"
  snap="backups/expensy_prerestore_$ts"
  mkdir -p "$snap"
  step "Creating pre-restore safety snapshot → $snap/"
  "$ADB" -s "$serial" shell "run-as $PACKAGE cat databases/expensy.db" > "$snap/expensy.db" 2>/dev/null
  ok "Safety snapshot saved (roll back with: $0 restore $snap)"
  step "Stopping app, restoring $src/expensy.db → device"
  "$ADB" -s "$serial" shell am force-stop "$PACKAGE"
  "$ADB" -s "$serial" shell "run-as $PACKAGE sh -c 'cat > databases/expensy.db'" < "$src/expensy.db"
  local f base
  for f in "$src"/*.xml; do
    [[ -e "$f" ]] || continue
    base="$(basename "$f")"
    "$ADB" -s "$serial" shell "run-as $PACKAGE sh -c 'cat > shared_prefs/$base'" < "$f"
  done
  # verify the DB landed with the expected size
  local want got
  want="$(wc -c < "$src/expensy.db")"
  got="$("$ADB" -s "$serial" shell "run-as $PACKAGE sh -c 'wc -c < databases/expensy.db' 2>/dev/null" | tr -d '[:space:]')"
  if [[ "$got" == "$want" ]]; then
    ok "Verified: device DB is $got bytes (matches backup)."
  else
    warn "Size mismatch after restore (device=$got, backup=$want). Check the app; roll back if needed."
  fi
  step "Relaunching app"
  "$ADB" -s "$serial" shell monkey -p "$PACKAGE" -c android.intent.category.LAUNCHER 1 >/dev/null 2>&1
  ok "Restore complete. App restarted."
}

cmd_help() {
  cat <<EOF
${C_BOLD}helpme.sh — Expensy build / deploy / run helper${C_RESET}

${C_BOLD}Build & deploy${C_RESET}
  build [debug|release]   Build the APK (default: debug)
  install [debug|release] Install a built APK on the connected device
  launch                  Launch the app on the connected device
  deploy [debug|release]  build + install + launch (default: debug)
  run                     LIVE mode: flutter run with hot-reload (Ctrl-C to stop)
  watch [build|run]       Rebuild on file change (build) or live-run (run)
  apk                     Show built APK paths and sizes

${C_BOLD}Data (needs a DEBUG build)${C_RESET}
  backup                  Pull the app DB + prefs to backups/ (timestamped)
  restore [backup-dir]    Push a backup back (auto pre-restore snapshot)
  backups                 List local backups

${C_BOLD}Project${C_RESET}
  pub                     flutter pub get
  clean                   flutter clean + pub get
  test [args]             flutter test (pass extra args, e.g. a test file)
  golden                  Run the golden backup round-trip test
  guard [report|enforce]  Run the CI code-hygiene guard

${C_BOLD}Device / diagnostics${C_RESET}
  devices                 List connected adb devices
  logs                    Tail logcat filtered to this app (Ctrl-C to stop)
  uninstall               Uninstall the app from the device
  env                     Show resolved environment (JDK, SDK, flutter, adb)
  doctor                  Run flutter doctor -v
  help                    Show this help

${C_BOLD}Examples${C_RESET}
  $0 deploy                 # build debug, install, launch
  $0 run                    # live hot-reload session
  $0 watch build            # auto-rebuild the APK as you edit
  $0 backup                 # snapshot the app's data to your machine
  $0 restore                # restore the latest backup (with safety snapshot)
  $0 build release          # make a release APK
  $0 test test/database_test.dart
  $0 logs                   # watch logs while you use the app
EOF
}

# ---------------------------------------------------------------------------
# Dispatcher
# ---------------------------------------------------------------------------
main() {
  local cmd="${1:-help}"
  [[ $# -gt 0 ]] && shift
  case "$cmd" in
    env)      cmd_env ;;
    doctor)   cmd_doctor ;;
    pub)      cmd_pub ;;
    clean)    cmd_clean ;;
    build)    cmd_build "${1:-debug}" ;;
    install)  cmd_install "${1:-debug}" ;;
    launch)   cmd_launch ;;
    uninstall) cmd_uninstall ;;
    run)      cmd_run ;;
    deploy)   cmd_deploy "${1:-debug}" ;;
    watch)    cmd_watch "${1:-build}" ;;
    backup)   cmd_backup ;;
    restore)  cmd_restore "${1:-}" ;;
    backups)  cmd_backups ;;
    test)     cmd_test "$@" ;;
    golden)   cmd_golden ;;
    guard)    cmd_guard "${1:-report}" ;;
    logs)     cmd_logs ;;
    devices)  cmd_devices ;;
    apk)      cmd_apk ;;
    help|-h|--help) cmd_help ;;
    *) err "Unknown command: $cmd"; echo; cmd_help; exit 1 ;;
  esac
}

main "$@"
