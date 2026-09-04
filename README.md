# River

River is a fast, native macOS launcher that stays out of the way. Press **Command-Shift-Space** to open it,
type what you want, and press Return. It has no Dock icon, no menu bar item, no preferences window,
and no server process.

It launches apps and files, searches the web, evaluates calculations and unit conversions, opens
Quicklinks, hands prompts to ChatGPT, and turns any executable file into a slash command.

## Install

River supports macOS 13 and newer. The installer needs Apple's command-line developer tools and
will tell you how to install them if they are missing.

```sh
curl -fsSL https://raw.githubusercontent.com/itaicoffee/river/main/install.sh | sh
```

The script downloads the public source, builds it locally with Swift, and installs the `river` CLI
at `~/.local/bin/river`. Its background process runs from a small signed app bundle under
`~/Library/Application Support/River`, giving macOS a stable identity for privacy permissions. It
never uses `sudo`. River starts immediately and a user LaunchAgent keeps it available after login.

If you prefer to inspect every step before running it:

```sh
git clone https://github.com/itaicoffee/river.git
cd river
make install
```

To update, run the one-line installer again. Your configuration and plugins are preserved.

## Use

| Input | What River does |
| --- | --- |
| Exact app name + Return | Opens the app (case-insensitive) |
| Fuzzy app name + arrows + Return | Opens the selected matching app |
| `displays`, `bluetooth`, etc. | Opens the matching native System Settings pane |
| `'filename` | Fuzzy-searches indexed files and folders; Return opens one, Shift-Return reveals it in Finder |
| `2 + 3 * 4` | Shows the answer live; Return copies it |
| `15% of 80` | Calculates percentages |
| `10 km in mi` | Converts common units |
| `define word` | Autocompletes and defines words with AHD; Return opens the AHD entry |
| `emoji heart` | Fuzzy-matches emoji names; arrows choose one and Return copies it |
| Quicklink name + query | Opens a configured URL or local path |
| `ai anything` | Opens the query in ChatGPT Chat |
| `work anything` | Opens the query in ChatGPT Work |
| `stock AAPL` | Shows a live market quote as you type; Return opens it |
| `lk anything` | Opens Google's “I'm Feeling Lucky” destination |
| Anything else | Searches with the configured browser and search engine |
| `>` or `> settings` | Browses or filters the command center |
| `/` or `/we` | Lists all plugins or filters them by name |
| `/weather`, `/rain`, `/uv`, `/watts` | Runs one of River's bundled example plugins |
| `river settings` | Opens the live config in Terminal with `nvim` |
| `river restart` | Restarts the background launcher |
| `restart` | Restarts the Mac |
| `shut down` | Shuts down the Mac |
| `lock` | Locks the screen |

Use the arrow keys to choose a result, Return to open it, and Escape to close River. While River is
open, Command-Plus and Command-Minus resize the launcher and status-plugin panel together and save
the new size to the config. Clicking elsewhere also hides it.

## How it works

River is a small Swift executable built directly on AppKit, Carbon, and Core Services:

1. A per-user LaunchAgent runs `river run` at login. The app uses AppKit's accessory activation
   policy, so it has a window but no Dock or menu bar presence.
2. Carbon registers the global hotkey. Pressing it shows a native `NSPanel` and focuses its text
   field.
3. As you type, River resolves local actions in priority order: commands, calculations, Quicklinks,
   applications, native System Settings panes, indexed files, definitions, and plugins. A remaining
   query becomes a browser search when you press Return.
4. File search uses a persisted local index with fuzzy basename and path-token matching, then merges
   any available Spotlight candidates. River remembers recent selections for four weeks so repeated
   queries put the result you actually use first.
5. Configuration is polled and reloaded live. Plugins are discovered from their directory each time
   they are needed. Scheduled status plugins refresh independently and publish cached output, so
   opening River never waits for a script or network request.

There are no third-party Swift dependencies. The release binary links only to macOS frameworks.

## Configuration

River creates `~/.config/river/config` on first install and applies changes without a restart:

```ini
hotkey = cmd+shift+space
text_size = 24
search_url = https://www.google.com/search?q={query}
lucky_url = https://www.google.com/search?btnI=1&q={query}
plugin_dir = ~/.config/river/plugins
plugin_timeout_ms = 5000
max_file_results = 5
# quicklink.github = https://github.com/search?q={query}
# quicklink.project = ~/Documents/code/project
```

