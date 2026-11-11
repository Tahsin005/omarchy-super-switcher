#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/.."

TMP_DIR=$(mktemp -d /tmp/switcher-install-test.XXXXXX)
trap 'rm -rf "$TMP_DIR"' EXIT

# Test 1: install.sh --squared
XDG_CONFIG_HOME="$TMP_DIR/config1" ./install.sh --squared --no-enable >/dev/null
if [[ ! -f "$TMP_DIR/config1/omarchy/super-switcher-border-style" ]]; then
  echo "FAIL: super-switcher-border-style not created for --squared" >&2
  exit 1
fi
content=$(cat "$TMP_DIR/config1/omarchy/super-switcher-border-style" | tr -d ' \n\r')
if [[ "$content" != "squared" ]]; then
  echo "FAIL: expected 'squared', got '$content'" >&2
  exit 1
fi
echo "PASS: install.sh --squared writes 'squared'"

# Test 2: install.sh --rounded
XDG_CONFIG_HOME="$TMP_DIR/config2" ./install.sh --rounded --no-enable >/dev/null
content=$(cat "$TMP_DIR/config2/omarchy/super-switcher-border-style" | tr -d ' \n\r')
if [[ "$content" != "rounded" ]]; then
  echo "FAIL: expected 'rounded', got '$content'" >&2
  exit 1
fi
echo "PASS: install.sh --rounded writes 'rounded'"

# Test 3: non-interactive default without flags should be squared
XDG_CONFIG_HOME="$TMP_DIR/config3" ./install.sh --no-enable </dev/null >/dev/null
content=$(cat "$TMP_DIR/config3/omarchy/super-switcher-border-style" | tr -d ' \n\r')
if [[ "$content" != "squared" ]]; then
  echo "FAIL: expected default 'squared', got '$content'" >&2
  exit 1
fi
echo "PASS: install.sh non-interactive default writes 'squared'"

