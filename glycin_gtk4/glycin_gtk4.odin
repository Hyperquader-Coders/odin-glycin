package glycin_gtk4

import glycin "glycin:glycin"
import gtk4 "gtk4:gtk4"

@(default_calling_convention = "c")
foreign glycin_gtk4_runic {
    @(link_name = "gly_gtk_frame_get_texture")
    frame_get_texture :: proc(frame: ^glycin.Frame) -> ^gtk4.Texture ---

}

foreign import glycin_gtk4_runic "system:glycin-gtk4-2"

