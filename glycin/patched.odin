package glycin

import glib "glib:glib"
import gio "glib:gio"
import gobj "glib:gobject"

// Typed pins for the post-generation rules (docs/PATCHED.md). A regeneration that drops one
// fails to compile here.

// gchar * is cstring, not ^char.
@(private = "file")
patched_image_get_metadata_key_value: proc "c" (_: ^Image, _: cstring) -> cstring = image_get_metadata_key_value

@(private = "file")
patched_creator_new: proc "c" (_: cstring, _: ^^glib.Error) -> ^Creator = creator_new

@(private = "file")
patched_creator_add_metadata_key_value: proc "c" (_: ^Creator, _: cstring, _: cstring) -> glib.boolean = creator_add_metadata_key_value

// GBytes * and GlyFrameDetails * parameters are ^T, not [^]T.
@(private = "file")
patched_loader_new_for_bytes: proc "c" (_: ^glib.Bytes) -> ^Loader = loader_new_for_bytes

@(private = "file")
patched_frame_details_get_pixel_density: proc "c" (_: ^FrameDetails) -> ^PixelDensity = frame_details_get_pixel_density

// TYPE_FOO is the get_type procedure itself; LOADER_ERROR the quark procedure.
@(private = "file")
patched_type_loader: proc "c" () -> gobj.Type = TYPE_LOADER

@(private = "file")
patched_loader_error: proc "c" () -> glib.Quark = LOADER_ERROR

// `typedef struct _GlyFoo GlyFoo` is one type, Foo.
@(private = "file")
patched_loader_new: proc "c" (_: ^gio.File) -> ^Loader = loader_new

// GlyMemoryFormatSelection is a flag type: a bit_set with the C size, bit i set for 1 << i.
#assert(size_of(MemoryFormatSelection) == 4)
#assert(int(MemoryFormatSelectionBit.R8G8B8) == 7)
#assert(int(MemoryFormatSelectionBit.G16) == 22)
