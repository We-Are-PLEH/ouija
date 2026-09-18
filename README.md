# Ouija

> It points at the pane that's calling you.

Native macOS notifications when a [herdr](https://herdr.dev) agent blocks for your input or finishes
its turn. **Clicking one lands you on the exact pane** — not on the tab, not on the window.

## Why this exists

The stack here is `terminal → tab → herdr client → workspace → tab → pane → agent`. No native path
reaches the pane:

- `osascript -e 'display notification …'` takes no click handler at all, and macOS attributes it to
  Script Editor, so clicking one opens an empty folder.
- Terminal notifications (OSC 9 / OSC 777, which Ghostty forwards natively) reach **the tab**. A
  terminal cannot see inside a multiplexer, and no escape sequence can say "…and then focus pane
  `w1:pD`".
- A terminal only notifies about what a program emits. An agent that emits nothing — a stuck worker,
  a CLI without notification support — never notifies at all.

Ouija watches herdr's own state machine instead, so it covers every agent herdr recognizes, and it
owns the click, so the click can do the two hops a notification needs.

## How it works

```
launchd  com.wearepleh.ouija
   └── Ouija.app (LSUIElement, no Dock icon)
         ├── Watcher    herdr api snapshot per session → transitions via state_change_seq
         ├── Notifier   UNUserNotificationCenter, threadIdentifier = <session>|<pane>
         └── click ─────► bin/ouija-focus --session <s> --pane <p>
                             1. HERDR_SOCKET_PATH=… herdr agent focus <pane>
                             2. AppleScript: select tab + focus (focused terminal of t)
```

Focusing lives in a separate script on purpose: it can be tested and fixed without recompiling, and
whatever verifies that the jump worked is not the same artifact that performed it.

herdr reports five agent states; two of them notify by default:

| State | Means | Notifies |
|---|---|---|
| `blocked` | waiting on a permission prompt, a dialog, or your input | yes |
| `done` | turn finished | yes |
| `idle` / `working` / `unknown` | — | no |

Three things keep it honest. A notification is suppressed while you are already looking at that pane
(the pane holds focus inside herdr **and** the terminal is the frontmost app); a state must last
`minStateSeconds` before it is announced, so a permission prompt you answer in three seconds never
makes a sound; and a notification is **withdrawn** as soon as its pane leaves the state that raised
it. A stale "needs your input" sitting in Notification Center is worse than no notification at all —
it sends you to look at something that carried on without you.

## Requirements

macOS 13+, Xcode Command Line Tools (for `swiftc`), `herdr` on `PATH`, and a terminal whose tabs can
be driven by AppleScript. Ghostty is the reference; `bin/ouija-focus` is small and self-contained if
you need to teach it another one.

## Install

```sh
bin/build.sh      # builds build/Ouija.app and ad-hoc signs it
bin/install.sh    # copies to ~/Library/Application Support/Ouija/ and loads the LaunchAgent
bin/uninstall.sh  # removes both
```

`install.sh` also copies the `ouija` CLI to `~/.local/bin/`, so cron jobs and LaunchAgents can send
notifications without knowing where this repo lives.

The app is installed **outside** the repo: launchd cannot read every path (cloud-synced folders,
external volumes) and the repo may move.

There is deliberately no Makefile: macOS ships GNU make 3.81, which has no `.RECIPEPREFIX`, and a
plain script reads better than a recipe held together by invisible tabs.

On first launch macOS asks for notification permission, and on the first click, for Automation
permission to drive the terminal. Ad-hoc signing changes the signature on every build, so the
Automation prompt can come back after a reinstall.

## Configuration

`~/.config/ouija/config.json` — every key optional; see `config/config.example.json`.

| Key | Default | What it does |
|---|---|---|
| `pollSeconds` | `1.5` | how often herdr is sampled |
| `notifyStates` | `["blocked","done"]` | which states notify |
| `minStateSeconds` | `{"blocked":5,"done":0}` | how long a state must hold before it is announced |
| `sounds` | `{"blocked":"Ping","done":"Glass"}` | per state; a name from `/System/Library/Sounds`, no extension |
| `templates` | see below | notification text per state |
| `startupGraceSeconds` | `5` | quiet window after launch, so the first sample doesn't fire a burst |
| `terminalBundleID` | `com.mitchellh.ghostty` | which frontmost app counts as "you're already looking at it" |
| `agentIcons` | `{}` | per-agent image attached to the notification, e.g. `{"claude": "~/icons/claude.png"}` |
| `replyEnabled` | `true` | show a text field on agent notifications |
| `replyButtonTitle` | `"Responder"` | label of that field's send button |
| `focusScript` | the bundled one | alternative path to `ouija-focus` |
| `herdrPath` | autodetected | path to `herdr` when launchd's `PATH` doesn't reach it |

Templates take `{title}` `{agent}` `{session}` `{pane}` `{tab}` `{workspace}` `{project}` `{cwd}`
`{status}`, where `{title}` is the pane's own title and `{project}` the basename of its working
directory:

```json
"templates": {
  "blocked": { "title": "{title}", "subtitle": "{agent} · {session}", "body": "Necesita tu input" },
  "done":    { "title": "{title}", "subtitle": "{agent} · {session}", "body": "Turno terminado" }
}
```

No session name and no tab id appear anywhere in the code: sessions come from
`herdr session list --json`, tabs from `~/.config/herdr/ghostty-tab-map.json`.

### Icons

Two different things. The **app icon** (`Resources/AppIcon.icns`, rebuilt from `icon-source.png` with
`bin/make-icon.sh`) is what macOS puts next to the app name on every notification — the identity of
the sender. The **attachment** is a thumbnail on the right, set per agent through `agentIcons`, so a
glance tells you whether it was Claude, Codex or a stuck worker.

`agentIcons` ships empty and no third-party logo is distributed here: point it at your own files.
The image is copied before it is attached, because `UNNotificationAttachment` *moves* the file you
hand it into its own store — attaching an original would take it out of wherever it lives.

## Replying without leaving what you're doing

Agent notifications carry a text field. What you type is sent with `herdr agent prompt`, so you can
answer a finished agent without switching tabs.

It does **not** answer permission dialogs. Those need keystrokes, and approving something you have
not read is a bad idea — go to the pane and read it. Set `"replyEnabled": false` to remove the field.

## Notifications from your own scripts

```sh
ouija send --title "daily audit" --body "3 repos need a look" --open ~/.cache/audit/
ouija send --title "Worker stuck" --session my-workers --pane w1:p3 --icon ~/icons/codex.png
```

Under launchd or cron, call it by absolute path — `$HOME/.local/bin/ouija` — since neither inherits
your shell's `PATH`.

With `--open` the click opens a path or a URL; with `--session`/`--pane`, it goes to the pane. This
is the replacement for `osascript -e 'display notification …'` in cron jobs and LaunchAgents.

## Troubleshooting

```sh
tail -f ~/Library/Logs/Ouija/ouija.log
launchctl print "gui/$(id -u)/com.wearepleh.ouija" | grep -E 'state|pid|last exit'
bin/ouija-focus --session <session> --pane <pane> -v   # the focus jump, by hand
```

If the click lands nowhere, check whether the tab id in `ghostty-tab-map.json` is still alive: that
file is refreshed on a timer and can lag. `ouija-focus` falls back to finding the tab by name, and
then to just activating the terminal.

Nothing appears at all? Confirm the app has notification permission in System Settings, and that a
Focus mode isn't routing it silently to Notification Center. Granting permission later needs no
restart: while it is denied, Ouija rechecks every 30 seconds and logs the moment it is granted.

The log records what the click did, so "it didn't take me anywhere" and "I mis-clicked" are
distinguishable:

```
00:10:56  INFO  clic: foco a default w3:p1C
00:11:18  INFO  prompt enviado a default w3:p12
00:11:18  INFO  retirado el aviso de default|w3:p12: ya no describe la realidad
```

## License

MIT. See [LICENSE](LICENSE).
