#!/usr/bin/env bash
# Compiles every ```odin block of docs/CHEATSHEET.md, so a wrong argument list fails lint.
# cheatsheet.sh checks that the names exist; this checks that the calls type-check.
#
# Usage: scripts/cheatsheet-compile.sh [-collection:name=path]...
#
# Each section (a `##` heading with odin blocks) becomes a package build/cheatsheet/NN/ of its
# own, so the blocks of one section see each other's types, as a reader does, and nothing leaks
# between sections. Each block is a file bNN.odin in it:
#   - its `import` lines are hoisted to file level;
#   - a block of declarations only (Name :: struct, Name :: proc) stays at file level;
#   - any other block goes inside `block_NN :: proc() { ... }`;
#   - a line that is only `…` or `...` is dropped, and a `…` in code (`{ … }`) is removed;
#   - blocks in any other language (c, html, sh) are not read.
# Then `odin check -no-entry-point` runs on each package, in parallel, with the collections
# given as arguments, and an error is printed against the line of the sheet it came from.
#
# scripts/cheatsheet-compile.conf (sh, optional) holds what differs between repos:
#   SKIP_IMPORTS     import paths whose blocks are not compiled ("web:browser")
#   ASSUME_IMPORTS   imports a block may use without writing them: "core:fmt core:time", an
#                    alias as "webtest=web:testing"
#   PRELUDE          Odin source every section may use, imports included: the variables a
#                    block leaves undeclared (`path: string`), written once
#   DIRS             directories (with one file in each) made in every package, for
#                    #load_directory("static")
#   section_prelude  a function: given a section's heading ("web:htmx — answering ...") it prints
#                    Odin source for that section's package alone, after PRELUDE; for a name
#                    that means one type in one section and another in the next
#   VET_FLAGS        replaces the default flags below
#
# Default flags: -strict-style -vet-using-stmt -vet-using-param -vet-semicolon -vet-cast. Left
# out, with the reason: -vet-unused-imports and -vet-unused-variables (a sheet shows a call, not
# a program; Odin still reports a variable declared and unused inside a nested block, so those
# are written to be used), -vet-shadowing (blocks reuse names), -vet-tabs (the wrapper does not
# re-indent a block) and -vet-style (it also reports the dependencies' own style).
set -euo pipefail

sheet=${CHEATSHEET:-docs/CHEATSHEET.md}
conf=${CHEATSHEET_CONF:-scripts/cheatsheet-compile.conf}
odin=${ODIN:-odin}
out=build/cheatsheet
SKIP_IMPORTS=""
ASSUME_IMPORTS=""
PRELUDE=""
DIRS=""
VET_FLAGS="-strict-style -vet-using-stmt -vet-using-param -vet-semicolon -vet-cast"
# shellcheck source=/dev/null
[ -f "$conf" ] && . "$conf"
declare -F section_prelude > /dev/null || section_prelude() { :; }

[ -f "$sheet" ] || { echo "cheatsheet-compile: $sheet not found" >&2; exit 2; }

rm -rf "$out"
mkdir -p "$out"
printf '%s\n' "$PRELUDE" > "$out/prelude.txt"

