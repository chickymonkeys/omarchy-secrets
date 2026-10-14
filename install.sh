#!/usr/bin/env bash
# Install Omarchy Secrets: a bar toggle that unlocks Bitwarden (rbw) and shares
# your fnox secrets with terminals and agents, off at every login.
#
#   ./install.sh              set everything up (copying this checkout into the plugins folder if needed)
#   ./install.sh --link       symlink the plugin folder to this checkout instead (for development)
#   ./install.sh --uninstall  remove the toggle and undo the setup (keeps your fnox config and vault)
#   --no-enable               don't add the indicator to the bar
#   --no-restart              on an update, don't restart the shell to load the new widget
#
# After `omarchy plugin add <git url> --enable`, run this script from the plugin
# folder to finish the setup. It is safe to run again: every step checks first.
set -euo pipefail

SRC="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_ID="chickymonkeys.secrets"
PLUGIN_DIR="$HOME/.config/omarchy/plugins/$PLUGIN_ID"
CLI_LINK="$HOME/.local/bin/secrets"
BASHRC="$HOME/.bashrc"
FNOX_CONFIG="$HOME/.config/fnox/config.toml"
MARKER=".secrets-install"
COPIED=(manifest.json Secrets.qml Prompt.qml bin shell examples install.sh LICENSE README.md)
PACKAGES=(rbw pinentry)
BLOCK_START="# >>> omarchy-secrets >>>"
BLOCK_END="# <<< omarchy-secrets <<<"
MODE="install"
LINK=false
ENABLE=true
RESTART=true
UPDATE=false

for arg in "$@"; do
  case "$arg" in
    --link) LINK=true ;;
    --no-enable) ENABLE=false ;;
    --no-restart) RESTART=false ;;
    --uninstall) MODE="uninstall" ;;
    -h|--help)
      sed -n '2,12p' "$0" | sed 's/^# \{0,1\}//'
      exit 0
      ;;
    *) echo "Unknown option: $arg" >&2; exit 1 ;;
  esac
done

say() { printf '\033[1;32m==>\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m==>\033[0m %s\n' "$*" >&2; }
interactive() { [[ -t 0 && -t 1 ]]; }
confirm() { interactive && command -v gum >/dev/null 2>&1 && gum confirm "$1"; }

is_ours() {
  # A symlink to a checkout with our manifest, a copy this script made, or an
  # unmodified clone from `omarchy plugin add` (so --link can replace it)
  if [[ -L $PLUGIN_DIR ]]; then
    local target
    target="$(readlink -f "$PLUGIN_DIR")" || return 1
    grep -q "\"id\": \"$PLUGIN_ID\"" "$target/manifest.json" 2>/dev/null
  elif [[ -f $PLUGIN_DIR/$MARKER ]]; then
    return 0
  else
    [[ -d $PLUGIN_DIR/.git ]] && grep -q "\"id\": \"$PLUGIN_ID\"" "$PLUGIN_DIR/manifest.json" 2>/dev/null &&
      [[ -z "$(git -C "$PLUGIN_DIR" status --porcelain 2>/dev/null)" ]] &&
      [[ -z "$(git -C "$PLUGIN_DIR" log --branches --not --remotes --oneline 2>/dev/null)" ]]
  fi
}

in_bar() {
  local config="$HOME/.config/omarchy/shell.json"
  [[ -f $config ]] && jq -e --arg id "$PLUGIN_ID" \
    '[.bar.layout // {} | .[] | .[]? | .id] | index($id) != null' "$config" >/dev/null 2>&1
}

# Rewrite a file in place (keeps a symlinked ~/.bashrc pointing at its dotfiles repo)
rewrite() {
  local file="$1" tmp
  tmp="$(mktemp)"
  cat >"$tmp"
  cat "$tmp" >"$file"
  rm -f "$tmp"
}

