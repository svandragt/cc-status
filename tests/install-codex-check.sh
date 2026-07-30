#!/bin/sh
# Checks scripts/install-codex-notify.sh: prepends the notify key, keeps the rest
# of the config, repeats safely, and refuses to clobber someone else's notify.
#
# Run: ./tests/install-codex-check.sh

set -e

root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

HOOK=/opt/cc-status/hooks/codex-notify.sh
export CODEX_CONFIG="$tmp/config.toml"

cat > "$CODEX_CONFIG" <<'TOML'
model = "gpt-5"

[mcp_servers.example]
command = "echo"
TOML

"$root/scripts/install-codex-notify.sh" "$HOOK" >/dev/null

grep -qF "notify = [\"$HOOK\"]" "$CODEX_CONFIG" || { echo "FAIL: notify not written" >&2; exit 1; }
grep -q 'model = "gpt-5"' "$CODEX_CONFIG" || { echo "FAIL: lost existing config" >&2; exit 1; }
# The key must be above the first table header, or TOML puts it inside that table.
if [ "$(grep -n 'notify =' "$CODEX_CONFIG" | cut -d: -f1)" -gt "$(grep -n '^\[' "$CODEX_CONFIG" | head -1 | cut -d: -f1)" ]; then
  echo "FAIL: notify landed inside a table" >&2
  exit 1
fi

# Second run is a no-op.
before=$(cat "$CODEX_CONFIG")
"$root/scripts/install-codex-notify.sh" "$HOOK" >/dev/null
[ "$before" = "$(cat "$CODEX_CONFIG")" ] || { echo "FAIL: second run changed the file" >&2; exit 1; }

# Someone else's notify is left alone, with a non-zero exit.
export CODEX_CONFIG="$tmp/other.toml"
echo 'notify = ["/usr/bin/mine"]' > "$CODEX_CONFIG"
if "$root/scripts/install-codex-notify.sh" "$HOOK" >/dev/null 2>&1; then
  echo "FAIL: clobbered an existing notify" >&2
  exit 1
fi
grep -q '/usr/bin/mine' "$CODEX_CONFIG" || { echo "FAIL: existing notify lost" >&2; exit 1; }

# A `notify` inside a table is not Codex's setting, so it must not block.
export CODEX_CONFIG="$tmp/table.toml"
printf '[some_table]\nnotify = ["nope"]\n' > "$CODEX_CONFIG"
"$root/scripts/install-codex-notify.sh" "$HOOK" >/dev/null
grep -qF "notify = [\"$HOOK\"]" "$CODEX_CONFIG" || { echo "FAIL: blocked by a table key" >&2; exit 1; }

echo "ok: install-codex-notify writes, preserves and refuses correctly"
