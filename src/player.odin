package main

import rl "vendor:raylib"

Player_Move_State :: enum {
    Uncontrollable,
    Idle,
    Run,
    Jump,
    Fall,
}

/*
   Performs updates on the player character.
 */
player_update :: proc(gs: ^Game_State, dt: f32) {
    player := entity_get(gs.player_id)

    in_x: f32
    if (rl.IsKeyDown(.T)) do in_x += 1
    if (rl.IsKeyDown(.R)) do in_x -= 1

    player.vel.x = in_x * player.move_speed

    switch gs.player_mv_state {
    case .Uncontrollable:
        gs.safe_reset_timer -= dt
        player.vel.x = 0
        player.vel.y = 0
        if gs.safe_reset_timer <= 0 {
            gs.player_mv_state = .Idle
            switch_animation(player, "idle")
        }
    case .Idle:
        try_run(gs, player)
        try_jump(gs, player)
    case .Run:
        if in_x == 0 {
            gs.player_mv_state = .Idle
            switch_animation(player, "idle")
        }
        try_jump(gs, player)
    case .Jump:
        if player.vel.y >= 0 {
            gs.player_mv_state = .Fall
            switch_animation(player, "fall")
        }
    case .Fall:
        if .Grounded in player.flags {
            gs.player_mv_state = .Idle
            switch_animation(player, "idle")
        }
    }
}

try_run :: proc(gs: ^Game_State, p: ^Entity) {
    if p.vel.x != 0 && .Grounded in p.flags {
        gs.player_mv_state = .Run
        switch_animation(p, "run")
    }
}

try_jump :: proc(gs: ^Game_State, p: ^Entity) {
    if rl.IsKeyPressed(.U) && .Grounded in p.flags {
        p.vel.y = -p.jump_force
        p.flags -= {.Grounded}
        gs.player_mv_state = .Jump
        switch_animation(p, "jump")
    }
}
