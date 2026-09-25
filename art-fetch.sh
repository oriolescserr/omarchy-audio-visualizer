#!/usr/bin/bash
# Reads one MPRIS artwork URL on stdin and prints the path of a validated local
# copy, or nothing when the artwork is rejected. Accepts https, file and base64
# data URLs; caps the transfer size, the image type and the pixel dimensions.
set -u
umask 077

[[ -n ${XDG_RUNTIME_DIR:-} && -d $XDG_RUNTIME_DIR ]] || exit 0
dir="$XDG_RUNTIME_DIR/oriolus-audio-visualizer"
/usr/bin/mkdir -p -m 700 -- "$dir" || exit 0
[[ -O $dir && ! -L $dir ]] || exit 0

max_bytes=4194304 # 4 MiB
max_side=4096

url=$(/usr/bin/head -c 6000000)
tmp=$(/usr/bin/mktemp -p "$dir" fetch.XXXXXXXX) || exit 0
trap '/usr/bin/rm -f -- "$tmp"' EXIT

case $url in
  https://*)
    /usr/bin/curl --silent --fail --location --max-redirs 3 \
      --proto '=https' --proto-redir '=https' \
      --connect-timeout 5 --max-time 10 --max-filesize "$max_bytes" \
      --output "$tmp" "$url" || exit 0
    ;;
  file://*)
    path=${url#file://}
    path=$(printf '%b' "${path//%/\\x}")
    [[ -f $path ]] || exit 0
    /usr/bin/head -c "$((max_bytes + 1))" -- "$path" >"$tmp" || exit 0
    ;;
  data:image/*\;base64,*)
    printf '%s' "${url#*,}" | /usr/bin/base64 -d 2>/dev/null | /usr/bin/head -c "$((max_bytes + 1))" >"$tmp"
    ;;
  *)
    exit 0
    ;;
esac

size=$(/usr/bin/stat -c %s -- "$tmp") || exit 0
((size > 0 && size <= max_bytes)) || exit 0

info=$(/usr/bin/file -b -- "$tmp")
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

final="$dir/art-$(/usr/bin/date +%s%N).$ext"
/usr/bin/mv -f -- "$tmp" "$final" || exit 0
trap - EXIT

# Keep only the newest copy.
for old in "$dir"/art-*; do
  [[ $old == "$final" ]] || /usr/bin/rm -f -- "$old"
done

printf '%s\n' "$final"
