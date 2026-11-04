#!/usr/bin/env bash
# Regenerate every package: runic over rune.yml, then the post-processing rules.
# RUNIC is the runic binary; GLYCIN_INCLUDE is the folder holding glycin-2/ and glycin-gtk4-2/,
# amber-glycin-dev's headers (/usr/lib/amber-glycin/include), and GTK_INCLUDE the one holding
# gtk-4.0/, amber-gtk4-dev's (/usr/lib/amber-gtk4/include). make generate passes all three.
set -euo pipefail

runic=${RUNIC:?RUNIC is not set}
cd "$(dirname "$0")/.."
mkdir -p build
# build/sys holds links to the system header folders the rune files name, and nothing more: a
# link to / would lead every tool that follows links (an indexer, rg -L) through the whole disk.
# rm removes build/sys itself when it is a link, never what the link points to.
rm -rf build/sys
sys_dirs=(usr/include usr/lib/x86_64-linux-gnu/glib-2.0/include
	usr/lib/x86_64-linux-gnu/graphene-1.0/include)
for d in "${sys_dirs[@]}"; do
	mkdir -p "build/sys/${d%/*}"
	ln -s "/$d" "build/sys/$d"
done
glycin_include=${GLYCIN_INCLUDE:?GLYCIN_INCLUDE is not set}
gtk_include=${GTK_INCLUDE:?GTK_INCLUDE is not set}
for h in "$glycin_include/glycin-2/glycin.h:amber-glycin-dev" "$gtk_include/gtk-4.0/gtk/gtk.h:amber-gtk4-dev"; do
	test -f "${h%:*}" || {
		echo "generate: ${h%:*} not found: install ${h##*:} (make init-packages)" >&2
		exit 2
	}
done
ln -sfn "$(cd "$glycin_include" && pwd)" build/glycin # amber-glycin-dev's headers
ln -sfn "$(cd "$gtk_include" && pwd)" build/gtk4      # amber-gtk4-dev's GTK headers

packages=(glycin glycin_gtk4)
for p in "${packages[@]}"; do
	echo "== generate $p =="
	rm -f "$p/$p.odin"
	(cd "$p" && env -u DISPLAY -u WAYLAND_DISPLAY "$runic" rune.yml)
	scripts/postprocess.sh "$p"
done
