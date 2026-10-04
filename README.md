# odin-glycin

Odin bindings for glycin 2 and libglycin-gtk4, generated with [runic](https://github.com/Samudevv/runic)
from the headers of the version Amber ships.

**Bound version:** 2.2.1 (the glycin Amber ships, built by the amber-glycin package; Mint 22
has no libglycin). The headers carry no version macro. A test compares this line with the
Version of the staged glycin-2.pc and glycin-gtk4-2.pc, so a bump of amber-glycin that is not
recorded here fails the build.

## Packages

```
glycin/        package glycin: sandboxed image loading and encoding (libglycin-2)
glycin_gtk4/   package glycin_gtk4: a frame as a GdkTexture (libglycin-gtk4-2)
```

`glycin` imports GLib, GObject and GIO from the `glib` collection and nothing else. `glycin_gtk4`
also imports `gtk4` (the type of `GdkTexture`) and `glycin`.

## Use

Point a collection at this repo. The collection is named `glycin` in every repo of the suite:

```
odin build . -collection:glycin=../odin-glycin -collection:glib=../odin-glib \
    -extra-linker-flags:"-L/usr/lib/amber-glycin -Wl,-rpath,/usr/lib/amber-glycin"
```

A program that imports `glycin_gtk4` also needs the collections odin-gtk4 imports (`gtk4`,
`cairo`, `pango`, `graphene`, `pixbuf`) and `/usr/lib/amber-gtk4` on its RUNPATH, as the
Makefile's `COLLECTIONS` and `LINK_FLAGS` show.

```odin
import "glycin:glycin"
import "glycin:glycin_gtk4"
```

```odin
file := gio.file_new_for_path("photo.jpg")
loader := glycin.loader_new(file)
err: ^glib.Error
image := glycin.loader_load(loader, &err)       // nil and err set on failure
frame := glycin.image_next_frame(image, &err)
texture := glycin_gtk4.frame_get_texture(frame) // a ^gtk4.Texture, you own it
```

The programs in [examples/](examples/) are complete: `info` prints what the library reports about
files, `view` shows one in a GTK window.

### Running

glycin exists only in amber-glycin's bundle; Mint has no libglycin. A program that uses it:

- links with RUNPATH `/usr/lib/amber-glycin`, so the bundle's libglycin-2 and libglycin-gtk4-2
  are the ones loaded;
- runs with `GLYCIN_DATA_DIR=/usr/lib/amber-glycin/share`, so glycin finds the bundle's loader
  configuration and not the distro's `glycin-loaders` 1.x, which speak a different protocol;
- needs bubblewrap, which runs each loader in its sandbox.

glycin starts a loader process per image source. Every call that reads an image can fail, and a
corrupt image makes it fail with a `GError`; the calling process is not affected.

### Formats

The bundle builds the image-rs and SVG loaders only. Loadable: PNG, APNG, JPEG, GIF, WebP, TIFF,
BMP, ICO, TGA, DDS, EXR, QOI, Radiance HDR, PNM, XPM, XBM, JPEG 2000, SVG and SVGZ. HEIF, AVIF,
JPEG XL and camera RAW are not built, because the distribution's libheif and libjxl are too old;
`glycin.loader_get_mime_types` lists what the running library loads. Encoding (`Creator`) covers
JPEG, PNG, GIF, WebP, TIFF, TGA, BMP, ICO, EXR and QOI.

### Behaviour the headers leave open

Each of these is checked by a test against the real loaders.

- EXIF orientation is applied to the pixels by default, and the image and frame sizes are the
  displayed ones. `loader_set_apply_transformations(loader, false)` leaves the stored pixels and
  `image_get_transformation_orientation` (1 to 8) tells the caller what to correct.
- A raster image has one frame; a second `image_next_frame` fails with `NO_MORE_FRAMES`, even with
  looping on. An SVG never runs out: every call renders again, with delay 0. A caller that loops
  until `NO_MORE_FRAMES` must stop on delay 0.
- Animation delays are microseconds. After the last frame an animation returns to the first unless
  the `FrameRequest` has `set_loop_animation(false)`, which ends it with `NO_MORE_FRAMES`.
- `frame_request_set_scale` is honoured by the SVG loader and ignored by the others.
- `loader_set_accepted_memory_formats` converts to the formats given; without it the loader picks,
  and a caller handles every `MemoryFormat`.
- The async calls take a `GCancellable`; a cancelled call fails with `G_IO_ERROR_CANCELLED`.
- Input can be a `GFile`, a `GBytes` or a `GInputStream`; the format comes from the content.
- Metadata is a key and value per text chunk (PNG tEXt); the JPEG and GIF fixtures expose none,
  and a missing key returns nil.
- Failures arrive in glycin's own error domain (`LOADER_ERROR`), including a missing file; a
  format no loader knows is `UNKNOWN_IMAGE_FORMAT`.
- A loader's address space is limited to 80% of the available memory and to about 16 GB, and a
  frame over 8 GB is refused. Neither limit can be set through the API; an image over them fails
  to load.

## Generate

```
make deps       # runic, shellcheck, xvfb, bubblewrap, the staged bundles
make generate   # runic, then the post-processing rules (scripts/)
make ci         # check, test, lint
```

`make generate` reads the headers from amber-glycin's and amber-gtk4's staged builds
(`GLYCIN_STAGE`, `GTK_STAGE`). The output is committed: consumers need neither runic nor the
headers to build, only the libraries to link.

Hand fixes to generated output are listed in [docs/PATCHED.md](docs/PATCHED.md), each pinned
by a typed variable in the package's `patched.odin`, so a regeneration that drops one fails
to compile.

`make generate` needs runic, pinned in odin-glib's `docs/DECISIONS.md` §2: clone
[Hyperquader-Coders/runic](https://github.com/Hyperquader-Coders/runic) beside this repo, check
out branch `amber-patched` and run `runic/amber-build.sh`; the Makefile finds `../runic/build/runic`.

## Test

`make test` links and loads amber-glycin's staged library and runs the staged loaders in the
sandbox; without the stage it stops and says how to build it (`make glycin` in amber-glycin).
`glycin_gtk4`'s tests run under `xvfb-run` against amber-gtk4's GTK. `ASAN=1 make test` adds
AddressSanitizer. `make test-big` decodes an image over glycin's 8 GB frame limit and needs about
17 GB of free memory. See [docs/DECISIONS.md](docs/DECISIONS.md) §3 for why the stage is needed.

## Regenerating

The bindings are generated with runic 0.8 from Amber's fork (`../runic`, branch `amber-patched`,
commit `ddc6f8f`: upstream 0.8 `9bd8391`, the Amber build script and Odin pin, and two patches:
declared array parameters and skipped va_list procedures), built by `runic/amber-build.sh` with
the Odin its own `runic/mise.toml` pins. `make generate` runs runic through `scripts/generate.sh`,
then `scripts/postprocess.sh` (the remaining fixes). Never edit a generated `.odin` file by hand:
the next `make generate` undoes it. The config `parameters: declared` in each `rune.yml` makes
parameters single objects unless `arrays:` lists them; a va_list procedure is skipped, with a
comment in the output. `make lint` fails (`scripts/check-generated.sh`) if a `[^]` outside the
lists, a `[^]^T` outside the list, or a va_list procedure appears.

## Documents

- [docs/SPEC.md](docs/SPEC.md): package layout and the API surface
- [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md): generation, patches, collections, tests
- [docs/CHEATSHEET.md](docs/CHEATSHEET.md): the calls a program makes, in order
- [docs/DECISIONS.md](docs/DECISIONS.md): settled choices
- [MoSCoW.md](MoSCoW.md): open work
- [diags/](diags/): the dependency graph

## Licence

MPL-2.0 OR LGPL-2.1-or-later, the licence of the library bound; see [LICENSE](LICENSE).

Copyright © 2025 Andre Bremer <hyperquader@gmail.com>, https://hyperquader.com, for the
generation scripts, post-processing rules, helper code, tests and documentation. Copyright in
the library's headers, from which the bindings are generated, stays with its authors.

The runic configuration starts from [PucklaJ/odin-gtk](https://github.com/PucklaJ/odin-gtk)
(MIT, Copyright 2024 Kassandra Pucher); its notice is kept in
[docs/LICENSE-odin-gtk.md](docs/LICENSE-odin-gtk.md).
