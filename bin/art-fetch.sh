#!/usr/bin/bash
# Reads one MPRIS artwork URL on stdin and prints the path of a validated local
# copy, or nothing when the artwork is rejected. Accepts https, file and base64
# data URLs; caps the transfer size, the image type and the pixel dimensions.
# A PNG is rewritten to the chunks that draw it. Compressed text and ICC
# profiles are dropped without being inflated, because the shell's decoder
# expands those before it scales the image.
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

# Print the big-endian uint32 at byte offset $2 of file $1.
read_be32() {
  local hex
  hex=$(LC_ALL=C od -An -N 4 -j "$2" -t x1 -- "$1" | LC_ALL=C tr -d '[:space:]') || return 1
  [[ $hex =~ ^[0-9a-f]{8}$ ]] || return 1
  printf '%d\n' "$((16#$hex))"
}

# Rewrite $tmp as a PNG that contains only the chunks needed to draw it, and set
# w and h from its IHDR. zTXt, iTXt, iCCP and every other ancillary chunk are
# skipped, not inflated. Pixel dimensions are the IHDR fields, capped by
# max_side. More than 4096 chunks is rejected: a real image stays well under
# that even when its pixel data is split into small IDAT pieces.
sanitize_png() {
  local out sig typ
  out=$(mktemp -p "$dir" png.XXXXXXXX) || return 1
  png_out=$out
  if ! LC_ALL=C gawk -b -v max_side="$max_side" -v max_bytes="$max_bytes" -v dst="$out" -f - -- "$tmp" <<'AWK'
@load "readfile"
function byte(p) { return ord[substr(data, p, 1)] }
function be32(p) {
  return byte(p) * 16777216 + byte(p + 1) * 65536 + byte(p + 2) * 256 + byte(p + 3)
}
function letters(t,    i, c) {
  if (length(t) != 4) return 0
  for (i = 1; i <= 4; i++) {
    c = ord[substr(t, i, 1)]
    if (!((c >= 65 && c <= 90) || (c >= 97 && c <= 122))) return 0
  }
  return 1
}
function depth_ok(color, depth) {
  if (color == 0) return (depth == 1 || depth == 2 || depth == 4 || depth == 8 || depth == 16)
  if (color == 2) return (depth == 8 || depth == 16)
  if (color == 3) return (depth == 1 || depth == 2 || depth == 4 || depth == 8)
  if (color == 4 || color == 6) return (depth == 8 || depth == 16)
  return 0
}
function ancillary(t) { return and(ord[substr(t, 1, 1)], 32) }
BEGIN {
  for (i = 0; i < 256; i++) ord[sprintf("%c", i)] = i
  infile = ARGV[1]
  ARGV[1] = ""
  data = readfile(infile)
  n = length(data)
  limit = max_side + 0
  if (infile == "" || n == 0 || n > max_bytes + 0 || limit < 1) exit 1
  sig = sprintf("%c%c%c%c%c%c%c%c", 137, 80, 78, 71, 13, 10, 26, 10)
  if (substr(data, 1, 8) != sig) exit 1
  printf("%s", sig) > dst
  seen_ihdr = seen_plte = seen_idat = seen_iend = 0
  seen_trns = seen_gama = seen_chrm = seen_srgb = 0
  idat_bytes = plte_n = png_color = chunks = 0
  pos = 9
  while (pos <= n) {
    if (seen_iend) exit 1
    chunks++
    if (chunks > 4096) exit 1
    if (n - pos + 1 < 12) exit 1
    len = be32(pos)
    if (len < 0 || len > n - pos + 1 - 12) exit 1
    typ = substr(data, pos + 4, 4)
    if (!letters(typ)) exit 1
    if (pos == 9 && typ != "IHDR") exit 1
    keep = 0
    was_idat = seen_idat
    if (typ == "IHDR") {
      if (pos != 9 || seen_ihdr || len != 13) exit 1
      w = be32(pos + 8)
      h = be32(pos + 12)
      depth = byte(pos + 16)
      png_color = byte(pos + 17)
      comp = byte(pos + 18)
      filt = byte(pos + 19)
      inter = byte(pos + 20)
      if (w < 1 || h < 1 || w > limit || h > limit) exit 1
      if (comp != 0 || filt != 0 || (inter != 0 && inter != 1)) exit 1
      if (!depth_ok(png_color, depth)) exit 1
      seen_ihdr = 1
      keep = 1
    } else if (typ == "PLTE") {
      if (!seen_ihdr || seen_plte || seen_idat) exit 1
      if (len < 3 || len > 768 || len % 3 != 0) exit 1
      if (png_color != 2 && png_color != 3 && png_color != 6) exit 1
      plte_n = int(len / 3)
      seen_plte = 1
      keep = 1
    } else if (typ == "IDAT") {
      if (!seen_ihdr || seen_iend) exit 1
      if (png_color == 3 && !seen_plte) exit 1
      idat_bytes += len
      seen_idat = 1
      keep = 1
    } else if (typ == "IEND") {
      if (!seen_ihdr || !seen_idat || seen_iend || len != 0 || idat_bytes <= 0) exit 1
      if (png_color == 3 && !seen_plte) exit 1
      seen_iend = 1
      keep = 1
    } else if (typ == "tRNS") {
      if (!seen_ihdr || seen_idat || seen_trns) exit 1
      if (png_color == 0) { if (len != 2) exit 1 }
      else if (png_color == 2) { if (len != 6) exit 1 }
      else if (png_color == 3) { if (!seen_plte || len < 1 || len > plte_n) exit 1 }
      else exit 1
      seen_trns = 1
      keep = 1
    } else if (typ == "gAMA") {
      if (!seen_ihdr || seen_plte || seen_idat || seen_gama || len != 4) exit 1
      seen_gama = 1
      keep = 1
    } else if (typ == "cHRM") {
      if (!seen_ihdr || seen_plte || seen_idat || seen_chrm || len != 32) exit 1
      seen_chrm = 1
      keep = 1
    } else if (typ == "sRGB") {
      if (!seen_ihdr || seen_plte || seen_idat || seen_srgb || len != 1) exit 1
      if (byte(pos + 8) > 3) exit 1
      seen_srgb = 1
      keep = 1
    } else if (!ancillary(typ)) {
      exit 1
    }
    if (keep && was_idat && typ != "IDAT" && typ != "IEND") exit 1
    if (keep) printf("%s", substr(data, pos, 12 + len)) > dst
    pos += 12 + len
  }
  if (!seen_iend || pos != n + 1) exit 1
  if (close(dst) != 0) exit 1
  exit 0
}
AWK
  then
    rm -f -- "$png_out"
    png_out=
    return 1
  fi
  sig=$(LC_ALL=C od -An -N 8 -t x1 -- "$out" | LC_ALL=C tr -d '[:space:]') || { rm -f -- "$png_out"; png_out=; return 1; }
  typ=$(LC_ALL=C od -An -N 4 -j 12 -t x1 -- "$out" | LC_ALL=C tr -d '[:space:]') || { rm -f -- "$png_out"; png_out=; return 1; }
  [[ $sig == 89504e470d0a1a0a && $typ == 49484452 ]] || { rm -f -- "$png_out"; png_out=; return 1; }
  w=$(read_be32 "$out" 16) || { rm -f -- "$png_out"; png_out=; return 1; }
  h=$(read_be32 "$out" 20) || { rm -f -- "$png_out"; png_out=; return 1; }
  mv -f -- "$out" "$tmp" || { rm -f -- "$png_out"; png_out=; return 1; }
  png_out=
}

url=$(head -c 6000000)
tmp=$(mktemp -p "$dir" fetch.XXXXXXXX) || exit 0
png_out=
cleanup() {
  rm -f -- "$tmp"
  if [[ -n $png_out ]]; then rm -f -- "$png_out"; fi
}
trap cleanup EXIT
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

# PNG dimensions are the IHDR fields, read while the file is rewritten.
# `file` reports JPEG and WebP size as "W x H" or "WxH"; for JPEG it is the last match.
if [[ $ext == png ]]; then
  sanitize_png || exit 0
else
  re='([0-9]+) ?x ?([0-9]+)'
  w=0 h=0 rest=$info
  while [[ $rest =~ $re ]]; do
    w=${BASH_REMATCH[1]} h=${BASH_REMATCH[2]}
    rest=${rest#*"${BASH_REMATCH[0]}"}
  done
fi
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
