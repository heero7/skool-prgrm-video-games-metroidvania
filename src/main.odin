package main

import "core:flags"
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
//Color :: rl.Color

Direction :: enum {
    Up,
    Right,
    Down,
    Left,
}

// Convenience vectors
UP :: Vec2{0, -1}
RIGHT :: Vec2{1, 0}
DOWN :: Vec2{0, 1}
LEFT :: Vec2{-1, 0}

PLAYER_SAFE_RESET_TIME :: 1

Game_State :: struct {
    player_id:        Entity_Id,
    player_mv_state:  Player_Move_State,
    safe_position:    Vec2,
    safe_reset_timer: f32,
    camera:           rl.Camera2D,
    entities:         [dynamic]Entity,
    solid_tiles:      [dynamic]Rect,
    spikes:           map[Entity_Id]Direction,
    debug_shapes:     [dynamic]Debug_Shape,
}

Entity_Id :: distinct int

Entity_Behaviors :: enum {
    Walk,
    Flip_At_Wall,
    Flip_At_Edge,
}

/*
   Holds the data for an animation from a texture
   image.

   size: frame size
   offset: where to start drawing the image. 
   start: 0 index beginning frame number
   end: 0 index final frame
   row: 0 index row from the texture image
   time: how long this frame lasts
 */
Animation :: struct {
    size:   Vec2,
    offset: Vec2,
    start:  int,
    end:    int,
    row:    int,
    time:   f32,
}

/*
 Allow the Rect to be accessed without calling player.Rect.
 i.e. player.x => is the same as player.Rect.x
 */
Entity :: struct {
    using collider:             Rect,
    vel:                        Vec2,
    move_speed:                 f32,
    jump_force:                 f32,
    on_enter, on_stay, on_exit: proc(self_id, other_id: Entity_Id),
    entity_ids:                 map[Entity_Id]time.Time,
    flags:                      bit_set[Entity_Flags],
    behaviors:                  bit_set[Entity_Behaviors],
    health:                     int,
    max_health:                 int,
    on_hit_damage:              int,
    debug_color:                rl.Color,
    texture:                    ^rl.Texture,
    animations:                 map[string]Animation,
    current_anim_name:          string,
    current_anim_frame:         int,
    animation_timer:            f32,
}

gs: Game_State

/*
   Used for moving entities, static ones will not 
   actually allow this to happen.
 */
player_on_enter :: proc(self_id, other_id: Entity_Id) {
    player := entity_get(self_id)
    other := entity_get(other_id)

    if other.on_hit_damage > 0 {
        player.health -= other.on_hit_damage
    }
}

