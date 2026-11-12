#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/omarchy"
STYLE_FILE="$CONFIG_DIR/super-switcher-border-style"
PLUGINS_DIR="$CONFIG_DIR/plugins"
TARGET_DIR="$PLUGINS_DIR/harryxu.super-switcher"

REPO_URL="${REPO_URL:-https://github.com/Tahsin005/omarchy-super-switcher.git}"
STYLE=""
ENABLE=true

usage() {
  cat <<EOF
Usage: ./install.sh [OPTIONS]

Install and configure Omarchy Super Switcher.

Options:
  --rounded             Configure rounded (macOS-style) borders (default)
  --squared, --square   Configure squared (sharp) borders
  --no-enable           Do not automatically enable the plugin or restart the shell
  -h, --help            Show this help message

If no option is provided in an interactive terminal, you will be prompted to choose.
EOF
  exit 0
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --squared|--square)
      STYLE="squared"
      shift
      ;;
    --rounded)
      STYLE="rounded"
      shift
      ;;
    --no-enable)
      ENABLE=false
      shift
      ;;
    -h|--help)
      usage
      ;;
    *)
      echo "Unknown option: $1" >&2
      usage
      ;;
  esac
done

# If style was not passed via CLI flag, prompt interactively or use default.
if [[ -z "$STYLE" ]]; then
  if [[ -t 0 && -t 1 ]]; then
    if command -v gum >/dev/null 2>&1; then
      choice=$(gum choose \
        --header="Choose border style for harryxu.super-switcher:" \
        --selected="rounded" \
        "rounded" \
        "squared") || true
      if [[ -n "$choice" ]]; then
        STYLE="$choice"
      fi
    else
      echo "Choose border style for harryxu.super-switcher:"
      echo "  1) rounded [default]"
      echo "  2) squared"
      read -r -p "Enter choice [1/2] (default: 1): " input_choice || true
      case "$input_choice" in
        2|[Ss]|[Ss]quare|[Ss]quared)
          STYLE="squared"
          ;;
        *)
          STYLE="rounded"
          ;;
      esac
    fi
  fi
  # Fallback for non-interactive execution without flags
  if [[ -z "$STYLE" ]]; then
    STYLE="rounded"
  fi
fi

# Ensure config directory exists and persist setting
mkdir -p "$CONFIG_DIR"
echo "$STYLE" > "$STYLE_FILE"
echo "✓ Saved border style preference: $STYLE"

# Install / link plugin if run from an external directory or piped
mkdir -p "$PLUGINS_DIR"
if [[ ! -f "$SCRIPT_DIR/manifest.json" ]]; then
  if [[ -L "$TARGET_DIR" && ! -e "$TARGET_DIR" ]]; then
    rm -f "$TARGET_DIR"
  fi
  if [[ ! -d "$TARGET_DIR" && ! -L "$TARGET_DIR" ]]; then
    echo "Cloning plugin into $TARGET_DIR..."
    git clone "$REPO_URL" "$TARGET_DIR"
  fi
elif [[ "$SCRIPT_DIR" != "$TARGET_DIR" ]]; then
  if [[ -L "$TARGET_DIR" ]]; then
    if [[ "$(readlink -f "$TARGET_DIR")" != "$SCRIPT_DIR" ]]; then
      echo "Updating plugin target link at $TARGET_DIR..."
      ln -sfn "$SCRIPT_DIR" "$TARGET_DIR"
    fi
  elif [[ -d "$TARGET_DIR" ]]; then
    echo "Replacing plugin directory at $TARGET_DIR with link to $SCRIPT_DIR..."
    rm -rf "$TARGET_DIR"
    ln -s "$SCRIPT_DIR" "$TARGET_DIR"
  else
    echo "Linking plugin into $TARGET_DIR..."
    ln -s "$SCRIPT_DIR" "$TARGET_DIR"
  fi
fi

# Rescan and update running shell if available
if command -v omarchy-shell >/dev/null 2>&1; then
  omarchy-shell shell rescanPlugins >/dev/null 2>&1 || true
  omarchy-shell harryxu.super-switcher setBorderStyle "$STYLE" >/dev/null 2>&1 || true
fi

# Link convenience launcher to ~/.local/bin if available
LOCAL_BIN="${HOME}/.local/bin"
LAUNCHER="$TARGET_DIR/install.sh"
if [[ -f "$SCRIPT_DIR/install.sh" ]]; then
  LAUNCHER="$SCRIPT_DIR/install.sh"
fi
if [[ -f "$LAUNCHER" && (-d "$LOCAL_BIN" || -w "$HOME") ]]; then
  mkdir -p "$LOCAL_BIN"
  ln -sf "$LAUNCHER" "$LOCAL_BIN/omarchy-super-switcher-setup"
fi

if [[ "$ENABLE" == true ]]; then
  if command -v omarchy >/dev/null 2>&1; then
    omarchy plugin enable harryxu.super-switcher >/dev/null 2>&1 || true
    omarchy restart shell >/dev/null 2>&1 || true
  fi
fi

cat <<EOF

==================================================
✓ Omarchy Super Switcher configured with '${STYLE}' borders!
==================================================

You can change this at any time using:
  omarchy-shell harryxu.super-switcher setBorderStyle squared
  omarchy-shell harryxu.super-switcher setBorderStyle rounded

Or re-run:
  ./install.sh
EOF