remove_shell_block() {
  [[ -f $BASHRC ]] && grep -qF "$BLOCK_START" "$BASHRC" || return 0
  awk -v start="$BLOCK_START" -v end="$BLOCK_END" '
    $0 == start { skipping = 1; next }
    skipping && $0 == end { skipping = 0; next }
    !skipping { print }
  ' "$BASHRC" | rewrite "$BASHRC"
  say "Removed the shell integration from $BASHRC"
}

restart_shell() {
  if command -v omarchy-restart-shell >/dev/null 2>&1; then
    say "Restarting the shell to load the new widget"
    omarchy-restart-shell >/dev/null 2>&1 || warn "Could not restart the shell: omarchy restart shell"
  else
    warn "Restart the shell to load the new widget"
  fi
}

# --- Uninstall -----------------------------------------------------------------

if [[ $MODE == "uninstall" ]]; then
  rm -f "${XDG_RUNTIME_DIR:-/run/user/$UID}/secrets-enabled"
  command -v rbw >/dev/null 2>&1 && rbw lock >/dev/null 2>&1 || true
  command -v fnox >/dev/null 2>&1 && fnox daemon stop >/dev/null 2>&1 || true

  command -v omarchy >/dev/null 2>&1 && omarchy plugin disable "$PLUGIN_ID" >/dev/null 2>&1 || true
  remove_shell_block

  if [[ -L $CLI_LINK && "$(readlink -f "$CLI_LINK")" == */bin/secrets ]]; then
    rm "$CLI_LINK"
    say "Removed $CLI_LINK"
  fi

  if command -v rbw >/dev/null 2>&1 && rbw config show 2>/dev/null | grep -q 'pinentry-omarchy'; then
    rbw config set pinentry pinentry >/dev/null 2>&1 && say "Reset rbw's pinentry to the default"
  fi

  if [[ -e $PLUGIN_DIR || -L $PLUGIN_DIR ]]; then
    if is_ours; then
      if [[ -L $PLUGIN_DIR ]]; then rm "$PLUGIN_DIR"; else rm -rf "$PLUGIN_DIR"; fi
      say "Removed $PLUGIN_DIR"
    else
      warn "Left $PLUGIN_DIR alone: it wasn't installed by this script (use: omarchy plugin remove $PLUGIN_ID)"
    fi
  fi

  say "Uninstalled. Your fnox config ($FNOX_CONFIG) and rbw login were kept."
  exit 0
fi

# --- Plugin folder -------------------------------------------------------------

if [[ $SRC == "$(readlink -f "$PLUGIN_DIR" 2>/dev/null)" ]]; then
  # Running from the installed plugin (omarchy plugin add, or a git clone there)
  UPDATE=false
else
  mkdir -p "$(dirname "$PLUGIN_DIR")"
  if [[ -e $PLUGIN_DIR || -L $PLUGIN_DIR ]]; then
    UPDATE=true
    if is_ours; then
      if [[ -L $PLUGIN_DIR ]]; then rm "$PLUGIN_DIR"; else rm -rf "$PLUGIN_DIR"; fi
    else
      warn "$PLUGIN_DIR exists and has local changes or wasn't installed by this script."
      warn "Move it aside, or update it with: omarchy plugin update $PLUGIN_ID"
      exit 1
    fi
  fi

  if $LINK; then
    ln -s "$SRC" "$PLUGIN_DIR"
    say "Linked $PLUGIN_DIR -> $SRC"
  else
    mkdir -p "$PLUGIN_DIR"
    for entry in "${COPIED[@]}"; do
      [[ -e $SRC/$entry ]] && cp -a "$SRC/$entry" "$PLUGIN_DIR/"
    done
    touch "$PLUGIN_DIR/$MARKER"
    say "Copied to $PLUGIN_DIR"
  fi
fi

# --- Dependencies --------------------------------------------------------------

missing=()
for package in "${PACKAGES[@]}"; do
  pacman -Q "$package" >/dev/null 2>&1 || missing+=("$package")
