package main

import "core:fmt"
import "core:os"
import "core:time"
import rl "vendor:raylib"

// Constants
WINDOW_WIDTH :: 1280
WINDOW_HEIGHT :: 720
WINDOW_TITLE :: "MetroidVania-Slice"
BG_COLOR :: rl.BLACK
ZOOM :: 2
TILE_SIZE :: 16
TARGET_FPS :: 60
SPIKES_BREADTH :: 16
SPIKES_DEPTH :: 12
SPIKES_DIFF :: TILE_SIZE - SPIKES_DEPTH

// Type Aliases (reduce typing!) Note, they must come after rl definition
Vec2 :: rl.Vector2
Rect :: rl.Rectangle

Direction :: enum {
    Up,
    Right,
    Down,
    Left,
}

Game_State :: struct {
    camera:      rl.Camera2D,
    entities:    [dynamic]Entity,
    solid_tiles: [dynamic]Rect,
    spikes:      map[Entity_Id]Direction,
}

Entity_Id :: distinct int

/*
 Allow the Rect to be accessed without calling player.Rect.
 i.e. player.x => is the same as player.Rect.x
 */
Entity :: struct {
    using collider:             Rect,
    vel:                        Vec2,
    move_speed:                 f32,
    jump_force:                 f32,
    is_grounded:                bool, // todo: delete
    is_dead:                    bool, // todo delete
    on_enter, on_stay, on_exit: proc(self_id, other_id: Entity_Id),
    entity_ids:                 map[Entity_Id]time.Time,
    flags:                      bit_set[Entity_Flags],
    debug_color:                rl.Color,
}

gs: Game_State

spike_on_enter :: proc(self_id, other_id: Entity_Id) {
    me := entity_get(self_id)
    them := entity_get(other_id)

    dir := gs.spikes[self_id]

    switch dir {
    case .Up:
        if them.vel.y > 0 {
            fmt.println("spikes pointing up")
        }
    case .Right:
        if them.vel.x < 0 {
            fmt.println("spikes pointing right")
        }
    case .Down:
        if them.vel.y < 0 {
            fmt.println("spikes pointing down")
        }
    case .Left:
        if them.vel.x > 0 {
            fmt.println("spikes pointing left")
        }
    }
}

main :: proc() {
    rl.InitWindow(WINDOW_WIDTH, WINDOW_HEIGHT, WINDOW_TITLE)
    rl.SetTargetFPS(TARGET_FPS)

    gs = Game_State {
        camera = rl.Camera2D{zoom = ZOOM},
    }

    player_id: Entity_Id

    // Can create your own scope so that similarly used variables (like x & y) are
    // able to be used. Pretty neat feature.
    {
        level_data, ok := os.read_entire_file("data/simple_level.dat")
        assert(ok, "Failed to read level data.")

        x, y: f32
        for v in level_data {
            switch v {
            case '\n':
                y += TILE_SIZE
                x = 0
                continue
            case '#':
                append(&gs.solid_tiles, Rect{x, y, TILE_SIZE, TILE_SIZE})

            case 'P':
                player_id = entity_create(
                    {
                        x = x,
                        y = y,
                        width = 16,
                        height = 38,
                        jump_force = 650,
                        move_speed = 280,
                    },
                )
            case '^':
                id := entity_create(
                    Entity {
                        collider = Rect {
                            x,
                            y + SPIKES_DIFF,
                            SPIKES_BREADTH,
                            SPIKES_DEPTH,
                        },
                        on_enter = spike_on_enter,
                        flags = {.Kinematic, .Debug_Draw},
                        debug_color = rl.YELLOW,
                    },
                )
                gs.spikes[id] = .Up
            case '>':
                id := entity_create(
                    Entity {
                        collider = Rect{x, y, SPIKES_DEPTH, SPIKES_BREADTH},
                        on_enter = spike_on_enter,
                        flags = {.Kinematic, .Debug_Draw},
                        debug_color = rl.YELLOW,
                    },
                )
                gs.spikes[id] = .Right
            case '<':
                id := entity_create(
                    Entity {
                        collider = Rect {
                            x + SPIKES_DIFF,
                            y,
                            SPIKES_DEPTH,
                            SPIKES_BREADTH,
                        },
                        on_enter = spike_on_enter,
                        flags = {.Kinematic, .Debug_Draw},
                        debug_color = rl.YELLOW,
                    },
                )
                gs.spikes[id] = .Left
            case 'v':
                id := entity_create(
                    Entity {
                        collider = Rect{x, y, SPIKES_BREADTH, SPIKES_DEPTH},
                        on_enter = spike_on_enter,
                        flags = {.Kinematic, .Debug_Draw},
                        debug_color = rl.YELLOW,
                    },
                )
                gs.spikes[id] = .Down

            }
            x += TILE_SIZE
        }
    }

    num := len(&gs.solid_tiles)
    assert(num > 0, "Failed to populate level tiles")


    for !rl.WindowShouldClose() {
        dt := rl.GetFrameTime()
        input_x: f32

        player := entity_get(player_id)

        if (rl.IsKeyDown(.D)) do input_x += 1
        if (rl.IsKeyDown(.A)) do input_x -= 1

        if rl.IsKeyPressed(.SPACE) && player.is_grounded {
            player.vel.y = -player.jump_force
            player.is_grounded = false
        }

        player.vel.x = input_x * player.move_speed

        physics_update(gs.entities[:], gs.solid_tiles[:], dt)

        // End Process
        rl.BeginDrawing()
        rl.BeginMode2D(gs.camera)
        rl.ClearBackground(BG_COLOR)

        for rect in gs.solid_tiles {
            rl.DrawRectangleRec(rect, rl.WHITE)
            rl.DrawRectangleLinesEx(rect, 1, rl.GRAY)
        }

        for e in gs.entities {
            if .Debug_Draw in e.flags {
                rl.DrawRectangleLinesEx(e.collider, 1, e.debug_color)
            }
        }

        // Draw the player after the level tiles!
        rl.DrawRectangleLinesEx(player.collider, 1, rl.GREEN)
        rl.EndMode2D()
        rl.EndDrawing()
    }
}
