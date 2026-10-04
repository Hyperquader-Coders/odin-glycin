#+test
package glycin

import "core:fmt"
import "core:os"
import "core:strings"
import "core:testing"
import "core:time"

import gio "glib:gio"
import glib "glib:glib"
import gobj "glib:gobject"

// These tests decode real images through the sandboxed loaders of amber-glycin's build: the
// Makefile links that library, points GLYCIN_DATA_DIR at the staged loader configs and sets
// GLYCIN_LIB to the directory holding them. No network, fixtures only.

// Version recorded in README.md: "**Bound version:** X.Y.Z".
README :: #load("../README.md", string)

// The staged glycin-2.pc's Version, passed by the Makefile (the headers carry no version macro).
GLYCIN_VERSION :: #config(GLYCIN_VERSION, "")

FIXTURES :: #directory + "/../fixtures/"

PX_PNG :: #load("../fixtures/px.png")
HALVES_JPG :: #load("../fixtures/halves.jpg")

bound_version :: proc() -> string {
    marker :: "**Bound version:** "
    readme := README
    i := strings.index(readme, marker)
    if i < 0 do return ""
    rest := readme[i + len(marker):]
    end := strings.index_any(rest, " \n")
    if end < 0 do return ""
    return rest[:end]
}

// ---- helpers ----

Failure :: struct {
    message: string,
    domain:  glib.Quark,
    code:    int,
}

take_error :: proc(err: ^glib.Error) -> Failure {
    if err == nil do return {}
    f := Failure{strings.clone(string(err.message), context.temp_allocator), err.domain, int(err.code)}
    glib.error_free(err)
    return f
}

// The first line of an error message: the loaders append their configuration after it.
first_line :: proc(s: string) -> string {
    i := strings.index_byte(s, '\n')
    return s if i < 0 else s[:i]
}

new_loader :: proc(name: string) -> ^Loader {
    path := fmt.ctprintf("%s%s", FIXTURES, name)
    file := gio.file_new_for_path(path)
    defer gobj.object_unref(file)
    return loader_new(file)
}

load :: proc(loader: ^Loader) -> (image: ^Image, fail: Failure) {
    err: ^glib.Error
    image = loader_load(loader, &err)
    if image == nil do fail = take_error(err)
    return
}

// Loads a fixture and its first frame; the caller unrefs both.
load_first :: proc(t: ^testing.T, name: string) -> (image: ^Image, frame: ^Frame) {
    loader := new_loader(name)
    defer gobj.object_unref(loader)
    fail: Failure
    image, fail = load(loader)
    testing.expectf(t, image != nil, "%s: load failed: %s", name, first_line(fail.message))
    if image == nil do return
    err: ^glib.Error
    frame = image_next_frame(image, &err)
    if frame == nil {
        testing.expectf(t, false, "%s: no frame: %s", name, first_line(take_error(err).message))
        gobj.object_unref(image)
        image = nil
    }
    return
}

release :: proc(image: ^Image, frame: ^Frame) {
    if frame != nil do gobj.object_unref(frame)
    if image != nil do gobj.object_unref(image)
}

// One pixel as RGBA8, whatever the frame's memory format; premultiplied formats are undone.
pixel :: proc(frame: ^Frame, x, y: int) -> (rgba: [4]u8) {
    n: glib.size
    data := cast([^]u8)glib.bytes_get_data(frame_get_buf_bytes(frame), &n)
    format := frame_get_memory_format(frame)
    stride := int(frame_get_stride(frame))
    bpp := 4
    #partial switch format {
    case .MEMORY_R8G8B8, .MEMORY_B8G8R8:
        bpp = 3
    }
    p := data[y * stride + x * bpp:]
    #partial switch format {
    case .MEMORY_R8G8B8:
        rgba = {p[0], p[1], p[2], 255}
    case .MEMORY_B8G8R8:
        rgba = {p[2], p[1], p[0], 255}
    case .MEMORY_R8G8B8A8:
        rgba = {p[0], p[1], p[2], p[3]}
    case .MEMORY_B8G8R8A8:
        rgba = {p[2], p[1], p[0], p[3]}
    case .MEMORY_R8G8B8A8_PREMULTIPLIED, .MEMORY_B8G8R8A8_PREMULTIPLIED:
        c := format == .MEMORY_R8G8B8A8_PREMULTIPLIED ? [3]u8{p[0], p[1], p[2]} : [3]u8{p[2], p[1], p[0]}
        a := int(p[3])
        for i in 0 ..< 3 do rgba[i] = a == 0 ? 0 : u8(min(255, (int(c[i]) * 255 + a / 2) / a))
        rgba[3] = p[3]
    case:
        panic("pixel: unsupported memory format")
    }
    return
}

near :: proc(a, b: [4]u8, tolerance: int) -> bool {
    for i in 0 ..< 4 {
        d := int(a[i]) - int(b[i])
        if d < -tolerance || d > tolerance do return false
    }
    return true
}

