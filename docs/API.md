# odin-glycin API

Every public declaration of every package, generated from the source by `make api`; do not
edit. The reference is the [README](../README.md); the short form is the
[cheat sheet](CHEATSHEET.md).

## glycin:glycin

```text
package glycin
	procedures
		cicp_copy :: proc(cicp: ^Cicp) -> ^Cicp ---
		cicp_free :: proc(cicp: ^Cicp) ---
		cicp_get_type :: proc() -> gobj.Type ---
		cicp_get_type :: proc() -> gobj.Type ---
		color_mode_get_type :: proc() -> gobj.Type ---
		creator_add_frame :: proc(creator: ^Creator, width: u32, height: u32, memory_format: MemoryFormat, texture: ^glib.Bytes, error: ^^glib.Error) -> ^NewFrame ---
		creator_add_frame_with_stride :: proc(creator: ^Creator, width: u32, height: u32, stride: u32, memory_format: MemoryFormat, texture: ^glib.Bytes, error: ^^glib.Error) -> ^NewFrame ---
		creator_add_metadata_key_value :: proc(creator: ^Creator, key: cstring, value: cstring) -> glib.boolean ---
		creator_create :: proc(image: ^Creator, error: ^^glib.Error) -> ^EncodedImage ---
		creator_create_async :: proc(creator: ^Creator, cancellable: ^gio.Cancellable, callback: gio.AsyncReadyCallback, user_data: glib.pointer) ---
		creator_create_finish :: proc(creator: ^Creator, result: ^gio.AsyncResult, error: ^^glib.Error) -> ^EncodedImage ---
		creator_get_type :: proc() -> gobj.Type ---
		creator_get_type :: proc() -> gobj.Type ---
		creator_new :: proc(mime_type: cstring, error: ^^glib.Error) -> ^Creator ---
		creator_set_encoding_compression :: proc(creator: ^Creator, compression: u8) -> glib.boolean ---
		creator_set_encoding_quality :: proc(creator: ^Creator, quality: u8) -> glib.boolean ---
		creator_set_sandbox_selector :: proc(creator: ^Creator, sandbox_selector: SandboxSelector) -> glib.boolean ---
		encoded_image_get_data :: proc(encoded_image: ^EncodedImage) -> ^glib.Bytes ---
		encoded_image_get_type :: proc() -> gobj.Type ---
		encoded_image_get_type :: proc() -> gobj.Type ---
		frame_details_get_pixel_density :: proc(frame_details: ^FrameDetails) -> ^PixelDensity ---
		frame_details_get_type :: proc() -> gobj.Type ---
		frame_details_get_type :: proc() -> gobj.Type ---
		frame_get_buf_bytes :: proc(frame: ^Frame) -> ^glib.Bytes ---
		frame_get_color_cicp :: proc(frame: ^Frame) -> ^Cicp ---
		frame_get_color_icc_profile :: proc(frame: ^Frame) -> ^glib.Bytes ---
		frame_get_color_mode :: proc(frame: ^Frame) -> ColorMode ---
		frame_get_delay :: proc(frame: ^Frame) -> i64 ---
		frame_get_details :: proc(frame: ^Frame) -> ^FrameDetails ---
		frame_get_height :: proc(frame: ^Frame) -> u32 ---
		frame_get_memory_format :: proc(frame: ^Frame) -> MemoryFormat ---
		frame_get_stride :: proc(frame: ^Frame) -> u32 ---
		frame_get_type :: proc() -> gobj.Type ---
		frame_get_type :: proc() -> gobj.Type ---
		frame_get_width :: proc(frame: ^Frame) -> u32 ---
		frame_request_get_type :: proc() -> gobj.Type ---
		frame_request_get_type :: proc() -> gobj.Type ---
		frame_request_new :: proc() -> ^FrameRequest ---
		frame_request_set_loop_animation :: proc(frame_request: ^FrameRequest, loop_animation: glib.boolean) ---
		frame_request_set_scale :: proc(frame_request: ^FrameRequest, width: u32, height: u32) ---
		image_get_height :: proc(image: ^Image) -> u32 ---
		image_get_metadata_key_value :: proc(image: ^Image, key: cstring) -> cstring ---
		image_get_metadata_keys :: proc(image: ^Image) -> glib.Strv ---
		image_get_mime_type :: proc(image: ^Image) -> cstring ---
		image_get_specific_frame :: proc(image: ^Image, frame_request: ^FrameRequest, error: ^^glib.Error) -> ^Frame ---
		image_get_specific_frame_async :: proc(image: ^Image, frame_request: ^FrameRequest, cancellable: ^gio.Cancellable, callback: gio.AsyncReadyCallback, user_data: glib.pointer) ---
		image_get_specific_frame_finish :: proc(image: ^Image, result: ^gio.AsyncResult, error: ^^glib.Error) -> ^Frame ---
		image_get_transformation_orientation :: proc(image: ^Image) -> u16 ---
		image_get_type :: proc() -> gobj.Type ---
		image_get_type :: proc() -> gobj.Type ---
		image_get_width :: proc(image: ^Image) -> u32 ---
		image_next_frame :: proc(image: ^Image, error: ^^glib.Error) -> ^Frame ---
		image_next_frame_async :: proc(image: ^Image, cancellable: ^gio.Cancellable, callback: gio.AsyncReadyCallback, user_data: glib.pointer) ---
		image_next_frame_finish :: proc(image: ^Image, result: ^gio.AsyncResult, error: ^^glib.Error) -> ^Frame ---
		loader_error_get_type :: proc() -> gobj.Type ---
		loader_error_quark :: proc() -> glib.Quark ---
		loader_error_quark :: proc() -> glib.Quark ---
		loader_get_mime_types :: proc() -> glib.Strv ---
		loader_get_mime_types_async :: proc(cancellable: ^gio.Cancellable, callback: gio.AsyncReadyCallback, user_data: glib.pointer) ---
		loader_get_mime_types_finish :: proc(result: ^gio.AsyncResult, error: ^^glib.Error) -> glib.Strv ---
		loader_get_type :: proc() -> gobj.Type ---
		loader_get_type :: proc() -> gobj.Type ---
		loader_load :: proc(loader: ^Loader, error: ^^glib.Error) -> ^Image ---
		loader_load_async :: proc(loader: ^Loader, cancellable: ^gio.Cancellable, callback: gio.AsyncReadyCallback, user_data: glib.pointer) ---
		loader_load_finish :: proc(loader: ^Loader, result: ^gio.AsyncResult, error: ^^glib.Error) -> ^Image ---
		loader_new :: proc(file: ^gio.File) -> ^Loader ---
		loader_new_for_bytes :: proc(bytes: ^glib.Bytes) -> ^Loader ---
		loader_new_for_stream :: proc(stream: ^gio.InputStream) -> ^Loader ---
		loader_set_accepted_memory_formats :: proc(loader: ^Loader, memory_format_selection: MemoryFormatSelection) ---
		loader_set_apply_transformations :: proc(loader: ^Loader, apply_transformations: glib.boolean) ---
		loader_set_color_convert_icc_srgb :: proc(loader: ^Loader, convert: glib.boolean) ---
		loader_set_sandbox_selector :: proc(loader: ^Loader, sandbox_selector: SandboxSelector) ---
		memory_format_get_type :: proc() -> gobj.Type ---
		memory_format_has_alpha :: proc(memory_format: MemoryFormat) -> glib.boolean ---
		memory_format_is_premultiplied :: proc(memory_format: MemoryFormat) -> glib.boolean ---
		memory_format_selection_get_type :: proc() -> gobj.Type ---
		new_frame_get_type :: proc() -> gobj.Type ---
		new_frame_get_type :: proc() -> gobj.Type ---
		new_frame_set_color_icc_profile :: proc(new_frame: ^NewFrame, icc_profile: ^glib.Bytes) -> glib.boolean ---
		new_frame_set_pixel_density :: proc(new_frame: ^NewFrame, pixel_density: ^PixelDensity) ---
		physical_dimension_unit_get_type :: proc() -> gobj.Type ---
		pixel_density_convert :: proc(pixel_density: ^PixelDensity, unit: PhysicalDimensionUnit) -> ^PixelDensity ---
		pixel_density_get_type :: proc() -> gobj.Type ---
		pixel_density_get_type :: proc() -> gobj.Type ---
		pixel_density_get_x_unit :: proc(pixel_density: ^PixelDensity) -> PhysicalDimensionUnit ---
		pixel_density_get_x_value :: proc(pixel_density: ^PixelDensity) -> f64 ---
		pixel_density_get_y_unit :: proc(pixel_density: ^PixelDensity) -> PhysicalDimensionUnit ---
		pixel_density_get_y_value :: proc(pixel_density: ^PixelDensity) -> f64 ---
		pixel_density_new :: proc(x_value: f64, x_unit: PhysicalDimensionUnit, y_value: f64, y_unit: PhysicalDimensionUnit) -> ^PixelDensity ---
		sandbox_selector_get_type :: proc() -> gobj.Type ---

	types
		Cicp :: struct {color_primaries: u8, transfer_characteristics: u8, matrix_coefficients: u8, video_full_range_flag: u8}
		ColorMode :: enum u32 {SRGB = 1, CICP = 2, ICC_PROFILE = 3}
		Creator :: struct #packed {}
		CreatorClass :: struct {parent_class: gobj.ObjectClass}
		EncodedImage :: struct #packed {}
		EncodedImageClass :: struct {parent_class: gobj.ObjectClass}
		Frame :: struct #packed {}
		FrameClass :: struct {parent_class: gobj.ObjectClass}
		FrameDetails :: struct #packed {}
		FrameDetailsClass :: struct {parent_class: gobj.ObjectClass}
		FrameRequest :: struct #packed {}
		FrameRequestClass :: struct {parent_class: gobj.ObjectClass}
		Image :: struct #packed {}
		ImageClass :: struct {parent_class: gobj.ObjectClass}
		Loader :: struct #packed {}
		LoaderClass :: struct {parent_class: gobj.ObjectClass}
		LoaderError :: enum u32 {FAILED = 0, UNKNOWN_IMAGE_FORMAT = 1, NO_MORE_FRAMES = 2}
		LoaderGetMimeTypesDoneFunc :: #type proc(mime_types: glib.Strv, data: glib.pointer)
		MemoryFormat :: enum u32 {MEMORY_B8G8R8A8_PREMULTIPLIED = 0, MEMORY_A8R8G8B8_PREMULTIPLIED = 1, MEMORY_R8G8B8A8_PREMULTIPLIED = 2, MEMORY_B8G8R8A8 = 3, MEMORY_A8R8G8B8 = 4, MEMORY_R8G8B8A8 = 5, MEMORY_A8B8G8R8 = 6, MEMORY_R8G8B8 = 7, MEMORY_B8G8R8 = 8, MEMORY_R16G16B16 = 9, MEMORY_R16G16B16A16_PREMULTIPLIED = 10, MEMORY_R16G16B16A16 = 11, MEMORY_R16G16B16_FLOAT = 12, MEMORY_R16G16B16A16_FLOAT = 13, MEMORY_R32G32B32_FLOAT = 14, MEMORY_R32G32B32A32_FLOAT_PREMULTIPLIED = 15, MEMORY_R32G32B32A32_FLOAT = 16, MEMORY_G8A8_PREMULTIPLIED = 17, MEMORY_G8A8 = 18, MEMORY_G8 = 19, MEMORY_G16A16_PREMULTIPLIED = 20, MEMORY_G16A16 = 21, MEMORY_G16 = 22}
		MemoryFormatSelection :: bit_set[MemoryFormatSelectionBit]
		MemoryFormatSelectionBit :: enum u32 {B8G8R8A8_PREMULTIPLIED = 0, A8R8G8B8_PREMULTIPLIED = 1, R8G8B8A8_PREMULTIPLIED = 2, B8G8R8A8 = 3, A8R8G8B8 = 4, R8G8B8A8 = 5, A8B8G8R8 = 6, R8G8B8 = 7, B8G8R8 = 8, R16G16B16 = 9, R16G16B16A16_PREMULTIPLIED = 10, R16G16B16A16 = 11, R16G16B16_FLOAT = 12, R16G16B16A16_FLOAT = 13, R32G32B32_FLOAT = 14, R32G32B32A32_FLOAT_PREMULTIPLIED = 15, R32G32B32A32_FLOAT = 16, G8A8_PREMULTIPLIED = 17, G8A8 = 18, G8 = 19, G16A16_PREMULTIPLIED = 20, G16A16 = 21, G16 = 22}
		NewFrame :: struct #packed {}
		NewFrameClass :: struct {parent_class: gobj.ObjectClass}
		PhysicalDimensionUnit :: enum u32 {INCH = 1, PICA = 2, POINT = 3, METER = 4, CENTIMETER = 5, MILLIMETER = 6}
		PixelDensity :: struct #packed {}
		PixelDensityClass :: struct {parent_class: gobj.ObjectClass}
		SandboxSelector :: enum u32 {AUTO = 0, BWRAP = 1, FLATPAK_SPAWN = 2, NOT_SANDBOXED = 3}

	files:
		glycin.odin
		patched.odin
```

## glycin:glycin_gtk4

```text
package glycin_gtk4
	procedures
		frame_get_texture :: proc(frame: ^glycin.Frame) -> ^gtk4.Texture ---

	files:
		glycin_gtk4.odin
		patched.odin
```
