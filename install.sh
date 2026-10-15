#!/usr/bin/env bash
# diffy installer: sets up ~/.config/diffy/config.json and the ~/.local/bin/diffy
# command. Idempotent; re-run any time. Run the reviewer with `diffy serve`.
#   ./install.sh [--port N] [--host ADDR] [--roots DIR[,DIR]] [--machine LABEL] [--uninstall]
# Non-interactive first install: set DIFFY_WEBHOOK_URL and DIFFY_WEBHOOK_KEY
# (optional DIFFY_MACHINE, DIFFY_ROOTS) in the environment.
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

if [ ! -f "$CONF" ]; then
  URL="${DIFFY_WEBHOOK_URL:-}"; KEY="${DIFFY_WEBHOOK_KEY:-}"
  if [ -z "$URL" ] || [ -z "$KEY" ]; then
    echo "No config yet at $CONF"
    [ -n "$URL" ] || read -rp "Webhook URL: " URL
    [ -n "$KEY" ] || { read -rsp "Webhook key (hidden): " KEY; echo; }
    [ -n "$LABEL" ] || read -rp "Machine label [$(hostname)]: " LABEL || true
  fi
  [ -n "$URL" ] && [ -n "$KEY" ] || { echo "webhook URL and key are required" >&2; exit 1; }
  ( umask 077
    URL="$URL" KEY="$KEY" LABEL="${LABEL:-$(hostname)}" python3 -c '
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
"$BIN" rediscover
echo "diffy is set up. Start it with:  diffy serve   (Ctrl+C to stop)"
case ":$PATH:" in *":$(dirname "$BIN"):"*) ;; *) echo "Note: $(dirname "$BIN") is not on your PATH; add it, or run $BIN";; esac
