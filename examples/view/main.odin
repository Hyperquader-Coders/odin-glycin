// view: show an image file in a GTK window, decoded by libglycin's sandboxed loaders.
//   view <file> [seconds]     closes after <seconds> if given (a smoke run on a private display)
package main

import "core:fmt"
import "core:os"
import "core:strconv"

import gio "glib:gio"
import glib "glib:glib"
import gobj "glib:gobject"

import gtk "gtk4:gtk4"
import "glycin:glycin"
import "glycin:glycin_gtk4"

loop: ^glib.MainLoop

quit :: proc "c" (_: glib.pointer) -> glib.boolean {
    glib.main_loop_quit(loop)
    return false
}

on_close :: proc "c" (_: glib.pointer, _: glib.pointer) -> glib.boolean {
    glib.main_loop_quit(loop)
    return false
}

main :: proc() {
    if len(os.args) < 2 || len(os.args) > 3 {
        fmt.eprintln("usage: view <file> [seconds]")
        os.exit(2)
    }
    seconds := 0
    if len(os.args) == 3 {
        n, ok := strconv.parse_int(os.args[2])
        if !ok || n < 1 {
            fmt.eprintln("view: seconds must be a positive number")
            os.exit(2)
        }
        seconds = n
    }

    file := gio.file_new_for_path(fmt.ctprint(os.args[1]))
    defer gobj.object_unref(file)
    loader := glycin.loader_new(file)
    defer gobj.object_unref(loader)

    err: ^glib.Error
    image := glycin.loader_load(loader, &err)
    if image == nil {
        fmt.eprintfln("view: %s: %s", os.args[1], err.message)
        glib.error_free(err)
        os.exit(1)
    }
    defer gobj.object_unref(image)
    frame := glycin.image_next_frame(image, &err)
    if frame == nil {
        fmt.eprintfln("view: %s: %s", os.args[1], err.message)
        glib.error_free(err)
        os.exit(1)
    }
    defer gobj.object_unref(frame)

    if !gtk.init_check() {
        fmt.eprintln("view: no display")
        os.exit(1)
    }
    texture := glycin_gtk4.frame_get_texture(frame)
    defer gobj.object_unref(texture)

    window := cast(^gtk.Window)gtk.window_new()
    gtk.window_set_default_size(window, 640, 480)
    gtk.window_set_child(window, gtk.picture_new_for_paintable(cast(^gtk.Paintable)texture))
    gobj.signal_connect_data(window, "close-request", cast(gobj.Callback)on_close, nil, nil, {})
    gtk.window_present(window)

    loop = glib.main_loop_new(nil, false)
    if seconds > 0 do glib.timeout_add_seconds(u32(seconds), quit, nil)
    glib.main_loop_run(loop)
    glib.main_loop_unref(loop)
    gtk.window_destroy(window)
}
