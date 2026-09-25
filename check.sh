#!/usr/bin/bash
# Prepares the widget's private runtime directory and reports whether cava is
# installed. Prints "runtime=ok" when $XDG_RUNTIME_DIR and
# $XDG_RUNTIME_DIR/oriolus-audio-visualizer are owned by this user, mode 0700
# and not symlinks, and "cava=yes" when /usr/bin/cava is executable.
set -u
umask 077
export PATH=/usr/bin
exec 2>/dev/null

private_dir() {
  [[ -d $1 && ! -L $1 && -O $1 && $(stat -c %a -- "$1") == 700 ]]
}

rt=${XDG_RUNTIME_DIR:-}
dir="$rt/oriolus-audio-visualizer"
if [[ -n $rt ]] && private_dir "$rt" && mkdir -p -m 700 -- "$dir" \
  && [[ -d $dir && ! -L $dir && -O $dir ]] && chmod 700 -- "$dir"; then
  printf 'runtime=ok\n'
fi

[[ -x /usr/bin/cava ]] && printf 'cava=yes\n'
exit 0