# The awk writes bNN.odin and bNN.map (the sheet line of every line of bNN.odin) into one
# directory per section, and prints "SS first-line heading" for each section.
awk -v out="$out" -v assume="$ASSUME_IMPORTS" -v skip="$SKIP_IMPORTS" -v dirs="$DIRS" '
function trim(s) { gsub(/^[ \t]+|[ \t]+$/, "", s); return s }
# A line of bare field reads or types (`m.name; m.size`, `http.Method // …`, or the same inside
# `for x in xs { … }`) shows what is there to read; Odin refuses an expression statement, so
# each one becomes `_ = expr`.
function bare_list(code,    item, k, np, parts, out) {
	item = "[A-Za-z_][A-Za-z0-9_]*(\\.[A-Za-z_][A-Za-z0-9_]*|\\[[0-9A-Za-z_.:]*\\])+"
	if (code !~ ("^[ \t]*" item "([ \t]*[;,][ \t]*" item ")*[ \t]*;?[ \t]*$")) return ""
	np = split(code, parts, /[;,]/)
	out = ""
	for (k = 1; k <= np; k++) {
		parts[k] = trim(parts[k])
		if (parts[k] != "") out = out (out == "" ? "" : "; ") "_ = " parts[k]
	}
	return out
}
function bare(line,    idx, code, rest, ind, i, j, r) {
	idx = index(line, "//")
	code = idx ? substr(line, 1, idx - 1) : line
	rest = idx ? "  " substr(line, idx) : ""
	ind = code; sub(/[^ \t].*$/, "", ind)
	r = bare_list(code)
	if (r != "") return ind r rest
	i = index(code, "{")
	if (i == 0 || code !~ /\}[ \t]*$/) return line
	j = length(code); while (substr(code, j, 1) != "}") j--
	r = bare_list(substr(code, i + 1, j - i - 1))
	if (r == "") return line
	return substr(code, 1, i) " " r " }" substr(code, j + 1) rest
}
# An ellipsis in code (not in a string or a comment) stands for code the sheet leaves out; drop it.
function strip_ell(line,    i, c, out, q, n) {
	out = ""; q = ""; n = length(line)
	for (i = 1; i <= n; i++) {
		c = substr(line, i, 1)
		if (q != "") {
			out = out c
			if (c == "\\" && q != "`") { out = out substr(line, i + 1, 1); i++ }
			else if (c == q) q = ""
			continue
		}
		if (c == "\"" || c == "`") { q = c; out = out c; continue }
		if (c == "/" && substr(line, i + 1, 1) == "/") return out substr(line, i)
		# length("…") is 3 bytes in mawk and 1 character in gawk under a UTF-8 locale: step by whichever it is.
		if (index(substr(line, i), "…") == 1) { i += length("…") - 1; continue }
		if (substr(line, i, 3) == "..." && substr(line, i - 1, 1) !~ /[A-Za-z0-9_.]/ && substr(line, i + 3, 1) !~ /[A-Za-z0-9_.]/) { i += 2; continue }
		out = out c
	}
	return out
}
function emit(text, src) { n++; g[n] = text; m[n] = src }
function section(    dir, pre, f) {
	if (!sec_open) {
		ns++
		sec_open = 1
		sec_dir = sprintf("%s/%02d", out, ns)
		system("mkdir -p " sec_dir)
		if (dirs != "") { nd = split(dirs, dl, " "); for (di = 1; di <= nd; di++) system("mkdir -p " sec_dir "/" dl[di] " && touch " sec_dir "/" dl[di] "/keep.txt") }
		f = sec_dir "/prelude.odin"
		print "package sheet" > f
		while ((getline pre < (out "/prelude.txt")) > 0) print pre > f
		close(out "/prelude.txt"); close(f)
		printf "%02d %d %s\n", ns, first, heading > (out "/index")
	}
}
function flush(    i, t, k, path, name, alias, decl, only, nimp, imps, isrc, f, skipit, words, w, line, body, bsrc, nbody) {
	nimp = 0; decl = 0; only = 1; skipit = 0; nbody = 0
	for (i = 1; i <= nl; i++) {
		line = L[i]
		t = trim(line)
		if (t == "…" || t == "...") continue
		line = strip_ell(line)
		if (t ~ /^import[ \t]/) {
			imps[++nimp] = line; isrc[nimp] = S[i]
			path = line; sub(/^[^"]*"/, "", path); sub(/".*$/, "", path)
			name = line; sub(/^import[ \t]+/, "", name)
			if (name ~ /^[A-Za-z_][A-Za-z0-9_]*[ \t]+"/) sub(/[ \t].*$/, "", name)
			else { name = path; sub(/^.*[:\/]/, "", name) }
			have[name] = 1; iname[nimp] = name
			words = split(skip, w, " ")
			for (k = 1; k <= words; k++) if (w[k] == path) skipit = 1
			continue
		}
		line = bare(line)
		body[++nbody] = line; bsrc[nbody] = S[i]
		if (line ~ /^[A-Za-z_@]/) {
			if (line ~ /^[A-Za-z_][A-Za-z0-9_]*[ \t]*::/ || line ~ /^@\(/) decl = 1
			else only = 0
		}
	}
	if (skipit) { nskip++; delete have; return }
	nb++
	section()
	f = sprintf("%s/b%02d.odin", sec_dir, nb)
	n = 0
	emit("package sheet", S[1])
	# A block with no import of its own reads as the section it is in: the imports of the
	# blocks before it come with it.
	for (i = 1; i <= nsi; i++) {
		if (!(sec_name[i] in have)) { emit(sec_imp[i], S[1]); have[sec_name[i]] = 1 }
	}
	for (i = 1; i <= nimp; i++) emit(imps[i], isrc[i])
	words = split(assume, w, " ")
	for (k = 1; k <= words; k++) {
		path = w[k]; name = path; sub(/^.*[:\/]/, "", name)
		if (path ~ /=/) { name = path; sub(/=.*$/, "", name); sub(/^[^=]*=/, "", path); alias = name " " }
		else alias = ""
		if (!(name in have)) emit("import " alias "\"" path "\"", S[1])
	}
	for (i = 1; i <= nimp; i++) { sec_imp[++nsi] = imps[i]; sec_name[nsi] = iname[i] }
	if (decl && only) {
		for (i = 1; i <= nbody; i++) emit(body[i], bsrc[i])
	} else {
		emit(sprintf("block_%02d :: proc() {", nb), S[1])
		for (i = 1; i <= nbody; i++) emit(body[i], bsrc[i])
		emit("}", S[1])
	}
	for (i = 1; i <= n; i++) { print g[i] > f; print m[i] > (substr(f, 1, length(f) - 4) "map") }
	close(f); close(substr(f, 1, length(f) - 4) "map")
	delete have
}
/^## / { heading = substr($0, 4); sec_open = 0; nsi = 0 }
inblock && /^```[ \t]*$/ { inblock = 0; flush(); nl = 0; next }
!inblock && /^```odin[ \t]*$/ { inblock = 1; nl = 0; first = NR; next }
!inblock && /^```/ { next }
inblock { L[++nl] = $0; S[nl] = NR; next }
END { printf "%d %d\n", nb, nskip > (out "/counts") }
' "$sheet"

read -r blocks skipped < "$out/counts"
[ "$blocks" -gt 0 ] || { echo "$sheet: no odin blocks"; exit 0; }

while read -r ss _ heading; do
	section_prelude "$heading" >> "$out/$ss/prelude.odin"
done < "$out/index"

run_one() {
	local dir=$1
	shift
	if "$odin" check "$dir" -no-entry-point "$@" > "$dir/out.txt" 2>&1; then echo 0 > "$dir/rc"; else echo 1 > "$dir/rc"; fi
}
export -f run_one
export odin

# shellcheck disable=SC2086
find "$out" -mindepth 1 -maxdepth 1 -type d | sort |
	xargs -P "$(nproc)" -I{} bash -c 'run_one "$@"' _ {} "$@" $VET_FLAGS

while read -r ss _ heading; do
	dir=$out/$ss
	[ "$(cat "$dir/rc")" = 0 ] && continue
	echo "$sheet: section \"$heading\" does not compile:"
	# Rewrite path/bNN.odin(L:C) to the sheet line it was written from.
	awk -v dir="$dir" -v sheet="$sheet" '
		{
			while (match($0, /[^ \t]*b[0-9][0-9]\.odin\([0-9]+:[0-9]+\)/)) {
				tok = substr($0, RSTART, RLENGTH)
				mapf = tok; sub(/\.odin\(.*$/, ".map", mapf)
				pos = tok; sub(/^.*\(/, "", pos); sub(/\)$/, "", pos)
				split(pos, p, ":")
				k = 0; src = "?"
				while ((getline s < mapf) > 0) if (++k == p[1]) { src = s; break }
				close(mapf)
				$0 = substr($0, 1, RSTART - 1) sheet ":" src ":" p[2] substr($0, RSTART + RLENGTH)
			}
			print "  " $0
		}' "$dir/out.txt"
done < "$out/index"

# A block is bad when an error begins at one of its lines (a line of the report that starts
# with its file, not an "at" or a source excerpt).
bad=$({ grep -hoE '^[^ 	]*b[0-9][0-9]\.odin\(' "$out"/*/out.txt 2>/dev/null || true; } | sort -u | wc -l)
if [ "$bad" -gt 0 ]; then
	echo "$sheet: $bad of $blocks blocks do not compile"
	exit 1
fi
echo "$sheet: $blocks blocks compile ($skipped skipped)"