// Async plumbing: the callback stores the result; the test iterates the default main context
// until it arrives, or fails after a deadline.
Async :: struct {
    done:   bool,
    result: ^gio.AsyncResult,
}

on_done :: proc "c" (_: ^gobj.Object, res: ^gio.AsyncResult, data: glib.pointer) {
    a := cast(^Async)data
    a.result = res
    gobj.object_ref(a.result)
    a.done = true
}

wait :: proc(t: ^testing.T, a: ^Async) -> bool {
    deadline := time.tick_add(time.tick_now(), 30 * time.Second)
    for !a.done {
        if time.tick_diff(time.tick_now(), deadline) <= 0 {
            testing.expect(t, false, "async call did not finish in 30 s")
            return false
        }
        if !glib.main_context_iteration(nil, false) do time.sleep(2 * time.Millisecond)
    }
    return true
}

// ---- version and library ----

@(test)
test_readme_version_matches_staged_library :: proc(t: ^testing.T) {
    testing.expect(t, GLYCIN_VERSION != "", "GLYCIN_VERSION is not set: run the tests through make test")
    testing.expect_value(t, bound_version(), GLYCIN_VERSION)
}

@(test)
test_loaded_library_is_the_staged_one :: proc(t: ^testing.T) {
    lib := os.get_env("GLYCIN_LIB", context.temp_allocator)
    testing.expect(t, lib != "", "GLYCIN_LIB is not set: run the tests through make test")
    // Touch the library first so it is mapped, then look for it in the process's maps.
    testing.expect(t, loader_get_type() != 0, "gly_loader_get_type returned G_TYPE_INVALID")
    maps, err := os.read_entire_file("/proc/self/maps", context.temp_allocator)
    testing.expect_value(t, err, nil)
    want := fmt.tprintf("%s/libglycin-2.so", lib)
    testing.expectf(t, strings.contains(string(maps), want), "the process did not map %s", want)
}

@(test)
test_type_macros_are_get_type_procs :: proc(t: ^testing.T) {
    testing.expect(t, TYPE_LOADER() != 0, "gly_loader_get_type returned G_TYPE_INVALID")
    testing.expect(t, TYPE_LOADER() != TYPE_IMAGE(), "GlyLoader and GlyImage share a type")
    testing.expect(t, TYPE_CICP() != 0, "gly_cicp_get_type returned G_TYPE_INVALID")
    testing.expect(t, LOADER_ERROR() != 0, "gly_loader_error_quark returned 0")
}

@(test)
test_supported_mime_types :: proc(t: ^testing.T) {
    types := loader_get_mime_types()
    testing.expect(t, types != nil, "no mime types")
    defer glib.strfreev(types)
    have: [dynamic]string
    defer delete(have)
    list := cast([^]cstring)types
    for i := 0; list[i] != nil; i += 1 {
        append(&have, string(list[i]))
    }
    has :: proc(have: []string, m: string) -> bool {
        for h in have do if h == m do return true
        return false
    }
    // amber-glycin builds the image-rs and SVG loaders only.
    for m in ([]string{"image/png", "image/jpeg", "image/gif", "image/svg+xml", "image/webp", "image/tiff"}) {
        testing.expectf(t, has(have[:], m), "%s is not loadable", m)
    }
    for m in ([]string{"image/heif", "image/avif", "image/jxl"}) {
        testing.expectf(t, !has(have[:], m), "%s is loadable: update the README's list of formats", m)
    }
}

// ---- decoding ----

@(test)
test_png_pixels :: proc(t: ^testing.T) {
    image, frame := load_first(t, "px.png")
    if image == nil do return
    defer release(image, frame)

    testing.expect_value(t, image_get_mime_type(image), "image/png")
    testing.expect_value(t, image_get_width(image), 3)
    testing.expect_value(t, image_get_height(image), 2)
    testing.expect_value(t, frame_get_width(frame), 3)
    testing.expect_value(t, frame_get_height(frame), 2)
    testing.expect_value(t, frame_get_memory_format(frame), MemoryFormat.MEMORY_R8G8B8)
    testing.expect_value(t, frame_get_stride(frame), 9)

    want := [2][3][4]u8 {
        {{255, 0, 0, 255}, {0, 255, 0, 255}, {0, 0, 255, 255}},
        {{255, 255, 0, 255}, {0, 255, 255, 255}, {255, 0, 255, 255}},
    }
    for y in 0 ..< 2 {
        for x in 0 ..< 3 {
            testing.expect_value(t, pixel(frame, x, y), want[y][x])
        }
    }
    // Opaque RGB: no alpha, no premultiplication; sRGB colour.
    testing.expect(t, !bool(memory_format_has_alpha(.MEMORY_R8G8B8)), "R8G8B8 has alpha")
    testing.expect(t, bool(memory_format_has_alpha(.MEMORY_B8G8R8A8_PREMULTIPLIED)), "B8G8R8A8_PREMULTIPLIED has no alpha")
    testing.expect(t, bool(memory_format_is_premultiplied(.MEMORY_B8G8R8A8_PREMULTIPLIED)), "not premultiplied")
    testing.expect(t, !bool(memory_format_is_premultiplied(.MEMORY_R8G8B8A8)), "R8G8B8A8 is premultiplied")
    testing.expect_value(t, frame_get_color_mode(frame), ColorMode.SRGB)
}

