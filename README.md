# River

A tiny, dark, native macOS launcher. It has no Dock icon, no menu bar item, no runtime dependencies, and no preferences UI.

Press **Control-F** to show or hide it. Clicking elsewhere hides it too.

## Install

Requires macOS 13 or newer and Apple's command-line developer tools.

```sh
make install
```

That builds one release binary at `~/.local/bin/river`, starts it immediately, and creates a LaunchAgent so it starts at login after a Mac restart.

To remove the launcher while keeping your config and plugins:

```sh
make uninstall
```

## Use

| Input | What happens |
| --- | --- |
| `anything` + Return | Google search in Chrome |
| `lk anything` + Return | Google's “I'm Feeling Lucky” destination, opened directly |
| `'filename` | Fast Spotlight file results; arrows + Return open one |
| `define word` | Definition appears live; Return opens Dictionary |
| `/uv` | Current-location UV index appears live |
| `/weather` | Current-location Celsius temperature appears live |
| `/watts` | Connected charger's rated wattage, when macOS exposes it |
| `/` | Lists installed plugins |

UV and weather use `wttr.in`, which infers location from the current public IP. `/watts` reports the adapter wattage macOS publishes; some docks and monitors only report that power is connected.

## Config

The plain text config lives at `~/.config/river/config`. River checks it twice a second and applies changes without a restart.

```ini
hotkey = ctrl+f
browser = Google Chrome
search_url = https://www.google.com/search?q={query}
lucky_url = https://www.google.com/search?btnI=1&q={query}
plugin_dir = ~/.config/river/plugins
plugin_timeout_ms = 5000
max_file_results = 5
```

Supported hotkey keys are letters, digits, and `space`; modifiers are `ctrl`, `cmd`, `opt`, and `shift`.

## Plugins

Every executable file in `~/.config/river/plugins` becomes a slash command. The filename is the command name, arguments are passed through normally, stdout is shown in the launcher, and no registration or rebuild is needed.

For example, `~/.config/river/plugins/hello`:

```zsh
#!/bin/zsh
print "hello ${1:-world}"
```

Then:

```sh
chmod +x ~/.config/river/plugins/hello
```

Typing `/hello friend` shows `hello friend` immediately. The installer seeds `uv`, `weather`, and `watts` this same way and never overwrites a plugin you edit.
