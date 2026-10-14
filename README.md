# Omarchy Secrets

An indicator in the [Omarchy](https://omarchy.org) bar that turns your Bitwarden secrets on and off for terminals, CLIs, and coding agents.

Secrets stay **off at every login**. Click the variables indicator (󰫧), type your master password into Omarchy's own password card (the one it uses for polkit), and every terminal you open, along with everything started from it, gets your API keys as environment variables. Click again and they are gone: the vault locks, the cache is cleared, and open terminals drop them at their next prompt.

Under the hood it is [rbw](https://github.com/doy/rbw) (an unofficial Bitwarden client that keeps the unlocked key in memory) and [fnox](https://fnox.jdx.dev) (which maps Bitwarden items to environment variables). Nothing secret is ever written to disk.

## How it behaves

| State | Bar | Terminals |
| --- | --- | --- |
| Off (every login) | hidden, like Omarchy's inactive indicators; hover the bar's center to reveal it dimmed | no secrets |
| Unlocking | the indicator pulses; Omarchy's password card opens on the focused monitor | |
| On | the indicator is shown | open and new terminals load the secrets at their next prompt |
| Off again | hidden | open terminals unset them at their next prompt; running programs keep what they already have |

- The icon is 󰫧 (variables): it shows that your secrets are loaded as environment variables, not that something is locked. The password card shows a safe (󱉼), the Bitwarden vault you are unlocking.
- The tooltip says what a click does: **Unlock Secrets** or **Lock Secrets**.
- The card behaves like Omarchy's polkit prompt: a wrong password turns it red and shakes it, with the attempt count above it ("attempt 2 of 3"); Esc cancels quietly and changes nothing.
- Notifications only appear when something needs your attention (an error, or Bitwarden locking itself); the indicator appearing is the confirmation.
- When rbw locks itself (its `lock_timeout`), the toggle turns off and tells you, so nothing ever asks for your password unprompted.
- Everything the indicator does is also a command: `secrets on`, `secrets off`, `secrets toggle`, `secrets status`.

## Install

Requires Omarchy with its Quickshell bar, bash as your shell, and [mise](https://mise.jdx.dev) or another way to install fnox.

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

1. offers to install `rbw` and `pinentry` (`omarchy pkg add`) and fnox (`mise use -g fnox`);
2. links the `secrets` command into `~/.local/bin`;
3. points rbw at Omarchy's password card (`bin/pinentry-omarchy`) and asks for your Bitwarden email if rbw has none;
4. adds one marked line to `~/.bashrc` that loads `shell/secrets.bash`;
5. creates `~/.config/fnox/config.toml` from `examples/fnox.toml` if you have none;
6. puts the indicator in the bar's center, before Omarchy's indicators.

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

The config holds only item names, never values, so it can live in a public dotfiles repo.

## Security model

- **On disk:** only rbw's encrypted vault copy. No `BW_SESSION`, no plaintext.
- **In memory:** the vault key in `rbw-agent` and resolved values in the fnox daemon, both dropped by `secrets off` or rbw's timeout.
- **While on, any program running as you can read the secrets.** That is the point (agents and CLIs need them), but it also means a misbehaving agent can. Keep write-capable tokens out of shells with `env = "exec"` in the fnox config; they are then only available through `fnox exec -- <command>`.
- Programs started while secrets were on keep their copy of the environment after you turn them off. Restart them to drop it.
- `fnox get` or `fnox exec` while off asks for the password, because rbw unlocks on demand.
- Apps launched from the launcher (not a terminal) never get the secrets.
- **The password card:** rbw runs `bin/pinentry-omarchy`, which creates a FIFO in a fresh `0700` directory under `$XDG_RUNTIME_DIR` (a tmpfs) and asks the shell over IPC to show the card. The shell writes the answer into that FIFO through a pipe, so the password never reaches disk, a command line, or the environment, and the directory is removed straight after. The shell only writes to FIFOs at that exact location. Like any desktop prompt, it trusts other programs running as you.

## How it works

```
(x) in the bar ──► bin/secrets on ──► rbw unlock ──► fnox cache warm
                                  │      │
                                  │      └─► bin/pinentry-omarchy ──IPC──► Prompt.qml (password card)
                                  │                    ▲                          │
                                  │                    └──── FIFO in $XDG_RUNTIME_DIR
                                  └─► $XDG_RUNTIME_DIR/secrets-enabled

every bash prompt ──► shell/secrets.bash: flag present? ──► fnox hook (export)
                                          flag absent?  ──► fnox deactivate (unset)
```

The flag lives in `$XDG_RUNTIME_DIR` (a tmpfs), which is why every login starts off. The widget polls `secrets status --json` every 4 seconds, so changes made from a terminal show up in the bar.

The card is the plugin's service (`Prompt.qml`), so it answers every rbw prompt, not only the bar's: `rbw unlock` in a terminal, or `fnox exec` while off, get the same card. Without the shell (a TTY, SSH) the pinentry hands the question to the system `pinentry` instead.

### Why rbw

rbw keeps the vault key in a small agent, locks itself after `lock_timeout`, and asks for the password through any pinentry, which is what lets Omarchy draw the prompt. The official `bw` CLI needs a `BW_SESSION` token kept in the environment or a file and is slow to start, and Bitwarden Secrets Manager (`bws`) is a separate product for machine tokens, with its own access token to store. rbw is an unofficial client, so it lags new Bitwarden login methods (passkey-only accounts, for example).

## Update and uninstall

```sh
omarchy plugin update chickymonkeys.secrets && omarchy restart shell
~/.config/omarchy/plugins/chickymonkeys.secrets/install.sh --uninstall
```

The shell has to restart to load a changed widget; `install.sh` does that on updates from a checkout. Uninstalling keeps your fnox config and rbw login.

## Develop

```sh
git clone https://github.com/chickymonkeys/omarchy-secrets && cd omarchy-secrets
./install.sh --link    # the plugin folder becomes a symlink to this checkout
omarchy restart shell  # after QML changes; bin/ and shell/ changes apply at once
```

`--link` also replaces an unmodified clone made by `omarchy plugin add`.

## Troubleshooting

- **The indicator doesn't react:** `secrets on` in a terminal shows the error the widget would. "Secrets need setup" lists what `install.sh` still has to do.
- **No password card appears:** `omarchy-shell chickymonkeys.secrets pending x` should print `no`; if it errors, the indicator isn't in the bar (the card's service loads with it) or the shell needs `omarchy restart shell`.
- **A secret is missing:** `fnox get NAME` shows Bitwarden's error; item names are case-sensitive, and custom fields use `Item/Field`.

## License

MIT