@(test)
test_accepted_memory_formats_convert :: proc(t: ^testing.T) {
    loader := new_loader("px.png")
    defer gobj.object_unref(loader)
    loader_set_accepted_memory_formats(loader, {.R8G8B8A8})
    image, fail := load(loader)
    testing.expectf(t, image != nil, "load failed: %s", first_line(fail.message))
    if image == nil do return
    err: ^glib.Error
    frame := image_next_frame(image, &err)
    defer release(image, frame)
    testing.expect(t, frame != nil, "no frame")
    if frame == nil do return
    // The RGB8 PNG is converted to the one accepted format.
    testing.expect_value(t, frame_get_memory_format(frame), MemoryFormat.MEMORY_R8G8B8A8)
    testing.expect_value(t, frame_get_stride(frame), 12)
    testing.expect_value(t, pixel(frame, 1, 0), [4]u8{0, 255, 0, 255})
    testing.expect_value(t, pixel(frame, 2, 1), [4]u8{255, 0, 255, 255})
}

@(test)
test_jpeg_pixels :: proc(t: ^testing.T) {
    image, frame := load_first(t, "halves.jpg")
    if image == nil do return
    defer release(image, frame)

    testing.expect_value(t, image_get_mime_type(image), "image/jpeg")
    testing.expect_value(t, image_get_width(image), 24)
    testing.expect_value(t, image_get_height(image), 8)
    // Lossy: the left half is red and the right blue, within a few levels.
    left := pixel(frame, 3, 4)
    right := pixel(frame, 20, 4)
    testing.expectf(t, near(left, {255, 0, 0, 255}, 12), "left half is %v", left)
    testing.expectf(t, near(right, {0, 0, 255, 255}, 12), "right half is %v", right)
}

@(test)
test_svg_renders_and_scales :: proc(t: ^testing.T) {
    image, frame := load_first(t, "box.svg")
    if image == nil do return
    defer release(image, frame)

    testing.expect_value(t, image_get_mime_type(image), "image/svg+xml")
    testing.expect_value(t, image_get_width(image), 8)
    testing.expect_value(t, image_get_height(image), 4)
    testing.expect_value(t, frame_get_width(frame), 8)
    testing.expect_value(t, frame_get_height(frame), 4)
    testing.expect_value(t, pixel(frame, 4, 2), [4]u8{0x33, 0x66, 0x99, 255})

    // The SVG loader obeys a requested size; the rest of the loaders ignore it.
    request := frame_request_new()
    defer gobj.object_unref(request)
    frame_request_set_scale(request, 80, 40)
    err: ^glib.Error
    big := image_get_specific_frame(image, request, &err)
    testing.expectf(t, big != nil, "scaled frame: %s", first_line(take_error(err).message))
    if big == nil do return
    defer gobj.object_unref(big)
    testing.expect_value(t, frame_get_width(big), 80)
    testing.expect_value(t, frame_get_height(big), 40)
    testing.expect_value(t, pixel(big, 40, 20), [4]u8{0x33, 0x66, 0x99, 255})
}

@(test)
test_png_ignores_requested_scale :: proc(t: ^testing.T) {
    loader := new_loader("px.png")
    defer gobj.object_unref(loader)
    image, fail := load(loader)
    testing.expectf(t, image != nil, "load failed: %s", first_line(fail.message))
    if image == nil do return
    defer gobj.object_unref(image)
    request := frame_request_new()
    defer gobj.object_unref(request)
    frame_request_set_scale(request, 30, 20)
    err: ^glib.Error
    frame := image_get_specific_frame(image, request, &err)
    testing.expectf(t, frame != nil, "frame: %s", first_line(take_error(err).message))
    if frame == nil do return
    defer gobj.object_unref(frame)
    testing.expect_value(t, frame_get_width(frame), 3)
    testing.expect_value(t, frame_get_height(frame), 2)
}

// ---- open behaviours the documentation leaves ----

