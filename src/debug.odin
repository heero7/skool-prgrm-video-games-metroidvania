package main

import f "core:fmt"
import rl "vendor:raylib"

Debug_Line :: struct {
    start, end: Vec2,
    thickness:  f32,
    color:      rl.Color,
}

Debug_Circle :: struct {
    pos:    Vec2,
    radius: f32,
    color:  rl.Color,
}

Debug_Rect :: struct {
    pos, size: Vec2,
    thickness: f32,
    color:     rl.Color,
}

// A union of all of these types. The size of this struct will be the size of
// the largest struct. At this time that would be Line & Circle
Debug_Shape :: union {
    Debug_Line,
    Debug_Circle,
    Debug_Rect,
}

// Noting how large the structs are. FYI -> the largest a Debug_Shape will be is
// 24 bytes
//main :: proc() {
//    f.println("bytes Vec2 -> {}", size_of(Vec2))
//    f.println("bytes f32 -> {}", size_of(f32))
//    f.println("bytes rl.Color -> {}", size_of(rl.Color))
//    f.println("bytes Debug_Circle -> {}", size_of(Debug_Circle))
//}

debug_draw_line :: proc(start, end: Vec2, thickness: f32, color: rl.Color) {
    append(&gs.debug_shapes, Debug_Line{start, end, thickness, color})
}

debug_draw_rect :: proc(pos, size: Vec2, thickness: f32, color: rl.Color) {
    append(&gs.debug_shapes, Debug_Rect{pos, size, thickness, color})
}

debug_draw_circle :: proc(pos: Vec2, radius: f32, color: rl.Color) {
    append(&gs.debug_shapes, Debug_Circle{pos, radius, color})
}
