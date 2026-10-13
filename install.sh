#!/bin/sh
# Link wisp onto PATH. Experiments are not part of the top-level install, so
# each one that needs to be on PATH carries its own installer.
#
#   ./install.sh         link into ~/.local/bin and verify
#   ./install.sh check   verify only, change nothing
set -eu
cd "$(dirname "$0")"
here="$(pwd)"
mode="${1:-install}"
fail=0
bin="$HOME/.local/bin"

ok()   { printf '  ok    %s\n' "$1"; }
miss() { printf '  MISS  %s\n' "$1"; fail=1; }

check() {
  # wispview is preferred. QuickLook is the fallback when there is no Swift.
  if [ -x "$here/wispview" ]; then ok "wispview built"
  elif command -v swiftc >/dev/null 2>&1; then miss "wispview not built (run ./install.sh)"
  else ok "no swiftc, wisp will use QuickLook"; fi
  command -v qlmanage   >/dev/null 2>&1 && ok "qlmanage (fallback viewer)" || miss "qlmanage, so this is not macOS"
  command -v pygmentize >/dev/null 2>&1 && ok "pygmentize"        || miss "pygmentize (pipx install pygments)"
  python3 -c 'import markdown' 2>/dev/null && ok "python markdown module" || miss "python markdown (pip install markdown)"
  case ":$PATH:" in *":$bin:"*) ok "$bin on PATH" ;; *) miss "$bin is not on PATH" ;; esac
  if [ -L "$bin/wisp" ] && [ "$(readlink "$bin/wisp")" = "$here/wisp" ]; then
    ok "wisp -> repo"
  elif [ -e "$bin/wisp" ]; then
    miss "$bin/wisp exists but does not point at this repo"
  else
    miss "wisp not linked"
  fi
}

install() {
  if command -v swiftc >/dev/null 2>&1; then
    swiftc -O "$here/wispview.swift" -o "$here/wispview" && echo "built wispview"
  else
    echo "no swiftc: wisp will fall back to QuickLook"
  fi
  mkdir -p "$bin"
  ln -sfn "$here/wisp" "$bin/wisp"
  echo "linked $bin/wisp"
}

case "$mode" in
  check) check ;;
  install) install; check ;;
  *) echo "usage: $0 [check]" >&2; exit 2 ;;
esac

[ "$fail" -eq 0 ] && echo "all good." || { echo "something is missing (see MISS above)."; exit 1; }
