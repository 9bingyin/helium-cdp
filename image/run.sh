#!/bin/bash
# Chromium only accepts the DevTools socket on loopback, so socat publishes it.
set -eu

public_port="${HELIUM_PUBLIC_PORT:-9222}"
debug_port="${HELIUM_DEBUG_PORT:-9223}"
ublock_id="blockjmkbacgjkknlgpkjjiijinjdanf"
filters_file="${HELIUM_UBLOCK_FILTERS:-/etc/helium/ublock/user-filters.txt}"
lists_file="${HELIUM_UBLOCK_LISTS:-/etc/helium/ublock/filter-lists.txt}"
default_lists_file=/opt/helium/default-filter-lists.txt

mkdir -p /run/dbus /tmp/dbus
if [ ! -S /run/dbus/system_bus_socket ]; then
  dbus-daemon --system --fork
fi
if [ ! -S /tmp/dbus/session ]; then
  dbus-daemon --session --fork --nopidfile --address="${DBUS_SESSION_BUS_ADDRESS}"
fi

json_escape() {
  local s=$1
  s=${s//\\/\\\\}
  s=${s//\"/\\\"}
  printf '%s' "$s"
}

# Blank lines and lines starting with # are skipped.
json_string_array() {
  local file=$1
  local first=1
  local line
  printf '['
  while IFS= read -r line || [ -n "$line" ]; do
    line=${line%$'\r'}
    case "$line" in
      ""|"#"*|[[:space:]]"#"*) continue ;;
    esac
    case "$line" in
      [[:space:]]*) line=${line#"${line%%[![:space:]]*}"} ;;
    esac
    [ -z "$line" ] && continue
    if [ "$first" -eq 0 ]; then
      printf ','
    fi
    first=0
    printf '"%s"' "$(json_escape "$line")"
  done < "$file"
  printf ']'
}

write_ublock_policy() {
  local has_filters=0
  local lists_source=""
  [ -s "$filters_file" ] && has_filters=1
  if [ -s "$lists_file" ]; then
    lists_source=$lists_file
  elif [ -s "$default_lists_file" ]; then
    lists_source=$default_lists_file
  fi
  [ "$has_filters" -eq 0 ] && [ -z "$lists_source" ] && return 0

  mkdir -p /etc/chromium/policies/managed
  {
    printf '{"3rdparty":{"extensions":{"%s":{"toOverwrite":{' "$ublock_id"
    local comma=0
    if [ "$has_filters" -eq 1 ]; then
      printf '"filters":%s' "$(json_string_array "$filters_file")"
      comma=1
    fi
    if [ -n "$lists_source" ]; then
      [ "$comma" -eq 1 ] && printf ','
      printf '"filterLists":%s' "$(json_string_array "$lists_source")"
    fi
    printf '}}}}}\n'
  } > /etc/chromium/policies/managed/ublock.json
}

write_ublock_policy

socat TCP4-LISTEN:"${public_port}",fork,reuseaddr,bind=0.0.0.0 TCP4:127.0.0.1:"${debug_port}" &

mkdir -p /tmp/helium-profile/Default
# --no-first-run skips initial_preferences. An existing profile is left alone.
if [ ! -s /tmp/helium-profile/Default/Preferences ]; then
  cp /opt/helium/initial_preferences /tmp/helium-profile/Default/Preferences
fi

exec /opt/helium/helium-wrapper \
  --headless=new \
  --no-sandbox \
  --disable-dev-shm-usage \
  --disable-gpu \
  --use-gl=angle \
  --use-angle=swiftshader \
  --enable-unsafe-swiftshader \
  --remote-debugging-address=127.0.0.1 \
  --remote-debugging-port="${debug_port}" \
  --remote-allow-origins=* \
  --user-data-dir=/tmp/helium-profile \
  --no-first-run \
  --no-default-browser-check \
  --disable-sync \
  --disable-translate \
  --disable-component-update \
  --disable-breakpad \
  --mute-audio \
  --hide-scrollbars \
  --font-render-hinting=none \
  --window-size=1288,790 \
  --ozone-override-screen-size=1280,720 \
  "$@"