@(test)
test_exif_orientation_applied_by_default :: proc(t: ^testing.T) {
    // orient6.jpg is the 24x8 red|blue JPEG with EXIF Orientation 6 (rotate 90 degrees clockwise).
    image, frame := load_first(t, "orient6.jpg")
    if image == nil do return
    defer release(image, frame)

    testing.expect_value(t, image_get_transformation_orientation(image), 6)
    // The image and the frame are the displayed, rotated size, with the red half on top.
    testing.expect_value(t, image_get_width(image), 8)
    testing.expect_value(t, image_get_height(image), 24)
    testing.expect_value(t, frame_get_width(frame), 8)
    testing.expect_value(t, frame_get_height(frame), 24)
    top := pixel(frame, 4, 3)
    bottom := pixel(frame, 4, 20)
    testing.expectf(t, near(top, {255, 0, 0, 255}, 12), "top is %v", top)
    testing.expectf(t, near(bottom, {0, 0, 255, 255}, 12), "bottom is %v", bottom)
}

@(test)
test_exif_orientation_not_applied_when_disabled :: proc(t: ^testing.T) {
    loader := new_loader("orient6.jpg")
    defer gobj.object_unref(loader)
    loader_set_apply_transformations(loader, false)
    image, fail := load(loader)
    testing.expectf(t, image != nil, "load failed: %s", first_line(fail.message))
    if image == nil do return
    err: ^glib.Error
    frame := image_next_frame(image, &err)
    defer release(image, frame)
    testing.expect(t, frame != nil, "no frame")
    if frame == nil do return
    // The caller corrects: the orientation is still reported, the pixels are as stored.
    testing.expect_value(t, image_get_transformation_orientation(image), 6)
    testing.expect_value(t, image_get_width(image), 24)
    testing.expect_value(t, image_get_height(image), 8)
    testing.expect_value(t, frame_get_width(frame), 24)
    testing.expect_value(t, frame_get_height(frame), 8)
    left := pixel(frame, 3, 4)
    testing.expectf(t, near(left, {255, 0, 0, 255}, 12), "left is %v", left)
}

@(test)
test_orientation_without_exif_is_one :: proc(t: ^testing.T) {
    image, frame := load_first(t, "halves.jpg")
    if image == nil do return
    defer release(image, frame)
    testing.expect_value(t, image_get_transformation_orientation(image), 1)
}

@(test)
test_animation_frame_delays :: proc(t: ^testing.T) {
    image, frame := load_first(t, "anim.gif")
    if image == nil do return
    defer release(image, frame)
    testing.expect_value(t, image_get_mime_type(image), "image/gif")

    // Delays are microseconds: the GIF has 70, 30 and 120 ms frames, red, green, blue.
    testing.expect_value(t, frame_get_delay(frame), 70_000)
    colours := [3][4]u8{{255, 0, 0, 255}, {0, 128, 0, 255}, {0, 0, 255, 255}} // ImageMagick's green is 0,128,0
    delays := [3]i64{70_000, 30_000, 120_000}
    testing.expect_value(t, pixel(frame, 1, 1), colours[0])
    for i in 1 ..< 3 {
        err: ^glib.Error
        f := image_next_frame(image, &err)
        testing.expectf(t, f != nil, "frame %d: %s", i, first_line(take_error(err).message))
        if f == nil do return
        testing.expect_value(t, frame_get_delay(f), delays[i])
        testing.expect_value(t, pixel(f, 1, 1), colours[i])
        gobj.object_unref(f)
    }
    // By default the animation loops: the frame after the last is the first again.
    err: ^glib.Error
    again := image_next_frame(image, &err)
    testing.expectf(t, again != nil, "fourth frame: %s", first_line(take_error(err).message))
    if again == nil do return
    defer gobj.object_unref(again)
    testing.expect_value(t, frame_get_delay(again), 70_000)
    testing.expect_value(t, pixel(again, 1, 1), colours[0])
}

@(test)
test_animation_without_loop_ends :: proc(t: ^testing.T) {
    image, frame := load_first(t, "anim.gif")
    if image == nil do return
    defer release(image, frame)
    request := frame_request_new()
    defer gobj.object_unref(request)
    frame_request_set_loop_animation(request, false)

    count := 0
    fail: Failure
    for count < 10 {
        err: ^glib.Error
        f := image_get_specific_frame(image, request, &err)
        if f == nil {
            fail = take_error(err)
            break
        }
        count += 1
        gobj.object_unref(f)
    }
    // The first next_frame above was the first frame; the request continues from there.
    testing.expectf(t, count >= 2 && count <= 3, "%d frames before the end", count)
    testing.expect_value(t, fail.domain, LOADER_ERROR())
    testing.expect_value(t, fail.code, int(LoaderError.NO_MORE_FRAMES))
}

@(test)
test_png_has_one_frame :: proc(t: ^testing.T) {
    image, first := load_first(t, "px.png")
    if image == nil do return
    defer release(image, first)
    // A raster still has exactly one frame, even with looping on: the second call fails.
    err: ^glib.Error
    second := image_next_frame(image, &err)
    fail := take_error(err)
    testing.expect(t, second == nil, "a PNG has a second frame")
    if second != nil {
        gobj.object_unref(second)
        return
    }
    testing.expect_value(t, fail.domain, LOADER_ERROR())
    testing.expect_value(t, fail.code, int(LoaderError.NO_MORE_FRAMES))
}

