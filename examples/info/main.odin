// info: print what libglycin reports about image files, without decoding the pixels twice.
//   info <file>...
package main

import "core:fmt"
import "core:os"

import gio "glib:gio"
import glib "glib:glib"
import gobj "glib:gobject"

import "glycin:glycin"

main :: proc() {
    if len(os.args) < 2 {
        fmt.eprintln("usage: info <file>...")
        os.exit(2)
    }
    failed := false
    for path in os.args[1:] {
        if !describe(path) do failed = true
    }
    if failed do os.exit(1)
}

describe :: proc(path: string) -> bool {
    cpath := fmt.ctprint(path)
    file := gio.file_new_for_path(cpath)
    defer gobj.object_unref(file)
    loader := glycin.loader_new(file)
    defer gobj.object_unref(loader)

    err: ^glib.Error
    image := glycin.loader_load(loader, &err)
    if image == nil {
        fmt.eprintfln("%s: %s", path, err.message)
        glib.error_free(err)
        return false
    }
    defer gobj.object_unref(image)

    fmt.printfln("%s: %s %dx%d, orientation %d", path, glycin.image_get_mime_type(image), glycin.image_get_width(image),
        glycin.image_get_height(image), glycin.image_get_transformation_orientation(image))

    keys := glycin.image_get_metadata_keys(image)
    if keys != nil {
        defer glib.strfreev(keys)
        list := ([^]cstring)(keys)
        for i := 0; list[i] != nil; i += 1 {
            key := list[i]
            value := glycin.image_get_metadata_key_value(image, key)
            fmt.printfln("  %s = %s", key, value)
            glib.free(rawptr(value))
        }
    }

    // One pass over the frames: without looping, the call after the last frame fails with
    // NO_MORE_FRAMES.
    request := glycin.frame_request_new()
    defer gobj.object_unref(request)
    glycin.frame_request_set_loop_animation(request, false)
    for n in 1 ..= 100000 {
        frame := glycin.image_get_specific_frame(image, request, &err)
        if frame == nil {
            ok := glib.error_matches(err, glycin.loader_error_quark(), i32(glycin.LoaderError.NO_MORE_FRAMES))
            if !ok do fmt.eprintfln("%s: %s", path, err.message)
            glib.error_free(err)
            return bool(ok)
        }
        fmt.printfln("  frame %d: %dx%d stride %d %v delay %d us", n, glycin.frame_get_width(frame),
            glycin.frame_get_height(frame), glycin.frame_get_stride(frame), glycin.frame_get_memory_format(frame),
            glycin.frame_get_delay(frame))
        delay := glycin.frame_get_delay(frame)
        gobj.object_unref(frame)
        // The SVG loader never reports NO_MORE_FRAMES; a frame without a delay is a still.
        if delay == 0 do return true
    }
    return true
}
