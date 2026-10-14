# Omarchy Secrets

A key in the [Omarchy](https://omarchy.org) bar that turns your Bitwarden
secrets on and off for terminals, CLIs, and coding agents.

Secrets stay **off at every login**. Click the key, type your master password
into a prompt themed like the rest of Omarchy, and every terminal you open, along
with everything started from it, gets your API keys as environment variables.
Click again and they are gone: the vault locks, the cache is cleared, and open
terminals drop them at their next prompt.

Under the hood it is [rbw](https://github.com/doy/rbw) (an unofficial Bitwarden
client that keeps the unlocked key in memory) and [fnox](https://fnox.jdx.dev)
(which maps Bitwarden items to environment variables). Nothing secret is ever
written to disk.

## How it behaves

| State | Bar | Terminals |
| --- | --- | --- |
| Off (every login) | hidden, like Omarchy's inactive indicators; hover the bar's center to reveal it dimmed | no secrets |
| Unlocking | the key pulses while the password prompt is open | |
| On | the key is shown | open and new terminals load the secrets at their next prompt |
| Off again | hidden | open terminals unset them at their next prompt; running programs keep what they already have |

- The tooltip says what a click does: **Unlock Secrets** or **Lock Secrets**.
- Cancelling the password prompt (Esc) changes nothing and shows no error.
- When rbw locks itself (its `lock_timeout`), the toggle turns off and tells
  you, so nothing ever asks for your password unprompted.
- Everything the key does is also a command: `secrets on`, `secrets off`,
  `secrets toggle`, `secrets status`.

## Install

Requires Omarchy with its Quickshell bar, bash as your shell, and
[mise](https://mise.jdx.dev) or another way to install fnox.

The standard Omarchy route:

```sh
omarchy plugin add https://github.com/chickymonkeys/omarchy-secrets --enable
~/.config/omarchy/plugins/chickymonkeys.secrets/install.sh
```

Or from a checkout:

```sh
git clone https://github.com/chickymonkeys/omarchy-secrets
cd omarchy-secrets && ./install.sh
```

`install.sh` is safe to run again; each step checks first. It:

1. offers to install `rbw`, `pinentry-bemenu`, `bemenu-wayland` (`omarchy pkg add`) and fnox (`mise use -g fnox`);
2. links the `secrets` command into `~/.local/bin`;
3. points rbw at the themed password prompt (`bin/pinentry-omarchy`) and asks for your Bitwarden email if rbw has none;
4. adds one marked line to `~/.bashrc` that loads `shell/secrets.bash`;
5. creates `~/.config/fnox/config.toml` from `examples/fnox.toml` if you have none;
6. puts the key in the bar's center, before Omarchy's indicators.

Then:

```sh
rbw login                                # once per machine
$EDITOR ~/.config/fnox/config.toml       # list the secrets to share
```

```toml
[secrets]
OPENAI_API_KEY = { provider = "bitwarden", value = "OpenAI API" }    # item's password
GITHUB_TOKEN = { provider = "bitwarden", value = "GitHub/token" }    # item's custom field
```

The config holds only item names, never values, so it can live in a public
dotfiles repo.

## Security model

- **On disk:** only rbw's encrypted vault copy. No `BW_SESSION`, no plaintext.
- **In memory:** the vault key in `rbw-agent` and resolved values in the fnox
  daemon, both dropped by `secrets off` or rbw's timeout.
- **While on, any program running as you can read the secrets.** That is the
  point (agents and CLIs need them), but it also means a misbehaving agent can.
  Keep write-capable tokens out of shells with `env = "exec"` in the fnox
  config; they are then only available through `fnox exec -- <command>`.
- Programs started while secrets were on keep their copy of the environment
  after you turn them off. Restart them to drop it.
- `fnox get` or `fnox exec` while off asks for the password, because rbw unlocks
  on demand.
- Apps launched from the launcher (not a terminal) never get the secrets.

## How it works

```
key in the bar ──► bin/secrets on ──► rbw unlock (pinentry-omarchy) ──► fnox cache warm
                                  └─► $XDG_RUNTIME_DIR/secrets-enabled

every bash prompt ──► shell/secrets.bash: flag present? ──► fnox hook (export)
                                          flag absent?  ──► fnox deactivate (unset)
```

The flag lives in `$XDG_RUNTIME_DIR` (a tmpfs), which is why every login starts
off. The widget polls `secrets status --json` every 4 seconds, so changes made
from a terminal show up in the bar.

## Update and uninstall

```sh
omarchy plugin update chickymonkeys.secrets && omarchy restart shell
~/.config/omarchy/plugins/chickymonkeys.secrets/install.sh --uninstall
```

The shell has to restart to load a changed widget; `install.sh` does that on
updates from a checkout. Uninstalling keeps your fnox config and rbw login.

## Troubleshooting

- **The key doesn't react:** `secrets on` in a terminal shows the error the
  widget would. "Secrets need setup" lists what `install.sh` still has to do.
- **No password prompt appears:** `rbw unlock` from a terminal; without a
  Wayland session pinentry-omarchy falls back to a terminal prompt.
- **A secret is missing:** `fnox get NAME` shows Bitwarden's error; item names
  are case-sensitive, and custom fields use `Item/Field`.

## License

MIT