@(test)
test_svg_frames_repeat :: proc(t: ^testing.T) {
    image, first := load_first(t, "box.svg")
    if image == nil do return
    defer release(image, first)
    // The SVG loader never runs out: every call renders the image again, with no delay, so a
    // caller that loops "until NO_MORE_FRAMES" must stop on delay 0.
    for _ in 0 ..< 3 {
        err: ^glib.Error
        again := image_next_frame(image, &err)
        testing.expectf(t, again != nil, "next frame: %s", first_line(take_error(err).message))
        if again == nil do return
        testing.expect_value(t, frame_get_delay(again), 0)
        gobj.object_unref(again)
    }
}

@(test)
test_metadata_keys :: proc(t: ^testing.T) {
    image, frame := load_first(t, "meta.png")
    if image == nil do return
    defer release(image, frame)

    keys := image_get_metadata_keys(image)
    testing.expect(t, keys != nil, "no metadata keys")
    if keys == nil do return
    defer glib.strfreev(keys)
    found := make(map[string]string, context.temp_allocator)
    list := cast([^]cstring)keys
    for i := 0; list[i] != nil; i += 1 {
        value := image_get_metadata_key_value(image, list[i])
        testing.expectf(t, value != nil, "key %s has no value", list[i])
        if value == nil do continue
        found[strings.clone(string(list[i]), context.temp_allocator)] = strings.clone(string(value), context.temp_allocator)
        glib.free(rawptr(value))
    }
    // PNG text chunks come through as keys, with their text as the value.
    testing.expect_value(t, found["Author"], "Hyperquader")
    testing.expect_value(t, found["Title"], "six pixels")
    testing.expect_value(t, len(found), 2)

    missing := image_get_metadata_key_value(image, "No such key")
    testing.expect(t, missing == nil, "an absent key has a value")
    if missing != nil do glib.free(rawptr(missing))
}

@(test)
test_no_metadata_gives_no_keys :: proc(t: ^testing.T) {
    image, frame := load_first(t, "px.png")
    if image == nil do return
    defer release(image, frame)
    keys := image_get_metadata_keys(image)
    if keys == nil do return
    defer glib.strfreev(keys)
    testing.expect(t, cast([^]cstring)keys != nil && (cast([^]cstring)keys)[0] == nil, "px.png reports metadata")
}

@(test)
test_frame_colour_and_density :: proc(t: ^testing.T) {
    image, frame := load_first(t, "px.png")
    if image == nil do return
    defer release(image, frame)
    // sRGB: neither a CICP nor an ICC profile accompanies the frame.
    cicp := frame_get_color_cicp(frame)
    testing.expect(t, cicp == nil, "an sRGB PNG has a CICP")
    if cicp != nil do cicp_free(cicp)
    icc := frame_get_color_icc_profile(frame)
    testing.expect(t, icc == nil, "an sRGB PNG has an ICC profile")
    if icc != nil do glib.bytes_unref(icc)

    details := frame_get_details(frame)
    testing.expect(t, details != nil, "no frame details")
    if details != nil {
        defer gobj.object_unref(details)
        density := frame_details_get_pixel_density(details)
        // A PNG without a pHYs chunk has no density.
        testing.expect(t, density == nil, "a PNG without pHYs has a pixel density")
        if density != nil do gobj.object_unref(density)
    }
}

@(test)
test_pixel_density_conversion :: proc(t: ^testing.T) {
    density := pixel_density_new(72, .INCH, 36, .INCH)
    defer gobj.object_unref(density)
    testing.expect_value(t, pixel_density_get_x_value(density), 72)
    testing.expect_value(t, pixel_density_get_x_unit(density), PhysicalDimensionUnit.INCH)
    testing.expect_value(t, pixel_density_get_y_value(density), 36)
    per_m := pixel_density_convert(density, .METER)
    defer gobj.object_unref(per_m)
    testing.expect_value(t, pixel_density_get_x_unit(per_m), PhysicalDimensionUnit.METER)
    x := pixel_density_get_x_value(per_m)
    testing.expectf(t, x > 2834 && x < 2835, "72 per inch is %v per metre", x)
}

// ---- input kinds ----

@(test)
test_bytes_input :: proc(t: ^testing.T) {
    bytes := glib.bytes_new(raw_data(PX_PNG), glib.size(len(PX_PNG)))
    defer glib.bytes_unref(bytes)
    loader := loader_new_for_bytes(bytes)
    defer gobj.object_unref(loader)
    image, fail := load(loader)
    testing.expectf(t, image != nil, "load failed: %s", first_line(fail.message))
    if image == nil do return
    err: ^glib.Error
    frame := image_next_frame(image, &err)
    defer release(image, frame)
    testing.expect(t, frame != nil, "no frame")
    if frame == nil do return
    testing.expect_value(t, image_get_mime_type(image), "image/png")
    testing.expect_value(t, pixel(frame, 0, 1), [4]u8{255, 255, 0, 255})
}