spike_on_enter :: proc(self_id, other_id: Entity_Id) {
    me := entity_get(self_id)
    them := entity_get(other_id)

    if other_id == gs.player_id {
        them.x = gs.safe_position.x
        them.y = gs.safe_position.y

        them.vel = 0

        gs.safe_reset_timer = PLAYER_SAFE_RESET_TIME
        gs.player_mv_state = .Uncontrollable
        switch_animation(them, "idle")
    }

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

    // Load textures
    player_tex := rl.LoadTexture("assets/textures/player_120x80.png")

    player_anim_idle := Animation {
        size   = {120, 80},
        offset = {52, 42},
        start  = 0,
        end    = 9,
        row    = 0,
        time   = 0.15,
    }

    player_anim_run := Animation {
        size   = {120, 80},
        offset = {52, 42},
        start  = 0,
        end    = 9,
        row    = 2,
        time   = 0.15,
    }

    player_anim_jump := Animation {
        size   = {120, 80},
        offset = {52, 42},
        start  = 0,
        end    = 2,
        row    = 1,
        time   = 0.15,
    }

    player_anim_jump_fall_inbetween := Animation {
        size   = {120, 80},
        offset = {52, 42},
        start  = 3,
        end    = 4,
        row    = 1,
        time   = 0.15,
    }

    player_anim_fall := Animation {
        size   = {120, 80},
        offset = {52, 42},
        start  = 5,
        end    = 7,
        row    = 1,
        time   = 0.15,
    }

    // Can create your own scope so that similarly used variables (like x & y) are
    // able to be used. Pretty neat feature.
    {
        level_data, ok := os.read_entire_file("data/simple_level.dat")
        assert(ok, "Failed to read level data.")

        x, y: f32
        for v in level_data {
            switch v {
            case 'e':
                en := entity_create(
                    Entity {
                        collider = Rect{x, y, TILE_SIZE, TILE_SIZE},
                        move_speed = 50,
                        flags = {.Debug_Draw},
                        behaviors = {.Walk, .Flip_At_Wall, .Flip_At_Edge},
                        health = 2,
                        max_health = 2,
                        on_hit_damage = 1,
                        debug_color = rl.RED,
                    },
                )
            case '\n':
                y += TILE_SIZE
                x = 0
                continue
            case '#':
                append(&gs.solid_tiles, Rect{x, y, TILE_SIZE, TILE_SIZE})

            case 'P':
                gs.player_id = entity_create(
                    {
                        x = x,
                        y = y,
                        width = 16,
                        height = 38,
                        flags = {.Debug_Draw},
                        debug_color = rl.GREEN,
                        jump_force = 650,
                        move_speed = 280,
                        on_enter = player_on_enter,
                        health = 5,
                        max_health = 5,
                        texture = &player_tex,
                        current_anim_name = "idle",
                    },
                )

                // load the player to load the animations
                p := entity_get(gs.player_id)

                p.animations["idle"] = player_anim_idle
                p.animations["run"] = player_anim_run
                p.animations["jump"] = player_anim_jump
                p.animations["jump_fall_inbetween"] =
                    player_anim_jump_fall_inbetween
                p.animations["fall"] = player_anim_fall
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
                        on_hit_damage = 1,
                        flags = {.Kinematic, .Debug_Draw, .Immortal},
                        debug_color = rl.YELLOW,
                    },
                )
                gs.spikes[id] = .Up
            case '>':
                id := entity_create(
                    Entity {
                        collider = Rect{x, y, SPIKES_DEPTH, SPIKES_BREADTH},
                        on_enter = spike_on_enter,
                        on_hit_damage = 1,
                        flags = {.Kinematic, .Debug_Draw, .Immortal},
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
                        on_hit_damage = 1,
                        flags = {.Kinematic, .Debug_Draw, .Immortal},
                        debug_color = rl.YELLOW,
                    },
                )
                gs.spikes[id] = .Left
            case 'v':
                id := entity_create(
                    Entity {
                        collider = Rect{x, y, SPIKES_BREADTH, SPIKES_DEPTH},
                        on_enter = spike_on_enter,
                        on_hit_damage = 1,
                        flags = {.Kinematic, .Debug_Draw, .Immortal},
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

        player := entity_get(gs.player_id)


        player_update(&gs, dt)
        entity_update(gs.entities[:], dt)
        physics_update(gs.entities[:], gs.solid_tiles[:], dt)
        behavior_update(gs.entities[:], gs.solid_tiles[:], dt)

        /*
	   Determines the last "safe area" for the player to return to.
	   It will set the position as a Vec2. It will only ever be on
	   the ground. It checks 4 positions, the corner "legs" of the bounding
	   box (the first two checks that check for ground, the point down), 
	   the top corners of the bounding box, (check above).

	   If at least one raycast doesn't detect ground it will use the last
	   position.
	   If at least one raycast detects a hazard, it will use the last
	   position.
	 */
        if .Grounded in player.flags {
            pos := Vec2{player.x, player.y}
            size := Vec2{player.width, player.height}

            targets := make([dynamic]Rect, context.temp_allocator)
            // remember an entity can only be a spike,player,enemy
            for e, i in gs.entities {
                if Entity_Id(i) == gs.player_id do continue
                if .Dead not_in e.flags {
                    append(&targets, e.collider)
                }
            }

            safety_check: {
                _, hit_ground_left := raycast(
                    pos + {0, size.y},
                    DOWN * 2,
                    gs.solid_tiles[:],
                )
                if !hit_ground_left do break safety_check

                _, hit_ground_right := raycast(
                    pos + size,
                    DOWN * 2,
                    gs.solid_tiles[:],
                )
                if !hit_ground_right do break safety_check

                _, hit_entity_left := raycast(
                    pos,
                    LEFT * TILE_SIZE,
                    targets[:],
                )
                if hit_entity_left do break safety_check

                _, hit_entity_right := raycast(
                    pos + {size.x, 0},
                    RIGHT * TILE_SIZE,
                    targets[:],
                )
                if hit_entity_right do break safety_check

                gs.safe_position = pos
            }
        }

        // End Process
        rl.BeginDrawing()
        rl.BeginMode2D(gs.camera)
        rl.ClearBackground(BG_COLOR)

        for rect in gs.solid_tiles {
            rl.DrawRectangleRec(rect, rl.WHITE)
            rl.DrawRectangleLinesEx(rect, 1, rl.GRAY)
        }

        for &e in gs.entities {
            if e.texture != nil {
                e.animation_timer -= dt

                anim := e.animations[e.current_anim_name]

                src := Rect {
                    f32(e.current_anim_frame) * anim.size.x,
                    f32(anim.row) * anim.size.y,
                    anim.size.x,
                    anim.size.y,
                }
                if .Left in e.flags {
                    src.width = -src.width
                }

                rl.DrawTextureRec(
                    e.texture^,
                    src,
                    {e.x, e.y} - anim.offset,
                    rl.WHITE,
                )
            }

            if .Debug_Draw in e.flags && .Dead not_in e.flags {
                //rl.DrawRectangleLinesEx(e.collider, 1, e.debug_color)
                // i think we can do both
                debug_draw_rect(
                    {e.collider.x, e.collider.y},
                    {e.width, e.height},
                    1,
                    e.debug_color,
                )
            }
        }

        // Draw the safe position
        debug_draw_rect(
            gs.safe_position,
            {player.width, player.height},
            1,
            rl.BLUE,
        )

        // Draw the player after the level tiles!
        //rl.DrawRectangleLinesEx(player.collider, 1, rl.GREEN)

        // Draw the current FPS
        rl.DrawFPS(20, 20)

        for d in gs.debug_shapes {
            switch v in d {
            case Debug_Line:
                rl.DrawLineEx(v.start, v.end, v.thickness, v.color)
            case Debug_Rect:
                rl.DrawRectangleLinesEx(
                    Rect{v.pos.x, v.pos.y, v.size.x, v.size.y},
                    v.thickness,
                    v.color,
                )
            case Debug_Circle:
                rl.DrawCircleLinesV(v.pos, v.radius, v.color)
            }
        }
        rl.EndMode2D()
        rl.EndDrawing()

        // clear the array of debug_shapes after drawing
        clear(&gs.debug_shapes)
    }
}
