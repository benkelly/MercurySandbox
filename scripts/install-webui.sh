#!/usr/bin/env bash
# hermes-webui, native, auto-discovers ~/.hermes
set -euo pipefail
TARGET="${HOME}/hermes-webui"
[ -d "$TARGET" ] || git clone https://github.com/nesquena/hermes-webui.git "$TARGET"
cd "$TARGET"
./ctl.sh start
./ctl.sh status
echo "Manage with: cd ~/hermes-webui && ./ctl.sh status|logs|restart|stop"