@(test)
test_stream_input :: proc(t: ^testing.T) {
    // A memory stream over JPEG bytes: the format is found from the content, not a file name.
    bytes := glib.bytes_new(raw_data(HALVES_JPG), glib.size(len(HALVES_JPG)))
    defer glib.bytes_unref(bytes)
    stream := gio.memory_input_stream_new_from_bytes(bytes)
    defer gobj.object_unref(stream)
    loader := loader_new_for_stream(stream)
    defer gobj.object_unref(loader)
    image, fail := load(loader)
    testing.expectf(t, image != nil, "load failed: %s", first_line(fail.message))
    if image == nil do return
    err: ^glib.Error
    frame := image_next_frame(image, &err)
    defer release(image, frame)
    testing.expect(t, frame != nil, "no frame")
    if frame == nil do return
    testing.expect_value(t, image_get_mime_type(image), "image/jpeg")
    testing.expect_value(t, frame_get_width(frame), 24)
    right := pixel(frame, 20, 4)
    testing.expectf(t, near(right, {0, 0, 255, 255}, 12), "right half is %v", right)
}

@(test)
test_file_stream_input :: proc(t: ^testing.T) {
    path := fmt.ctprintf("%spx.png", FIXTURES)
    file := gio.file_new_for_path(path)
    defer gobj.object_unref(file)
    err: ^glib.Error
    stream := gio.file_read(file, nil, &err)
    testing.expectf(t, stream != nil, "file_read: %s", take_error(err).message)
    if stream == nil do return
    defer gobj.object_unref(stream)
    loader := loader_new_for_stream(cast(^gio.InputStream)stream)
    defer gobj.object_unref(loader)
    image, fail := load(loader)
    testing.expectf(t, image != nil, "load failed: %s", first_line(fail.message))
    if image == nil do return
    frame := image_next_frame(image, &err)
    defer release(image, frame)
    testing.expect(t, frame != nil, "no frame")
    if frame == nil do return
    testing.expect_value(t, pixel(frame, 1, 1), [4]u8{0, 255, 255, 255})
}

// ---- async and cancellation ----

@(test)
test_async_load_and_frame :: proc(t: ^testing.T) {
    loader := new_loader("px.png")
    defer gobj.object_unref(loader)
    a: Async
    loader_load_async(loader, nil, on_done, &a)
    if !wait(t, &a) do return
    err: ^glib.Error
    image := loader_load_finish(loader, a.result, &err)
    gobj.object_unref(a.result)
    testing.expectf(t, image != nil, "load_finish: %s", first_line(take_error(err).message))
    if image == nil do return
    defer gobj.object_unref(image)

    b: Async
    image_next_frame_async(image, nil, on_done, &b)
    if !wait(t, &b) do return
    frame := image_next_frame_finish(image, b.result, &err)
    gobj.object_unref(b.result)
    testing.expectf(t, frame != nil, "next_frame_finish: %s", first_line(take_error(err).message))
    if frame == nil do return
    defer gobj.object_unref(frame)
    testing.expect_value(t, pixel(frame, 0, 0), [4]u8{255, 0, 0, 255})
}

@(test)
test_cancelled_load_reports_cancelled :: proc(t: ^testing.T) {
    loader := new_loader("px.png")
    defer gobj.object_unref(loader)
    cancellable := gio.cancellable_new()
    defer gobj.object_unref(cancellable)
    gio.cancellable_cancel(cancellable)

    a: Async
    loader_load_async(loader, cancellable, on_done, &a)
    if !wait(t, &a) do return
    err: ^glib.Error
    image := loader_load_finish(loader, a.result, &err)
    gobj.object_unref(a.result)
    fail := take_error(err)
    testing.expect(t, image == nil, "a cancelled load returned an image")
    if image != nil {
        gobj.object_unref(image)
        return
    }
    testing.expect_value(t, fail.domain, gio.io_error_quark())
    testing.expect_value(t, fail.code, int(gio.IOErrorEnum.CANCELLED))
}

@(test)
test_cancelled_frame_reports_cancelled :: proc(t: ^testing.T) {
    image, frame := load_first(t, "anim.gif")
    if image == nil do return
    defer release(image, frame)
    cancellable := gio.cancellable_new()
    defer gobj.object_unref(cancellable)
    gio.cancellable_cancel(cancellable)

    a: Async
    image_next_frame_async(image, cancellable, on_done, &a)
    if !wait(t, &a) do return
    err: ^glib.Error
    next := image_next_frame_finish(image, a.result, &err)
    gobj.object_unref(a.result)
    fail := take_error(err)
    testing.expect(t, next == nil, "a cancelled frame request returned a frame")
    if next != nil {
        gobj.object_unref(next)
        return
    }
    testing.expect_value(t, fail.domain, gio.io_error_quark())
    testing.expect_value(t, fail.code, int(gio.IOErrorEnum.CANCELLED))
}

