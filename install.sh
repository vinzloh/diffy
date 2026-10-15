#!/usr/bin/env bash
# diffy installer: sets up ~/.config/diffy/config.json and the ~/.local/bin/diffy
# command. Idempotent; re-run any time. Run the reviewer with `diffy serve`.
#   ./install.sh [--port N] [--host ADDR] [--roots DIR[,DIR]] [--machine LABEL] [--uninstall]
# --roots (or DIFFY_ROOTS) is required on first install: the folder(s) holding your repos.
# diffy never scans your whole home folder. --machine defaults to the short hostname.
# Non-interactive first install: set DIFFY_WEBHOOK_URL and DIFFY_WEBHOOK_KEY
# plus --roots or DIFFY_ROOTS (optional DIFFY_MACHINE) in the environment.
set -euo pipefail
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONF_DIR="${DIFFY_CONFIG_DIR:-$HOME/.config/diffy}"
export CONF="$CONF_DIR/config.json"
BIN="$HOME/.local/bin/diffy"
PORT=""; HOST=""; ROOTS="${DIFFY_ROOTS:-}"; LABEL="${DIFFY_MACHINE:-}"; UNINSTALL=0
while [ $# -gt 0 ]; do
  case "$1" in
    --port) PORT="$2"; shift 2;;
    --host) HOST="$2"; shift 2;;
    --roots) ROOTS="$2"; shift 2;;
    --machine) LABEL="$2"; shift 2;;
    --uninstall) UNINSTALL=1; shift;;
    -h|--help) sed -n 2,5p "$0"; exit 0;;
    *) echo "unknown option: $1" >&2; exit 2;;
  esac
done

if [ "$UNINSTALL" = 1 ]; then
  rm -f "$BIN"
  # clean up the systemd service that older versions installed
  if [ -f "$HOME/.config/systemd/user/diffy.service" ]; then
    systemctl --user disable --now diffy.service 2>/dev/null || true
    rm -f "$HOME/.config/systemd/user/diffy.service"
    systemctl --user daemon-reload 2>/dev/null || true
  fi
  rm -rf "$CONF_DIR"
  echo "diffy uninstalled (removed $BIN and $CONF_DIR). You can delete this clone."
  exit 0
fi

command -v python3 >/dev/null || { echo "python3 is required" >&2; exit 1; }
command -v git >/dev/null || { echo "git is required" >&2; exit 1; }
mkdir -p "$CONF_DIR"; chmod 700 "$CONF_DIR"
DEFAULT_LABEL="$(hostname -s 2>/dev/null || uname -n)"; DEFAULT_LABEL="${DEFAULT_LABEL%%.*}"

# --- repo folders: required, never defaults to ~
HAVE_SCOPE=0
[ -f "$CONF" ] && python3 -c 'import json,os,sys;c=json.load(open(os.environ["CONF"]));sys.exit(0 if (c.get("roots") or c.get("repos")) else 1)' 2>/dev/null && HAVE_SCOPE=1
if [ -z "$ROOTS" ] && [ "$HAVE_SCOPE" = 0 ]; then
  if [ -t 0 ]; then
    SUG=""; [ -d "$HOME/workspace" ] && SUG="$HOME/workspace"
    read -rp "Folder(s) that hold your repos, comma-separated${SUG:+ [$SUG]}: " ROOTS || true
    ROOTS="${ROOTS:-$SUG}"
    [ -n "$ROOTS" ] || { echo "A repo folder is required." >&2; exit 1; }
    read -rp "Scan $ROOTS for git repos? [y/N]: " OK || true
    case "$OK" in y|Y|yes|YES) ;; *) echo "Aborted. Re-run with --roots DIR." >&2; exit 1;; esac
  else
    echo "error: no repo folder given. Pass --roots DIR[,DIR] or set DIFFY_ROOTS (e.g. ./install.sh --roots ~/workspace)." >&2
    echo "diffy never scans your whole home folder." >&2
    exit 1
  fi
fi
if [ -n "$ROOTS" ]; then
  ABS=""
  IFS=',' read -ra _R <<< "$ROOTS"
  for r in "${_R[@]}"; do
    r="$(echo "$r" | sed 's/^ *//; s/ *$//')"; [ -n "$r" ] || continue
    r="${r/#\~/$HOME}"
    [ -d "$r" ] || { echo "error: repo folder does not exist: $r" >&2; exit 1; }
    [ "$(cd "$r" && pwd -P)" = "$(cd "$HOME" && pwd -P)" ] && { echo "error: refusing to scan your whole home folder; pick the folder that holds your repos." >&2; exit 1; }
    ABS="${ABS:+$ABS,}$(cd "$r" && pwd -P)"
  done
  ROOTS="$ABS"
fi

if [ ! -f "$CONF" ]; then
  URL="${DIFFY_WEBHOOK_URL:-}"; KEY="${DIFFY_WEBHOOK_KEY:-}"
  if [ -z "$URL" ] || [ -z "$KEY" ]; then
    echo "No config yet at $CONF"
    [ -n "$URL" ] || read -rp "Webhook URL: " URL
    [ -n "$KEY" ] || { read -rsp "Webhook key (hidden): " KEY; echo; }
    [ -n "$LABEL" ] || read -rp "Machine label [$DEFAULT_LABEL]: " LABEL || true
  fi
  [ -n "$URL" ] && [ -n "$KEY" ] || { echo "webhook URL and key are required" >&2; exit 1; }
  ( umask 077
    URL="$URL" KEY="$KEY" LABEL="${LABEL:-$DEFAULT_LABEL}" python3 -c '
import json, os
json.dump({"url": os.environ["URL"], "key": os.environ["KEY"], "machine": os.environ["LABEL"]}, open(os.environ["CONF"], "w"), indent=1)
' ) 
  unset KEY DIFFY_WEBHOOK_KEY
fi
if [ -n "$PORT$HOST$ROOTS$LABEL" ]; then
  PORT="$PORT" HOST="$HOST" ROOTS="$ROOTS" LABEL="$LABEL" python3 -c '
import json, os
p = os.environ["CONF"]; c = json.load(open(p))
if os.environ["PORT"]: c["port"] = int(os.environ["PORT"])
if os.environ["HOST"]: c["host"] = os.environ["HOST"]
if os.environ["ROOTS"]: c["roots"] = [r.strip() for r in os.environ["ROOTS"].split(",") if r.strip()]
if os.environ["LABEL"]: c["machine"] = os.environ["LABEL"]
json.dump(c, open(p, "w"), indent=1)'
fi
chmod 600 "$CONF"

chmod +x "$DIR/diffy"
mkdir -p "$(dirname "$BIN")"
ln -sf "$DIR/diffy" "$BIN"
# older versions ran diffy as a systemd user service; stop it so the port is free
if [ -f "$HOME/.config/systemd/user/diffy.service" ]; then
  systemctl --user disable --now diffy.service 2>/dev/null || true
  rm -f "$HOME/.config/systemd/user/diffy.service"; systemctl --user daemon-reload 2>/dev/null || true
fi
python3 -c 'import json,os;c=json.load(open(os.environ["CONF"]));print("Machine label:", c.get("machine") or "(hostname)");print("Repo roots:", ", ".join(c.get("roots") or ["(explicit repos list)"]), "(depth %s)" % c.get("depth", 4))'
echo "Repos found:"
"$BIN" rediscover | sed 's/^/  /'
echo "diffy is set up. Start it with:  diffy serve   (Ctrl+C to stop)"
case ":$PATH:" in *":$(dirname "$BIN"):"*) ;; *) echo "Note: $(dirname "$BIN") is not on your PATH; add it, or run $BIN";; esac
