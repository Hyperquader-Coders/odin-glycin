#+test
package glycin_gtk4

import "core:fmt"
import "core:strings"
import "core:testing"

import gio "glib:gio"
import glib "glib:glib"
import gobj "glib:gobject"

import gtk4 "gtk4:gtk4"
import glycin "glycin:glycin"

// Run by make test under xvfb-run, against amber-glycin's libglycin-gtk4 and amber-gtk4's
// GTK 4.16 (which libglycin-gtk4 is built for). GLYCIN_DATA_DIR points at the staged loaders.

// Version recorded in README.md: "**Bound version:** X.Y.Z".
README :: #load("../README.md", string)

// The staged glycin-gtk4-2.pc's Version, passed by the Makefile.
GLYCIN_VERSION :: #config(GLYCIN_VERSION, "")

FIXTURES :: #directory + "/../fixtures/"

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

// Loads a fixture's first frame; the caller unrefs both.
first_frame :: proc(t: ^testing.T, name: string) -> (image: ^glycin.Image, frame: ^glycin.Frame) {
    file := gio.file_new_for_path(fmt.ctprintf("%s%s", FIXTURES, name))
    defer gobj.object_unref(file)
    loader := glycin.loader_new(file)
    defer gobj.object_unref(loader)
    err: ^glib.Error
    image = glycin.loader_load(loader, &err)
    if image == nil {
        testing.expectf(t, false, "%s: %s", name, err.message)
        glib.error_free(err)
        return
    }
    frame = glycin.image_next_frame(image, &err)
    if frame == nil {
        testing.expectf(t, false, "%s: %s", name, err.message)
        glib.error_free(err)
        gobj.object_unref(image)
        image = nil
    }
    return
}

// A texture's pixels as GDK's default memory format: B, G, R, A premultiplied, 8 bits each.
bgra :: proc(texture: ^gtk4.Texture) -> []u8 {
    w, h := int(gtk4.gdk_texture_get_width(texture)), int(gtk4.gdk_texture_get_height(texture))
    data := make([]u8, w * h * 4, context.temp_allocator)
    gtk4.gdk_texture_download(texture, &data[0], glib.size(w * 4))
    return data
}

@(test)
test_readme_version_matches_staged_library :: proc(t: ^testing.T) {
    testing.expect(t, GLYCIN_VERSION != "", "GLYCIN_VERSION is not set: run the tests through make test")
    testing.expect_value(t, bound_version(), GLYCIN_VERSION)
}

@(test)
test_png_frame_becomes_texture :: proc(t: ^testing.T) {
    testing.expect(t, bool(gtk4.init_check()), "no display: run under xvfb-run")
    image, frame := first_frame(t, "px.png")
    if image == nil do return
    defer gobj.object_unref(image)
    defer gobj.object_unref(frame)

    texture := frame_get_texture(frame)
    testing.expect(t, texture != nil, "no texture")
    if texture == nil do return
    defer gobj.object_unref(texture)
    testing.expect(t, bool(gobj.type_check_instance_is_a(cast(^gobj.TypeInstance)texture, gtk4.TYPE_TEXTURE())), "not a GdkTexture")
    testing.expect_value(t, gtk4.gdk_texture_get_width(texture), 3)
    testing.expect_value(t, gtk4.gdk_texture_get_height(texture), 2)

    px := bgra(texture)
    // Row 0: red, green, blue; row 1: yellow, cyan, magenta.
    want := [6][4]u8 {
        {0, 0, 255, 255}, {0, 255, 0, 255}, {255, 0, 0, 255},
        {0, 255, 255, 255}, {255, 255, 0, 255}, {255, 0, 255, 255},
    }
    for p, i in want {
        got := [4]u8{px[i * 4], px[i * 4 + 1], px[i * 4 + 2], px[i * 4 + 3]}
        testing.expectf(t, got == p, "pixel %d is %v, want %v", i, got, p)
    }
}

@(test)
test_oriented_jpeg_becomes_rotated_texture :: proc(t: ^testing.T) {
    testing.expect(t, bool(gtk4.init_check()), "no display: run under xvfb-run")
    image, frame := first_frame(t, "orient6.jpg")
    if image == nil do return
    defer gobj.object_unref(image)
    defer gobj.object_unref(frame)
    texture := frame_get_texture(frame)
    testing.expect(t, texture != nil, "no texture")
    if texture == nil do return
    defer gobj.object_unref(texture)
    // EXIF orientation is applied before the texture is made: 24x8 is stored, 8x24 is shown.
    testing.expect_value(t, gtk4.gdk_texture_get_width(texture), 8)
    testing.expect_value(t, gtk4.gdk_texture_get_height(texture), 24)
}

@(test)
test_svg_frame_becomes_texture :: proc(t: ^testing.T) {
    testing.expect(t, bool(gtk4.init_check()), "no display: run under xvfb-run")
    image, frame := first_frame(t, "box.svg")
    if image == nil do return
    defer gobj.object_unref(image)
    defer gobj.object_unref(frame)
    texture := frame_get_texture(frame)
    testing.expect(t, texture != nil, "no texture")
    if texture == nil do return
    defer gobj.object_unref(texture)
    testing.expect_value(t, gtk4.gdk_texture_get_width(texture), 8)
    testing.expect_value(t, gtk4.gdk_texture_get_height(texture), 4)
    px := bgra(texture)
    // The SVG's #336699 fill, as B, G, R, A.
    got := [4]u8{px[0], px[1], px[2], px[3]}
    testing.expect_value(t, got, [4]u8{0x99, 0x66, 0x33, 255})
}