@(test)
test_mime_types_async :: proc(t: ^testing.T) {
    a: Async
    loader_get_mime_types_async(nil, on_done, &a)
    if !wait(t, &a) do return
    err: ^glib.Error
    types := loader_get_mime_types_finish(a.result, &err)
    gobj.object_unref(a.result)
    testing.expectf(t, types != nil, "finish: %s", first_line(take_error(err).message))
    if types == nil do return
    defer glib.strfreev(types)
    testing.expect_value(t, string((cast([^]cstring)types)[0]) != "", true)
}

// ---- sandbox ----

@(test)
test_bwrap_sandbox_selector :: proc(t: ^testing.T) {
    loader := new_loader("px.png")
    defer gobj.object_unref(loader)
    loader_set_sandbox_selector(loader, .BWRAP)
    image, fail := load(loader)
    testing.expectf(t, image != nil, "bubblewrap load failed: %s", first_line(fail.message))
    if image != nil do gobj.object_unref(image)
}

// ---- encoding ----

@(test)
test_creator_round_trip :: proc(t: ^testing.T) {
    err: ^glib.Error
    creator := creator_new("image/png", &err)
    testing.expectf(t, creator != nil, "creator_new: %s", first_line(take_error(err).message))
    if creator == nil do return
    defer gobj.object_unref(creator)

    pixels := [12]u8{255, 0, 0, 0, 255, 0, 0, 0, 255, 10, 20, 30} // 2x2, RGB
    data := glib.bytes_new(&pixels[0], glib.size(len(pixels)))
    defer glib.bytes_unref(data)
    new_frame := creator_add_frame(creator, 2, 2, .MEMORY_R8G8B8, data, &err)
    testing.expectf(t, new_frame != nil, "add_frame: %s", first_line(take_error(err).message))
    if new_frame == nil do return
    defer gobj.object_unref(new_frame)
    testing.expect(t, creator_add_metadata_key_value(creator, "Author", "Hyperquader") != false, "add_metadata_key_value refused")

    encoded := creator_create(creator, &err)
    testing.expectf(t, encoded != nil, "create: %s", first_line(take_error(err).message))
    if encoded == nil do return
    defer gobj.object_unref(encoded)
    png := encoded_image_get_data(encoded)

    loader := loader_new_for_bytes(png)
    defer gobj.object_unref(loader)
    image, fail := load(loader)
    testing.expectf(t, image != nil, "decoding the encoded image: %s", first_line(fail.message))
    if image == nil do return
    frame := image_next_frame(image, &err)
    defer release(image, frame)
    testing.expect(t, frame != nil, "no frame")
    if frame == nil do return
    testing.expect_value(t, image_get_mime_type(image), "image/png")
    testing.expect_value(t, image_get_width(image), 2)
    testing.expect_value(t, pixel(frame, 0, 0), [4]u8{255, 0, 0, 255})
    testing.expect_value(t, pixel(frame, 1, 1), [4]u8{10, 20, 30, 255})
    value := image_get_metadata_key_value(image, "Author")
    testing.expect(t, value != nil, "the Author text did not round-trip")
    if value != nil {
        testing.expect_value(t, string(value), "Hyperquader")
        glib.free(rawptr(value))
    }
}

// ---- failure ----

@(test)
test_missing_file_fails :: proc(t: ^testing.T) {
    file := gio.file_new_for_path("/nonexistent/odin-glycin/none.png")
    defer gobj.object_unref(file)
    loader := loader_new(file)
    defer gobj.object_unref(loader)
    image, fail := load(loader)
    testing.expect(t, image == nil, "a missing file loaded")
    if image != nil {
        gobj.object_unref(image)
        return
    }
    // Not a G_IO_ERROR_NOT_FOUND: glycin reports the failure in its own domain.
    testing.expect_value(t, fail.domain, LOADER_ERROR())
    testing.expect_value(t, fail.code, int(LoaderError.FAILED))
    testing.expect(t, strings.contains(fail.message, "No such file"), "the message does not name the cause")
}

@(test)
test_unknown_format_error_code :: proc(t: ^testing.T) {
    for name in ([]string{"unknown.bin", "empty.png"}) {
        loader := new_loader(name)
        image, fail := load(loader)
        gobj.object_unref(loader)
        testing.expectf(t, image == nil, "%s loaded", name)
        if image != nil {
            gobj.object_unref(image)
            continue
        }
        testing.expect_value(t, fail.domain, LOADER_ERROR())
        testing.expect_value(t, fail.code, int(LoaderError.UNKNOWN_IMAGE_FORMAT))
        testing.expectf(t, strings.has_prefix(fail.message, "Unknown image format"), "%s: %s", name, first_line(fail.message))
    }
}

