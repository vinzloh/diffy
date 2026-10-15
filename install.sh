#!/usr/bin/env bash
# diffy installer: idempotent. Re-run any time (e.g. after `git pull`).
#   ./install.sh [--port N] [--host ADDR] [--uninstall]
set -euo pipefail
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONF_DIR="${DIFFY_CONFIG_DIR:-$HOME/.config/diffy}"
export CONF="$CONF_DIR/config.json"
UNIT="$HOME/.config/systemd/user/diffy.service"
BIN="$HOME/.local/bin/diffy"
PORT=""; HOST=""; UNINSTALL=0
while [ $# -gt 0 ]; do
  case "$1" in
    --port) PORT="$2"; shift 2;;
    --host) HOST="$2"; shift 2;;
    --uninstall) UNINSTALL=1; shift;;
    -h|--help) sed -n 2,4p "$0"; exit 0;;
    *) echo "unknown option: $1" >&2; exit 2;;
  esac
done

if [ "$UNINSTALL" = 1 ]; then
  systemctl --user disable --now diffy.service 2>/dev/null || true
  rm -f "$UNIT" "$BIN"; systemctl --user daemon-reload
  echo "diffy service removed. Config kept at $CONF (delete it yourself if you want)."
  exit 0
fi

command -v python3 >/dev/null || { echo "python3 is required" >&2; exit 1; }
command -v git >/dev/null || { echo "git is required" >&2; exit 1; }
mkdir -p "$CONF_DIR"; chmod 700 "$CONF_DIR"

if [ ! -f "$CONF" ]; then
  echo "No config yet at $CONF"
  read -rp "Webhook URL: " URL
  read -rsp "Webhook key (hidden): " KEY; echo
  read -rp "Machine label [$(hostname)]: " LABEL
  ( umask 077
    URL="$URL" KEY="$KEY" LABEL="${LABEL:-$(hostname)}" python3 -c '
import json, os
json.dump({"url": os.environ["URL"], "key": os.environ["KEY"], "machine": os.environ["LABEL"]}, open(os.environ["CONF"], "w"), indent=1)
' ) 
  unset KEY
fi
if [ -n "$PORT$HOST" ]; then
  PORT="$PORT" HOST="$HOST" python3 -c '
import json, os
p = os.environ["CONF"]; c = json.load(open(p))
if os.environ["PORT"]: c["port"] = int(os.environ["PORT"])
if os.environ["HOST"]: c["host"] = os.environ["HOST"]
json.dump(c, open(p, "w"), indent=1)'
fi
chmod 600 "$CONF"

chmod +x "$DIR/diffy"
mkdir -p "$(dirname "$BIN")" "$(dirname "$UNIT")"
ln -sf "$DIR/diffy" "$BIN"
cat > "$UNIT" <<UNITEOF
[Unit]
Description=diffy local git diff reviewer
After=network-online.target

[Service]
ExecStart=/usr/bin/env python3 $DIR/diffy serve
Restart=on-failure

[Install]
WantedBy=default.target
UNITEOF
systemctl --user daemon-reload
systemctl --user enable diffy.service >/dev/null 2>&1
systemctl --user restart diffy.service
"$DIR/diffy" rediscover
P=$(python3 -c 'import json,os;print(json.load(open(os.environ["CONF"])).get("port",4747))')
echo "diffy installed: http://localhost:$P  (service: diffy.service, CLI: $BIN)"
echo "Tip: to keep it running while logged out: sudo loginctl enable-linger $USER"
