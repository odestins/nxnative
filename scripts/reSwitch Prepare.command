#!/bin/zsh
cd "${0:A:h:h}" || exit 1
export PATH="/opt/homebrew/bin:/usr/local/bin:/usr/local/share/dotnet:$PATH"
iswitch_python="${ISWITCH_PYTHON:-$HOME/Documents/iSwitch Games/.venv/bin/python}"
if [ ! -x "$iswitch_python" ]; then iswitch_python="$(command -v python3)"; fi
"$iswitch_python" scripts/iswitch.py wizard
result=$?
echo ""
if [ "$result" -ne 0 ]; then echo "See docs/iswitch.md for setup instructions."; fi
read -r "?Press Return to close."
exit "$result"