done
if ((${#missing[@]})); then
  if confirm "Install ${missing[*]}?"; then
    omarchy pkg add "${missing[@]}"
  else
    warn "Missing packages: ${missing[*]}. Install them with: omarchy pkg add ${missing[*]}"
  fi
fi

if ! command -v fnox >/dev/null 2>&1; then
  if command -v mise >/dev/null 2>&1 && confirm "Install fnox with mise (mise use -g fnox)?"; then
    mise use -g fnox
  else
    warn "fnox is missing. Install it with: mise use -g fnox (see https://fnox.jdx.dev)"
  fi
fi

# --- Command, password prompt, shell -------------------------------------------

mkdir -p "$(dirname "$CLI_LINK")"
if [[ $(readlink "$CLI_LINK" 2>/dev/null) == "$PLUGIN_DIR/bin/secrets" ]]; then
  : # already linked
elif [[ ! -e $CLI_LINK || ( -L $CLI_LINK && "$(readlink -f "$CLI_LINK")" == */bin/secrets ) ]]; then
  ln -sfn "$PLUGIN_DIR/bin/secrets" "$CLI_LINK"
  say "Linked the secrets command: $CLI_LINK"
else
  warn "$CLI_LINK exists and isn't ours; use $PLUGIN_DIR/bin/secrets from a terminal"
fi

if command -v rbw >/dev/null 2>&1; then
  pinentry="$PLUGIN_DIR/bin/pinentry-omarchy"
  if ! rbw config show 2>/dev/null | grep -qF "\"pinentry\": \"$pinentry\""; then
    rbw config set pinentry "$pinentry"
    say "rbw now asks for your password in Omarchy's own password card"
  fi
  if ! rbw config show 2>/dev/null | grep -q '"email": "[^"]'; then
    if interactive && command -v gum >/dev/null 2>&1; then
      email=$(gum input --placeholder "you@example.com" --header "Bitwarden account email") || email=""
      [[ -n $email ]] && rbw config set email "$email"
    fi
  fi
fi

if ! grep -qs "$PLUGIN_ID/shell/secrets.bash" "$BASHRC"; then
  {
    [[ -f $BASHRC ]] && cat "$BASHRC"
    printf '\n%s\n' "$BLOCK_START"
    printf '%s\n' "[[ -r ~/.config/omarchy/plugins/$PLUGIN_ID/shell/secrets.bash ]] && source ~/.config/omarchy/plugins/$PLUGIN_ID/shell/secrets.bash"
    printf '%s\n' "$BLOCK_END"
  } | rewrite "$BASHRC"
  say "Added the shell integration to $BASHRC"
fi

if [[ ! -e $FNOX_CONFIG ]]; then
  mkdir -p "$(dirname "$FNOX_CONFIG")"
  cp "$SRC/examples/fnox.toml" "$FNOX_CONFIG"
  say "Created $FNOX_CONFIG: list your Bitwarden items under [secrets]"
fi

# --- Bar -----------------------------------------------------------------------

if $ENABLE && command -v omarchy >/dev/null 2>&1 && ! in_bar; then
  if omarchy plugin enable "$PLUGIN_ID" --section center --before omarchy.indicators >/dev/null 2>&1 ||
    omarchy plugin enable "$PLUGIN_ID" --section center >/dev/null 2>&1; then
    say "Added the safe indicator to the bar (hover the bar's center to reveal it while off)"
  else
    warn "Could not add the indicator to the bar: omarchy plugin enable $PLUGIN_ID"
  fi
fi

$UPDATE && $RESTART && restart_shell

# --- Next steps ----------------------------------------------------------------

say "Done."
if command -v rbw >/dev/null 2>&1 && ! compgen -G "${XDG_CACHE_HOME:-$HOME/.cache}/rbw/*.json" >/dev/null; then
  echo "    Log in to Bitwarden once:     rbw login"
fi
echo "    Choose what to share:         \$EDITOR $FNOX_CONFIG"
echo "    Turn secrets on:              click the safe in the bar, or: secrets on"
