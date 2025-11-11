package main

import "core:fmt"
import rl "vendor:raylib"

Player_Move_State :: enum {
  Uncontrollable,
  Idle,
  Run,
  Jump,
  Fall,
  Attack,
}

/*
   Performs updates on the player character.
 */
player_update :: proc(gs: ^Game_State, dt: f32) {
  player := entity_get(gs.player_id)

  gs.jump_timer -= dt
  gs.coyote_timer -= dt

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
    try_attack(gs, player)
  case .Run:
    if in_x == 0 {
      gs.player_mv_state = .Idle
      switch_animation(player, "idle")
    }
    try_jump(gs, player)
    try_attack(gs, player)
  case .Jump:
    if player.vel.y >= 0 {
      gs.player_mv_state = .Fall
      switch_animation(player, "fall")
    }
    // variable jump
    if rl.IsKeyReleased(.U) && Entity_Flags.Grounded not_in player.flags {
      player.vel.y *= 0.5
    }

    try_attack(gs, player)
  case .Fall:
    if .Grounded in player.flags {
      gs.player_mv_state = .Idle
      switch_animation(player, "idle")
    }
    try_attack(gs, player)
  case .Attack:
    if .Grounded in player.flags {
      player.vel.x = 0
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
  if rl.IsKeyPressed(.U) {
    gs.jump_timer = JUMP_TIME
  }


  if Entity_Flags.Grounded in p.flags {
    gs.coyote_timer = COYOTE_TIME
  }

  if (Entity_Flags.Grounded in p.flags || gs.coyote_timer > 0) &&
     gs.jump_timer > 0 {
    p.vel.y = -p.jump_force
    p.flags -= {.Grounded}
    gs.player_mv_state = .Jump
    switch_animation(p, "jump")
  }
}

try_attack :: proc(gs: ^Game_State, p: ^Entity) {
  if rl.IsKeyPressed(.I) {
    switch_animation(p, "attack")
    gs.player_mv_state = .Attack
  }
}

player_on_finish_attack :: proc(gs: ^Game_State, p: ^Entity) {
  switch_animation(p, "idle")
  gs.player_mv_state = .Fall
}

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

player_attack_callback :: proc(gs: ^Game_State, p: ^Entity) {
  center := Vec2{p.x, p.y}
  center += {.Left in p.flags ? -30 + p.collider.width : 30, 20}

  for &e, i in gs.entities {
    id := Entity_Id(i)

    if id == gs.player_id do continue
    if .Dead in e.flags do continue
    if .Immortal in e.flags do continue


    if rl.CheckCollisionCircleRec(center, 25, e.collider) {
      entity_damage(Entity_Id(i), 1)
    }
  }
}
