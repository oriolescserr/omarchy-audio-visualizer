#!/usr/bin/bash
# Reads one MPRIS artwork URL on stdin and prints the path of a validated local
# copy, or nothing when the artwork is rejected. Accepts https, file and base64
# data URLs; caps the transfer size, the image type and the pixel dimensions.
set -u -o pipefail
umask 077
# The widget starts this with a cleared environment; pinning PATH here as well
# means every tool name below resolves only in /usr/bin.
export PATH=/usr/bin
# Nothing reads this script's stderr, so it is discarded rather than left on a
# pipe. Only the final path is written to the original stdout (fd 3), so the
# widget never receives more than one short line.
exec 2>/dev/null 3>&1 1>/dev/null

# Works only inside a private runtime directory: owned by this user, mode 0700,
# not a symlink. Anything else fails closed.
private_dir() {
  [[ -d $1 && ! -L $1 && -O $1 && $(stat -c %a -- "$1") == 700 ]]
}
rt=${XDG_RUNTIME_DIR:-}
[[ -n $rt ]] && private_dir "$rt" || exit 0
dir="$rt/oriolus-audio-visualizer"
mkdir -p -m 700 -- "$dir" || exit 0
[[ -d $dir && ! -L $dir && -O $dir ]] && chmod 700 -- "$dir" || exit 0

max_bytes=4194304 # 4 MiB
max_side=4096

# Each widget instance (one per monitor) tags its files so it only replaces its own.
tag=${ART_TAG:-w}
[[ $tag =~ ^[a-z0-9]{1,16}$ ]] || exit 0

# True for addresses that are not on the public internet: loopback, private,
# link-local, carrier-grade NAT, documentation, benchmarking, multicast and
# reserved IPv4 ranges. For IPv6 only global unicast (2000::/3) is public,
# minus documentation, 6to4 and Teredo, which can embed other addresses.
non_public() {
  local ip=${1,,}
  [[ $ip == ::ffff:* ]] && ip=${ip#::ffff:}
  if [[ $ip =~ ^([0-9]{1,3})\.([0-9]{1,3})\.([0-9]{1,3})\.([0-9]{1,3})$ ]]; then
    local a=$((10#${BASH_REMATCH[1]})) b=$((10#${BASH_REMATCH[2]})) c=$((10#${BASH_REMATCH[3]}))
    ((a == 0 || a == 10 || a == 127 || a >= 224)) && return 0
    ((a == 100 && b >= 64 && b <= 127)) && return 0
    ((a == 169 && b == 254)) && return 0
    ((a == 172 && b >= 16 && b <= 31)) && return 0
    ((a == 192 && b == 0 && (c == 0 || c == 2))) && return 0
    ((a == 192 && b == 88 && c == 99)) && return 0
    ((a == 192 && b == 168)) && return 0
    ((a == 198 && (b == 18 || b == 19))) && return 0
    ((a == 198 && b == 51 && c == 100)) && return 0
    ((a == 203 && b == 0 && c == 113)) && return 0
    return 1
  fi
  [[ $ip =~ ^[23][0-9a-f]{0,3}: ]] || return 0
  [[ $ip == 2001:db8:* || $ip == 2001:0db8:* || $ip == 2002:* || $ip == 2001:0:* || $ip == 2001:0000:* ]] && return 0
  return 1
}

url=$(head -c 6000000)
tmp=$(mktemp -p "$dir" fetch.XXXXXXXX) || exit 0
trap 'rm -f -- "$tmp"' EXIT
trap 'exit 1' TERM INT HUP

case $url in
  https://*)
    # Plain host names only (no credentials, no IPv6 literals). The host is
    # resolved once, must be a public address, and curl is pinned to it, so a
    # player cannot point the fetch at the local machine or network.
    [[ $url =~ ^https://([A-Za-z0-9.-]+)(:([0-9]{1,5}))?([/?#].*)?$ ]] || exit 0
    host=${BASH_REMATCH[1]} port=${BASH_REMATCH[3]:-443}
    ip=$(getent ahostsv4 "$host" | head -n 1 | cut -d ' ' -f 1)
    [[ -n $ip ]] || ip=$(getent ahostsv6 "$host" | head -n 1 | cut -d ' ' -f 1)
    [[ -n $ip ]] && ! non_public "$ip" || exit 0
    [[ $ip == *:* ]] && pinned="[$ip]" || pinned=$ip
    # --disable must come first: it keeps ~/.curlrc from changing these limits.
    # --globoff stops [] and {} in the URL from expanding into many requests.
    # Redirects are not followed, since their targets would not be checked.
    # head enforces the byte cap while data arrives, whatever the server
    # declares; on overflow curl's pipe closes and the size check below rejects.
    curl --disable --globoff --silent --fail --max-redirs 0 \
      --proto '=https' --resolve "$host:$port:$pinned" \
      --connect-timeout 5 --max-time 10 --max-filesize "$max_bytes" \
      "$url" | head -c "$((max_bytes + 1))" >"$tmp" || exit 0
    ;;
  file://*)
    # Percent-decode only; any backslash is rejected first so printf cannot
    # interpret it as an escape. Pseudo-filesystems are never read.
    path=${url#file://}
    [[ $path == /* && $path != *\\* ]] || exit 0
    path=$(printf '%b' "${path//%/\\x}")
    path=$(realpath -e -- "$path") || exit 0
    case $path in /proc/* | /sys/* | /dev/*) exit 0 ;; esac
    [[ -f $path ]] || exit 0
    head -c "$((max_bytes + 1))" -- "$path" >"$tmp" || exit 0
    ;;
  data:image/*\;base64,*)
    printf '%s' "${url#*,}" | base64 -d 2>/dev/null | head -c "$((max_bytes + 1))" >"$tmp"
    ;;
  *)
    exit 0
    ;;
esac

size=$(stat -c %s -- "$tmp") || exit 0
((size > 0 && size <= max_bytes)) || exit 0

info=$(file -b -- "$tmp")
case $info in
  "JPEG image data"*) ext=jpg ;;
  "PNG image data"*) ext=png ;;
  "RIFF (little-endian) data, WebP image"* | "RIFF (little-endian) data, Web/P image"*) ext=webp ;;
  *) exit 0 ;;
esac

# `file` reports the pixel size as "W x H" or "WxH"; for JPEG it is the last match.
re='([0-9]+) ?x ?([0-9]+)'
w=0 h=0 rest=$info
while [[ $rest =~ $re ]]; do
  w=${BASH_REMATCH[1]} h=${BASH_REMATCH[2]}
  rest=${rest#*"${BASH_REMATCH[0]}"}
done
((${#w} <= 5 && ${#h} <= 5)) || exit 0
((10#$w > 0 && 10#$h > 0 && 10#$w <= max_side && 10#$h <= max_side)) || exit 0

final="$dir/art-$tag-$(date +%s%N).$ext"
mv -f -- "$tmp" "$final" || exit 0
trap - EXIT

# Keep this instance's 10 newest copies (the widget remembers the same 10), and
# drop copies left behind by instances that no longer exist. Names sort by time.
own=("$dir"/art-"$tag"-*)
for ((i = 0; i < ${#own[@]} - 10; i++)); do
  rm -f -- "${own[i]}"
done
find "$dir" -maxdepth 1 -type f -name 'art-*' ! -name "art-$tag-*" -mmin +60 -delete 2>/dev/null

printf '%s\n' "$final" >&3
