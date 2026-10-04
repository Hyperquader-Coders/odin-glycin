# Decisions — odin-glycin

Settled choices. An entry that stops being true is rewritten, not appended to.

## 1. Generated, not hand-written

The bindings are generated with runic from the headers Amber ships, so a library bump is a
regeneration. Hand fixes are the exception and are tracked in [PATCHED.md](PATCHED.md).

## 2. Flag enums are bit_sets, chosen by a list

`MemoryFormatSelection` (`GlyMemoryFormatSelection`, bits `1 << 0` to `1 << 22`) is the only GFlags
type in glycin. `postprocess.sh` rewrites it to `bit_set[MemoryFormatSelectionBit; u32]` with the C
size, as odin-gtk4 does for its flags (odin-gtk4 DECISIONS §5), so callers write
`{.R8G8B8A8, .G8}`. The enum is named in a list: bit-flags and plain enums are not told apart by
value alone (`MemoryFormat`, 0 to 22, is a plain enum with the same members). Generation fails if
the listed enum is missing, so a header bump that renames it is noticed. A new flag type in a bump
is added to the list by hand. The member names lose their `MEMORY_SELECTION_` group word, since
the type says it.

## 3. Tests link and load the amber-glycin stage

libglycin 2 is not in Mint 22 (it ships glycin-loaders 1.x only), so there is no distro library
to fall back on. `make test` links and loads amber-glycin's staged build and fails with the build
command when it is missing. A test that mocked the library would not check the protocol, the
sandbox or the loaders, which are what the binding exists for. The loaders run from the stage,
not from an install: the staged configs name `/usr/lib/amber-glycin`, so the Makefile copies them
with `Exec=` rewritten (`scripts/data-dir.sh`). The test environment is the one consumers use:
RUNPATH to the bundle and `GLYCIN_DATA_DIR`.

CI checks out amber-glycin and builds it with `make glycin`, caching its stage against its VERSION,
patches and Makefile. The GTK stage libglycin-gtk4 needs is built in the same job with
amber-glycin's `make gtk-sdk`.

## 4. Version policy: the .pc files, exactly

The headers have no version macro and the library no version function. The README's
`**Bound version:**` line is compared with the `Version:` of the staged `glycin-2.pc` and
`glycin-gtk4-2.pc`, which `make test` passes as `-define:GLYCIN_VERSION`. The comparison is exact,
not a floor: the tests always run the bundle, so a bump of amber-glycin must be recorded here with
the regenerated bindings. A second test checks that the process mapped the stage's
`libglycin-2.so`, so the version compared is the library tested.

## 5. Opaque objects, not generated accessors

Objects (`Loader`, `Image`, `Frame`, ...) are used by pointer and released with
`gobj.object_unref`. GObject reference counting is the only lifetime API, and a wrapper would
hide the ownership rules the header documents (`transfer full` or `none` per call).

## 6. Corrupt input fails in the loader, not in the host

glycin decodes in a bubblewrap and seccomp sandboxed process, so a malformed image ends the
loader and the call returns a `GError`; the program calling it keeps running. The tests assert
that on truncated, damaged, oversized-header, unknown and empty input, and on mutated PNG and
JPEG, and then decode a good image in the same process. A binding must not add decoding of its
own in the host, and does not.

## 7. Parameters are single objects unless declared

runic 0.8 writes `[^]T` for a pointer parameter whose C name ends in `s` (`settings`, `lines`),
however many elements it holds, which lets a caller index past one element, and drops a trailing
`va_list`, binding the procedure as `#c_vararg ..any`. Amber's runic fork (branch `amber-patched`)
has `parameters: declared`: with it every procedure parameter is `^T` (`T **` is `^^T`) unless
`arrays:` in the package's `rune.yml` lists it, chosen against the C headers, and a va_list
procedure is skipped. Struct members, variables and typedefs keep runic's name guess, and the
parameters of function-pointer types are plain `^T`: a limit of the fork, true in every binding.
Where a binding needs it, the `param_rules` table in `postprocess.sh` restores the `[^]` for
those parameters' real arrays, rewrites single-object struct members and corrects `T ***` outs;
a row that matches nothing fails the build. Rejected: rewriting the output in `postprocess.sh`,
which had to be told each parameter, matched `va_list` procedures by name pattern (it deleted
`list_store_insert_with_values` for containing `_va`) and was a second place to keep in step
with the headers. `scripts/check-generated.sh` stays as the guard that any regeneration, with
any runic, keeps the listed parameters right.
