#!/usr/bin/env bash
# Rewrites runic's output where runic gets Odin wrong. Run by `make generate` after runic,
# once per package: scripts/postprocess.sh glycin|glycin_gtk4. Deterministic: the same runic
# output always gives the same file. Every rule is listed in docs/PATCHED.md. The one flag
# enum becomes a bit_set (bit_sets below).
#
# The rules are odin-gtk's (MIT, docs/LICENSE-odin-gtk.md), kept where they still apply to
# runic 0.8 on the staged headers.
set -euo pipefail

# bit_sets <file> <strip-prefix> <enum>...: `Foo :: enum u32 {A = 1, B = 4, C = 5, NONE = 0}`
# becomes
#   FooBit :: enum u32 {A = 0, B = 2}        bit indices, prefix stripped from the members
#   Foo :: bit_set[FooBit; u32]              same size and bits as the C type
#   C :: Foo{.A, .B}                         composite masks, by their C names
#   NONE :: Foo{}                            zero members, by their C names; a name with no
#                                            underscore (NONE, FAMILY) is prefixed FOO_ so it is unique
# Members that are not one bit or zero are composites; a composite with a bit that has no
# member is a transmute of the C value. Fails if a listed enum is missing, has a negative
# value or has no single-bit member, so a header bump that changes a flag type is noticed.
bit_sets() {
    local file=$1 strip=$2
    shift 2
    STRIP=$strip NAMES="$*" perl -i -ne '
        BEGIN { $strip = $ENV{STRIP}; %want = map { $_ => 1 } split " ", $ENV{NAMES}; }
        if (/^(\w+) :: enum u32 \{(.*)\}\s*$/ && $want{$1}) {
            my ($name, $body) = ($1, $2);
            delete $want{$name};
            my (@bits, @zero, @comp, $all);
            (my $pre = uc($name =~ s/([a-z0-9])([A-Z])/$1_$2/gr)) .= "_";
            for my $m (split /,\s*/, $body =~ s/\s+$//r) {
                $m =~ /^(\w+) = (-?\d+)$/ or die "postprocess: $name: cannot read member $m\n";
                my ($id, $v) = ($1, $2);
                die "postprocess: $name.$id is negative\n" if $v < 0;
                if ($v == 0) { push @zero, $id }
                elsif (($v & ($v - 1)) == 0) { push @bits, [$id, $v] }
                else { push @comp, [$id, $v] }
            }
            die "postprocess: $name has no single-bit member\n" unless @bits;
            my %idx; my $mask = 0;
            for (@bits) {
                my $i = 0; $i++ while (1 << $i) != $_->[1];
                ($id = $_->[0]) =~ s/^\Q$strip\E//;
                $idx{$_->[1]} = $id; $mask |= $_->[1];
                $_ = [$id, $i];
            }
            print "${name}Bit :: enum u32 {", join(", ", map { "$_->[0] = $_->[1]" } @bits), "}\n";
            print "$name :: bit_set[${name}Bit; u32]\n";
            for (@zero) { my $c = /_/ ? $_ : "$pre$_"; print "$c :: $name\{}\n" }
            for (@comp) {
                my ($id, $v) = @$_;
                $id = "$pre$id" unless $id =~ /_/;
                if (($v & ~$mask) == 0) {
                    print "$id :: $name\{", join(", ", map { ".$idx{$_}" } grep { $v & $_ } sort { $a <=> $b } keys %idx), "}\n";
                } else { print "$id :: transmute($name)u32($v)\n" }
            }
        } else { print }
        END { die "postprocess: flag enum(s) not found: " . join(" ", sort keys %want) . "\n" if %want; }
    ' "$file"
}

pkg=${1:?usage: postprocess.sh glycin|glycin_gtk4}
cd "$(dirname "$0")/.."
file="$pkg/$pkg.odin"
[ -f "$file" ] || { echo "postprocess: $file not found" >&2; exit 2; }

case "$pkg" in
glycin)
    # gchar * is ^char (cstring). Macros runic quotes as backtick strings become Odin
    # expressions: TYPE_FOO names foo_get_type, LOADER_ERROR names the quark procedure.
    # `Foo :: _GlyFoo` is dropped and `_GlyFoo` becomes Foo.
    # shellcheck disable=SC2016  # backticks in the sed patterns are literal
    sed -i "$file" \
        -e 's/\^glib\.char/cstring/g' \
        -e '/^[A-Z0-9_]* :: `(\?[a-z0-9_]* \?())\?`$/ {s/`(\?//; s/ \?())\?`//; s/ gly_/ /}' \
        -e '/^\([a-zA-Z][a-zA-Z_0-9]*\)\s*::\s*_Gly\1$/d' \
        -e 's#^_Gly\([a-zA-Z][a-zA-Z_0-9]*\)\s*::\s*\(.*\)$#\1 :: \2#'
    bit_sets "$file" MEMORY_SELECTION_ MemoryFormatSelection
    ;;
glycin_gtk4)
    # GdkTexture is gtk4.Texture; nothing else to rewrite.
    ;;
*)
    echo "postprocess: unknown package $pkg" >&2
    exit 2
    ;;
esac
