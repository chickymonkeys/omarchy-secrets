# Omarchy Secrets: shell integration for bash. Source it from ~/.bashrc (the
# installer adds the line).
#
# Exports the secrets in ~/.config/fnox/config.toml into this shell and
# everything started from it, including agents, but only while the Secrets
# toggle is on: the safe indicator in the bar, or `secrets on|off`. Every prompt
# checks the toggle, so turning it off also unsets them in open shells.

[[ $- == *i* ]] || return 0
command -v fnox &> /dev/null || return 0

export FNOX_SHELL_OUTPUT=none
_secrets_flag="${XDG_RUNTIME_DIR:-/run/user/$UID}/secrets-enabled"

# Keep fnox's functions, but run its hook through the toggle below.
_secrets_prompt_command=$PROMPT_COMMAND
eval "$(fnox activate bash)"
PROMPT_COMMAND="_secrets_hook${_secrets_prompt_command:+;$_secrets_prompt_command}"
unset _secrets_prompt_command

_secrets_hook() {
  local status=$?
  if [[ -e $_secrets_flag ]]; then
    _fnox_hook
  elif [[ -n ${__FNOX_SESSION:-} ]]; then
    eval "$(command fnox deactivate 2> /dev/null | grep -E '^unset [A-Za-z_][A-Za-z0-9_]*$')"
    unset __FNOX_SESSION
  fi
  return $status
}

# Run it now too, so commands started without a prompt (`ghostty -e claude`,
# `bash -ic ...`) get secrets.
_secrets_hook
