#!/usr/bin/env bash
# Chromium only accepts the DevTools socket on loopback, so socat publishes it.
set -eu

public_port="${HELIUM_PUBLIC_PORT:-9222}"
debug_port="${HELIUM_DEBUG_PORT:-9223}"
ublock_id="blockjmkbacgjkknlgpkjjiijinjdanf"
filters_file="${HELIUM_UBLOCK_FILTERS:-/etc/helium/ublock/user-filters.txt}"
lists_file="${HELIUM_UBLOCK_LISTS:-/etc/helium/ublock/filter-lists.txt}"
default_lists_file="${HELIUM_DEFAULT_LISTS:?HELIUM_DEFAULT_LISTS is required}"

# Skip blank lines and comments.
lines_to_json() {
  local file=$1 line first=1
  printf '['
  while IFS= read -r line || [ -n "$line" ]; do
    line=${line%$'\r'}
    line=${line#"${line%%[![:space:]]*}"}
    case "$line" in
      "" | "#"*) continue ;;
    esac
    [ "$first" -eq 1 ] || printf ','
    first=0
    line=${line//\\/\\\\}
    line=${line//\"/\\\"}
    printf '"%s"' "$line"
  done < "$file"
  printf ']'
}

lists_source=""
[ -s "$lists_file" ] && lists_source=$lists_file
[ -z "$lists_source" ] && [ -s "$default_lists_file" ] && lists_source=$default_lists_file

if [ -s "$filters_file" ] || [ -n "$lists_source" ]; then
  mkdir -p /etc/chromium/policies/managed
  {
    printf '{"3rdparty":{"extensions":{"%s":{"toOverwrite":{' "$ublock_id"
    if [ -s "$filters_file" ]; then
      printf '"filters":%s' "$(lines_to_json "$filters_file")"
    fi
    if [ -n "$lists_source" ]; then
      [ -s "$filters_file" ] && printf ','
      printf '"filterLists":%s' "$(lines_to_json "$lists_source")"
    fi
    printf '}}}}}\n'
  } >/etc/chromium/policies/managed/ublock.json
fi

socat TCP4-LISTEN:"${public_port}",fork,reuseaddr,bind=0.0.0.0 TCP4:127.0.0.1:"${debug_port}" &
mkdir -p /tmp/helium-profile

exec helium \
  --headless=new \
  --no-sandbox \
  --disable-dev-shm-usage \
  --disable-gpu \
  --use-gl=angle \
  --use-angle=swiftshader \
  --enable-unsafe-swiftshader \
  --remote-debugging-port="${debug_port}" \
  --remote-allow-origins=* \
  --user-data-dir=/tmp/helium-profile \
  --no-first-run \
  --no-default-browser-check \
  --disable-sync \
  --disable-component-update \
  --disable-breakpad \
  --mute-audio \
  --hide-scrollbars \
  --window-size=1280,720 \
  --ozone-override-screen-size=1280,720 \
  "$@"
