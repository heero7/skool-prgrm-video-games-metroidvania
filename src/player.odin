package main

import "core:fmt"
import "core:math/linalg"
import rl "vendor:raylib"

Player_Move_State :: enum {
  Uncontrollable,
  Idle,
  Run,
  Jump,
  Fall,
  Attack,
  Attack_Cooldown,
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

  if player.vel.x > 0 do player.flags -= {.Left}
  if player.vel.x < 0 do player.flags += {.Left}

  if gs.attack_recovery_timer > 0 {
    gs.attack_recovery_timer -= dt
    player.vel *= 0.5
  }

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
  case .Attack_Cooldown:
    gs.attack_cooldown_timer -= dt
    if gs.attack_cooldown_timer <= 0 {
      gs.player_mv_state = .Idle
    }
    try_run(gs, player)
  }

  for spike in gs.spikes {
    if rl.CheckCollisionRecs(spike.collider, player.collider) {
      player.x = gs.safe_position.x
      player.y = gs.safe_position.y
      player.vel = 0
      gs.safe_reset_timer = PLAYER_SAFE_RESET_TIME
      gs.player_mv_state = .Uncontrollable
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
    gs.attack_cooldown_timer = ATTACK_COOLDOWN_DURATION
  }
}

player_on_finish_attack :: proc(gs: ^Game_State, p: ^Entity) {
  switch_animation(p, "idle")
  gs.player_mv_state = .Attack_Cooldown
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
      entity_damage(id, 1)

      a := rect_center(p.collider)
      b := rect_center(e.collider)

      dir := linalg.normalize0(b - a)

      p.vel.x = -dir.x * 500
      p.vel.y = -dir.y * 200 - 100

      gs.attack_recovery_timer = ATTACK_RECOVERY_DURATION

      entity_hit(id, dir * 500)
    }
  }

  for &falling_log in gs.falling_logs {
    if falling_log.state != .Default do continue

    log_center := rect_center(falling_log.collider)
    rope_pos := Vec2 {
      log_center.x,
      log_center.y - falling_log.collider.height / 2,
    }

    rect := Rect {
      rope_pos.x - 1,
      rope_pos.y - falling_log.rope_height,
      2,
      falling_log.rope_height - TILE_SIZE,
    }

    if rl.CheckCollisionCircleRec(center, 25, rect) {
      falling_log.state = .Falling
    }
  }
}
