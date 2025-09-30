package main

import "core:fmt"
import "core:os"
import rl "vendor:raylib"

// Constants
WINDOW_WIDTH :: 1280
WINDOW_HEIGHT :: 720
WINDOW_TITLE :: "MetroidVania-Slice"
BG_COLOR :: rl.BLACK
ZOOM :: 2
TILE_SIZE :: 16

// Type Aliases (reduce typing!) Note, they must come after rl definition
Vec2 :: rl.Vector2
Rect :: rl.Rectangle

// User defined structs
Player :: struct {
    // Allow the Rect to be accessed without calling player.Rect.
    // i.e. player.x => is the same as player.Rect.x
    using collider: Rect,
    vel:            Vec2,
    move_speed:     f32,
}

main :: proc() {
    rl.InitWindow(WINDOW_WIDTH, WINDOW_HEIGHT, WINDOW_TITLE)

    camera := rl.Camera2D {
        zoom = ZOOM,
    }

    player: Player = {
        x          = 100,
        y          = 100,
        width      = 16,
        height     = 38,
        move_speed = 280,
    }


    // Can create your own scope so that similarly used variables (like x & y) are
    // able to be used. Pretty neat feature.
    solid_tiles: [dynamic]Rect
    {
        level_data, ok := os.read_entire_file("data/simple_level.dat")
        assert(ok, "Failed to read level data.")

        x, y: f32
        for val in level_data {
            if val == '\n' {
                y += TILE_SIZE
                x = 0
                continue
            }
            if val == '#' {
                append(&solid_tiles, Rect{x, y, TILE_SIZE, TILE_SIZE})
            }
            x += TILE_SIZE
        }
    }

    num := len(solid_tiles)
    assert(num > 0, "Failed to populate level tiles")


    for !rl.WindowShouldClose() {
        // Process
        // Before drawing, calculate movements, any deltas, input, etc.
        dt := rl.GetFrameTime()
        input_x: f32 // Note that this will start as 0.
        if (rl.IsKeyDown(.D)) do input_x += 1
        if (rl.IsKeyDown(.A)) do input_x -= 1

        player.vel.x = input_x * player.move_speed
        player.x += player.vel.x * dt
        // End Process
        rl.BeginDrawing()
        rl.BeginMode2D(camera)
        rl.ClearBackground(BG_COLOR)

        for rect in solid_tiles {
            rl.DrawRectangleRec(rect, rl.WHITE)
            rl.DrawRectangleLinesEx(rect, 1, rl.GRAY)
        }

        // Draw the player after the level tiles!
        rl.DrawRectangleLinesEx(player.collider, 1, rl.GREEN)
        rl.EndMode2D()
        rl.EndDrawing()
    }
}