// A corrupt image makes the loader fail, in the load or at the frame, and the test process
// carries on: the same loader class then decodes a good image.
@(test)
test_hostile_images_fail_and_host_survives :: proc(t: ^testing.T) {
    hostile := []string{"truncated.png", "damaged.png", "huge.png", "truncated.jpg"}
    for name in hostile {
        loader := new_loader(name)
        image, fail := load(loader)
        gobj.object_unref(loader)
        if image == nil {
            testing.expectf(t, fail.message != "", "%s: failed without a message", name)
            continue
        }
        // The header was readable; the data is not.
        err: ^glib.Error
        frame := image_next_frame(image, &err)
        testing.expectf(t, frame == nil, "%s: decoded a frame from corrupt data", name)
        if frame != nil {
            gobj.object_unref(frame)
        } else {
            fail = take_error(err)
            testing.expectf(t, fail.message != "", "%s: frame failed without a message", name)
        }
        gobj.object_unref(image)
    }
    // Still alive, and the loaders still work.
    image, frame := load_first(t, "px.png")
    if image == nil do return
    defer release(image, frame)
    testing.expect_value(t, pixel(frame, 0, 0), [4]u8{255, 0, 0, 255})
}

// A fixed pseudo-random set of single-byte corruptions of a PNG and a JPEG: each decodes or
// fails, none takes the host down or hangs.
@(test)
test_mutated_images_do_not_hurt_the_host :: proc(t: ^testing.T) {
    sources := [2][]byte{PX_PNG, HALVES_JPG}
    seed: u32 = 12345
    next :: proc(seed: ^u32) -> u32 {
        seed^ = seed^ * 1664525 + 1013904223
        return seed^ >> 8
    }
    for src, which in sources {
        for round in 0 ..< 12 {
            mutant := make([]byte, len(src))
            defer delete(mutant)
            copy(mutant, src)
            for _ in 0 ..< 1 + round % 3 {
                mutant[int(next(&seed)) % len(mutant)] = u8(next(&seed))
            }
            bytes := glib.bytes_new(raw_data(mutant), glib.size(len(mutant)))
            loader := loader_new_for_bytes(bytes)
            glib.bytes_unref(bytes)
            image, fail := load(loader)
            gobj.object_unref(loader)
            if image == nil {
                testing.expectf(t, fail.message != "", "source %d round %d: failed without a message", which, round)
                continue
            }
            err: ^glib.Error
            frame := image_next_frame(image, &err)
            if frame != nil {
                gobj.object_unref(frame)
            } else {
                take_error(err)
            }
            gobj.object_unref(image)
        }
    }
}

// The size limits belong to glycin and are not settable (README, "Behaviour the headers
// leave open"): a frame over 8 GB is refused, and a loader gets 80% of the available memory,
// at most 16 GB. Decoding such an image needs that much memory and many seconds, so it runs
// only when asked (make test-big sets GLYCIN_TEST_BIG).
@(test)
test_oversized_image_is_refused :: proc(t: ^testing.T) {
    path := os.get_env("GLYCIN_TEST_BIG", context.temp_allocator)
    if path == "" do return
    file := gio.file_new_for_path(strings.clone_to_cstring(path, context.temp_allocator))
    defer gobj.object_unref(file)
    loader := loader_new(file)
    defer gobj.object_unref(loader)
    image, fail := load(loader)
    if image == nil {
        testing.expectf(t, fail.message != "", "failed without a message")
        return
    }
    defer gobj.object_unref(image)
    err: ^glib.Error
    frame := image_next_frame(image, &err)
    testing.expect(t, frame == nil, "a frame over the size limit was returned")
    if frame != nil {
        gobj.object_unref(frame)
        return
    }
    fail = take_error(err)
    testing.expectf(t, fail.message != "", "failed without a message")
    fmt.println("oversized image refused:", first_line(fail.message))
}

// MemoryFormatSelection is a bit_set of the C bits (docs/DECISIONS.md §2): the size is that of
// the C enum (4 bytes) and member i is bit i of GlyMemoryFormatSelection (glycin.h), 23 in all.
@(test)
test_memory_format_selection_bits_match_the_header :: proc(t: ^testing.T) {
    bits :: proc(s: MemoryFormatSelection) -> u32 {
        return transmute(u32)s
    }
    testing.expect_value(t, size_of(MemoryFormatSelection), 4)
    count := 0
    for member in MemoryFormatSelectionBit {
        testing.expect_value(t, bits({member}), u32(1) << u32(member))
        count += 1
    }
    testing.expect_value(t, count, 23)
    testing.expect_value(t, bits({.B8G8R8A8_PREMULTIPLIED}), 1)
    testing.expect_value(t, bits({.R8G8B8, .G8}), 1 << 7 | 1 << 19)
    testing.expect_value(t, bits({.G16}), 1 << 22)
}
