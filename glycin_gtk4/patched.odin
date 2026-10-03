package glycin_gtk4

import glycin "glycin:glycin"
import gtk4 "gtk4:gtk4"

// Typed pins for the post-generation rules (docs/PATCHED.md). A regeneration that drops one
// fails to compile here.

// GdkTexture and GlyFrame come from their own bindings, not from this package.
@(private = "file")
patched_frame_get_texture: proc "c" (_: ^glycin.Frame) -> ^gtk4.Texture = frame_get_texture
