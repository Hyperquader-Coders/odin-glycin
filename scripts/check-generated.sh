#!/usr/bin/env bash
# Fails when one of runic's two faults comes back in the generated files (docs/PATCHED.md):
#  1. a `#c_vararg` procedure bound over a C `va_list` (`*_valist`, `*_vprintf`, `logv`, ...):
#     runic drops the trailing `va_list` and writes `..any`, which is a wrong call. Every such
#     procedure is skipped by the fork of runic (to.detect); the names are listed here, and the generic
#     pattern catches a new one.
#  2. a parameter the header declares as one `T *`, typed `[^]T` again: runic writes `[^]T` for
#     any pointer parameter whose name ends in "s". Each corrected `declaration, parameter` is
#     listed here; a declaration is a procedure, a callback type or a struct.
# Usage: scripts/check-generated.sh
set -euo pipefail
cd "$(dirname "$0")/.."

files=(glycin/glycin.odin glycin_gtk4/glycin_gtk4.odin)

# C names of the procedures removed because their last C parameter is a va_list.
removed=""

# Link names that mark a va_list binding even when not listed above.
pattern='_valist|_va_list|vprintf|vsnprintf|vsprintf|vasprintf|_vfprintf|_logv|_vscanf'

# Parameters that are real `[^]^T` arrays (counted or NULL-terminated, read against the headers):
# any other `[^]^T` is a `T **` out-parameter that returns one pointer and must be `^^T`.
arrays=""

# Corrected parameters: `declaration, parameter`.
read -r -d '' corrected <<'LIST' || true
loader_new_for_bytes, bytes
frame_details_get_pixel_density, frame_details
LIST

REMOVED="$removed" PATTERN="$pattern" CORRECTED="$corrected" ARRAYS="$arrays" perl -e '
    my %removed = map { $_ => 1 } split " ", $ENV{REMOVED};
    my $pattern = qr/$ENV{PATTERN}/;
    my (%decl, @bad, %seen);
    my %arrays = map { $_ => 1 } split " ", $ENV{ARRAYS};
    for my $f (@ARGV) {
        open my $in, "<", $f or die "check-generated: $f: $!\n";
        my ($prev, $struct) = ("", undef);
        while (<$in>) {
            chomp;
            while (/\b(\w+): \[\^\]\^/g) {
                push @bad, "$f: parameter $1 is [^]^T; a T ** out-parameter must be ^^T (list real arrays in \$arrays)" unless $arrays{$1};
            }
            if (/^\s*\@\(link_name = "(\w+)"\)/) { $prev = $1; }
            elsif (/^\s*(\w+) :: proc\((.*)\)/) {
                my ($name, $args) = ($1, $2);
                $decl{$name} .= "$args\n";
                push @bad, "$f: $name is #c_vararg over $prev, a va_list binding"
                    if $args =~ /#c_vararg/ && ($removed{$prev} || $prev =~ $pattern);
                $prev = "";
            }
            elsif (/^(\w+) :: #type proc\s*(?:"c"\s*)?\((.*)\)/) { $decl{$1} .= "$2\n"; }
            elsif (/^(\w+) :: struct\b(.*)$/) { my ($n, $rest) = ($1, $2); $struct = $rest =~ /\}\s*$/ ? undef : $n; $decl{$n} .= "$rest\n"; }
            elsif (/^\}/) { $struct = undef; }
            elsif (defined $struct) { $decl{$struct} .= "$_\n"; }
            elsif (/^\s+(\w+): /) { $decl{$1} .= "$_\n"; }
            push @bad, "$f: $1 is bound again (removed va_list procedure)"
                if /^\s*\@\(link_name = "(\w+)"\)/ && $removed{$1};
        }
    }
    for my $line (split /\n/, $ENV{CORRECTED}) {
        next unless $line =~ /^(\w+), (\w+)$/;
        my ($d, $p) = ($1, $2);
        next if $seen{$line}++;
        if (!exists $decl{$d}) { push @bad, "$d, $p: declaration not found (stale entry)"; next; }
        push @bad, "$d: parameter $p is [^]T again" if $decl{$d} =~ /(?:^|[(, ])\Q$p\E: \[\^\]/m;
    }
    if (@bad) { print STDERR "check-generated: $_\n" for @bad; exit 1; }
' -- "${files[@]}"
echo "check-generated: no va_list binding, no corrected parameter back to [^], no unlisted [^]^T"
