# odin-glycin cheat sheet

One screen per job: the calls a program makes, in the order it makes them, and the few rules
worth remembering. Every name here is a public declaration in [API.md](API.md), and
`make lint` fails when one is not, or when a block does not compile. For the reasons behind a
rule, follow the link to the README.

Conventions that hold everywhere: the library is the `glycin` collection
(`-collection:glycin=../odin-glycin`); the names are glycin's without the `gly_` prefix;
GLib, GObject and GIO come from `glib:` and are never redeclared ([Use](../README.md#use));
a call that can fail takes a `^^glib.Error` last and sets it only on failure; every object is a
GObject and ends with `gobj.object_unref`. A program links against `/usr/lib/amber-glycin` and runs
with `GLYCIN_DATA_DIR` set ([Running](../README.md#running)).

## glycin:glycin — decode an image

```odin
import "glycin:glycin"
import gio "glib:gio"
import glib "glib:glib"
import gobj "glib:gobject"

file := gio.file_new_for_path("photo.jpg")
defer gobj.object_unref(file)
loader := glycin.loader_new(file)                  // or loader_new_for_bytes, loader_new_for_stream
defer gobj.object_unref(loader)
glycin.loader_set_apply_transformations(loader, false)   // keep the stored pixels; see orientation below

err: ^glib.Error                                   // nil on success
image := glycin.loader_load(loader, &err)          // nil and err set on failure, a corrupt file included
if image == nil {
	glib.error_free(err)
	return
}
defer gobj.object_unref(image)
_ = glycin.image_get_mime_type(image)              // cstring, owned by image
_ = glycin.image_get_width(image)
_ = glycin.image_get_transformation_orientation(image)   // 1 to 8: what a caller corrects

frame := glycin.image_next_frame(image, &err)      // nil with NO_MORE_FRAMES after the last frame
defer gobj.object_unref(frame)
_ = glycin.frame_get_width(frame)
_ = glycin.frame_get_stride(frame)                 // bytes per row
_ = glycin.frame_get_memory_format(frame)          // a caller handles every MemoryFormat
pixels := glycin.frame_get_buf_bytes(frame)        // ^glib.Bytes, owned by frame
_ = pixels

// Choose the formats instead of handling all of them.
glycin.loader_set_accepted_memory_formats(loader, {.R8G8B8A8, .R8G8B8})

// One pass over an animation, or a scaled SVG.
request := glycin.frame_request_new()
defer gobj.object_unref(request)
glycin.frame_request_set_loop_animation(request, false)
glycin.frame_request_set_scale(request, 256, 256)  // the SVG loader honours it, the others ignore it
f2 := glycin.image_get_specific_frame(image, request, &err)
if f2 != nil { gobj.object_unref(f2) }
```

| remember | |
|---|---|
| A corrupt image is a `GError`, not a crash | the loader runs in its own sandboxed process; the caller keeps running ([DECISIONS §6](DECISIONS.md)) |
| Orientation is applied by default | sizes are the displayed ones; `loader_set_apply_transformations(loader, false)` leaves the stored pixels |
| A raster has one frame | the second `image_next_frame` fails with `NO_MORE_FRAMES`; an SVG never runs out and reports delay 0, so stop on delay 0 |
| Delays are microseconds | an animation loops unless `frame_request_set_loop_animation(request, false)` |
| Match the error by domain | `glib.error_matches(err, glycin.loader_error_quark(), i32(glycin.LoaderError.NO_MORE_FRAMES))` |
| Async calls take a `GCancellable` | a cancelled call fails with `G_IO_ERROR_CANCELLED` |
| `loader_get_mime_types` lists what loads | HEIF, AVIF, JPEG XL and camera RAW are not built |

## glycin:glycin — encode an image

```odin
creator := glycin.creator_new("image/png", &err)   // nil with err set for an unknown type
defer gobj.object_unref(creator)
_ = glycin.creator_set_encoding_compression(creator, 6)
nf := glycin.creator_add_frame(creator, 64, 64, .MEMORY_R8G8B8A8, bytes, &err)   // bytes: ^glib.Bytes
defer gobj.object_unref(nf)
encoded := glycin.creator_create(creator, &err)    // ^glycin.EncodedImage
defer gobj.object_unref(encoded)
data := glycin.encoded_image_get_data(encoded)     // ^glib.Bytes: the file's bytes
_ = data
```

| remember | |
|---|---|
| `creator_new` takes a MIME type | JPEG, PNG, GIF, WebP, TIFF, TGA, BMP, ICO, EXR and QOI encode |
| Quality and compression are `u8` | `creator_set_encoding_quality` for lossy formats, `creator_set_encoding_compression` for PNG |

## glycin:glycin_gtk4 — a frame as a texture

```odin
import "glycin:glycin_gtk4"

texture := glycin_gtk4.frame_get_texture(frame)    // ^gtk4.Texture; you own it: gobj.object_unref
```

| remember | |
|---|---|
| Needs odin-gtk4's collections | `gtk4`, `cairo`, `pango`, `graphene`, `pixbuf`, and `/usr/lib/amber-gtk4` on the RUNPATH |
