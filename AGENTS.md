# Development instructions

- After changing Swift source code or `Package.swift`, run `swift test` and then `make install` before reporting the work complete. This ensures the running launcher uses the newly built code.
- `river restart` only restarts the binary already installed at `~/.local/bin/river`; it does not build or install source changes.
- Changes to River's config or executable plugins are loaded live and do not require a rebuild, reinstall, or restart.