Supported hotkey keys are letters, digits, and `space`; modifiers are `ctrl`, `cmd`, `opt`, and
`shift`. `text_size` accepts 12 through 48 and proportionally scales all text and geometry in both
River panels. Web links open in the default browser configured in macOS.

### Quicklinks

Add a command name after `quicklink.`:

```ini
quicklink.github = https://github.com/search?q={query}
quicklink.project = ~/Documents/code/project
```

`github swift appkit` opens the first URL with the query safely encoded. `project` opens the local
folder. Names can contain letters, digits, `_`, and `-`. A destination containing `{query}` requires
a query; other destinations open directly.

### Command center

Type `>` to browse River actions, input modes, configured Quicklinks, and installed plugins. Keep
typing to filter the list, then choose an item with the arrow keys and Return. Immediate actions
such as settings open directly; Ask ChatGPT, Search Files, and query-based Quicklinks complete the
appropriate prefix so you can type their argument.

### Calculator

Arithmetic supports parentheses, `+`, `-`, `*`, `/`, `^`, percentages, and `sqrt`, `abs`, `sin`,
`cos`, `tan`, `ln`, and `log`. Unit conversion uses `in` or `to`, such as `10 km in mi` or
`32 f to c`. Length, mass, time, decimal and binary storage, and temperature units work offline.

### Plugins

Every executable file in `~/.config/river/plugins` becomes a slash command. Its filename is the
command name, arguments are passed directly, and stdout is shown in River. No registration or
rebuild is needed.

For example, create `~/.config/river/plugins/hello`:

```zsh
#!/bin/zsh
print "hello ${1:-world}"
```

Then make it executable:

```sh
chmod +x ~/.config/river/plugins/hello
```

Typing `/hello friend` now displays `hello friend`. The installer seeds `weather`, `rain`, `uv`, and
`watts` the same way and never overwrites a plugin you edit. Weather, Rain, and UV use macOS Core
Location and Open-Meteo for your current coordinates, while watts reads the power-adapter
information published by macOS. Rain shows today's next start time and intensity or duration; when
today is dry, it shows the next rainy weekday. The installer also schedules these four plugins for
the status rectangle by default.

### Status plugins

Add a refresh interval to an executable plugin's filename to turn it into a status plugin:

```text
weather.10m.zsh
rain.15m.zsh
stocks.30s.sh
watts.10s.zsh
uv.15m.zsh
```

River runs these scripts continuously in the background and shows their cached output as individual
rows in a fixed rectangle at the active display's top-left. Opening River only reads the cache, so
even network-backed values appear immediately. Intervals use `s`, `m`, `h`, or `d`, have a
five-second minimum, and may
appear before an optional file extension. Numeric prefixes such as `010-weather.10m.zsh` control
display order without becoming part of the placeholder name.

Each refresh captures the first non-empty line of stdout. Runs never overlap for the same plugin,
at most two status plugins execute concurrently, and the existing `plugin_timeout_ms` setting also
applies to them. When a refresh fails or times out, River keeps showing the last successful value.
Status plugins are rescanned live and are not exposed as slash commands.

## Privacy and security

River has no telemetry and no River-operated service. Configuration, plugins, and learned rankings
stay under `~/.config/river`; the ranking database is written with user-only permissions. Normal app
launching, file search, calculations, unit conversions, and power status are local.

Network requests happen only when an action needs them: web and Lucky searches go to the configured
search engine, `ai` and `work` open ChatGPT, stock quotes come from Yahoo Finance, definitions come
from the American Heritage Dictionary, and the bundled weather/rain/UV plugins call Open-Meteo with
coordinates from Core Location. Status plugins run on
their filename schedule even while River is hidden. Plugins are programs on your machine and run
with your user permissions, so only install plugins you trust.

The one-line installer is provided for convenience. It builds the public source locally and does
not elevate privileges. If piping a script into a shell is not your style, use the inspectable Git
clone instructions above.

## Commands

```text
river run        Run the launcher in the foreground
river install    Install and start this build
river restart    Restart the installed LaunchAgent
river uninstall  Remove the binary and LaunchAgent
river config     Print the active config path
river search-diagnose code
                 Print local file-search results and elapsed time
```

`river uninstall` keeps your config, learned rankings, and plugins. Remove `~/.config/river` yourself
if you also want to delete that data.

## Development

```sh
swift test
swift run river run
```

`make install` creates a release build and installs it for the current user. Configuration and
executable plugins reload live; Swift source changes require another build and install.

Contributions and bug reports are welcome. Keep changes focused, add tests for behavior, and run
`swift test` before opening a pull request.

## License

River is open source under the [MIT License](LICENSE).
