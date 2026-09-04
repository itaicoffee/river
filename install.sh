#!/bin/sh

set -eu

repo="${RIVER_REPO:-itaicoffee/river}"
ref="${RIVER_REF:-main}"

fail() {
  printf 'river: %s\n' "$*" >&2
  exit 1
}

[ "$(uname -s)" = "Darwin" ] || fail "River requires macOS 13 or newer"
command -v curl >/dev/null 2>&1 || fail "curl is required"
command -v xcrun >/dev/null 2>&1 || fail "install Apple's command-line tools with: xcode-select --install"
xcrun --find swift >/dev/null 2>&1 || fail "install Apple's command-line tools with: xcode-select --install"

major_version="$(sw_vers -productVersion | cut -d. -f1)"
[ "$major_version" -ge 13 ] 2>/dev/null || fail "River requires macOS 13 or newer"

work_dir="$(mktemp -d "${TMPDIR:-/tmp}/river.XXXXXX")"
trap 'rm -rf "$work_dir"' EXIT HUP INT TERM

archive_url="https://github.com/${repo}/archive/${ref}.tar.gz"
printf 'Downloading River…\n'
curl -fsSL --retry 3 "$archive_url" -o "$work_dir/river.tar.gz"
mkdir "$work_dir/source"
tar -xzf "$work_dir/river.tar.gz" -C "$work_dir/source" --strip-components=1

printf 'Building River…\n'
xcrun swift build -c release --package-path "$work_dir/source"
binary_dir="$(xcrun swift build -c release --package-path "$work_dir/source" --show-bin-path)"

printf 'Installing River…\n'
"$binary_dir/river" install

case ":${PATH:-}:" in
  *:"$HOME/.local/bin":*) ;;
  *) printf '\nAdd River to your shell PATH:\n  export PATH="$HOME/.local/bin:$PATH"\n' ;;
esac

printf '\nDone. Press Command-Shift-Space to open River.\n'
