package main

import "core:math/linalg"
import "core:math/rand"


behavior_update :: proc(
  entities: []Entity,
  static_colliders: []Rect,
  dt: f32,
) {
  for &e in entities {
    if .Dead in e.flags do continue
    if .Walk in e.behaviors {
      if .Left in e.flags {
        e.vel.x = -e.move_speed
      } else {
        e.vel.x = e.move_speed
      }
    }

    // send raycasts either left or right to check for a wall
    if .Flip_At_Wall in e.behaviors {
      if .Left in e.flags {
        if _, ok := raycast(
          {e.x + e.width / 2, e.y + e.height / 2},
          {-e.width / 2 - COLLISION_EPSILON, 0},
          static_colliders,
        ); ok {
          e.flags -= {.Left}
          e.vel.x = 0
        }
      } else {
        if _, ok := raycast(
          {e.x + e.width / 2, e.y + e.height / 2},
          {e.width / 2 + COLLISION_EPSILON, 0},
          static_colliders,
        ); ok {
          e.flags += {.Left}
          e.vel.x = 0
        }
      }
    }

    if .Flip_At_Edge in e.behaviors && .Grounded in e.flags {
      if .Left in e.flags {
        start := Vec2{e.x, e.y + e.height / 2}
        magnitude := Vec2{0, e.height / 2 + COLLISION_EPSILON}
        if _, ok := raycast(start, magnitude, static_colliders); !ok {
          e.flags -= {.Left}
          e.vel.x = 0
        }
      } else {
        start := Vec2{e.x + e.width, e.y + e.height / 2}
        magnitude := Vec2{0, e.height / 2 + COLLISION_EPSILON}
        if _, ok := raycast(start, magnitude, static_colliders); !ok {
          e.flags += {.Left}
          e.vel.x = 0
        }
      }
    }

    if .Wander in e.behaviors {
      e.wander_timer -= dt

      _, has_dest := e.destination.?

      if e.wander_timer < 0 && !has_dest {
        // pick a destination
        // 1. in a level
        // 2. not in a wall

        ray_start := rect_center(e.collider)
        ray_dir := rand.uint32() % 2 == 0 ? LEFT : RIGHT
        ray_length := rand.float32_range(20, 150)
        ray_end := ray_start + ray_dir * ray_length

        within_left := ray_end.x > gs.level.level_min.x + e.collider.width
        within_right := ray_end.x < gs.level.level_max.x - e.collider.width

        within_bounds := within_left && within_right

        if within_bounds {
          _, hit := raycast(ray_start, ray_dir * ray_length, static_colliders)
          if !hit {
            e.destination = ray_end
          }
        }
      }
    }

    if .Hop in e.behaviors {
      e.hop_timer -= dt

      if dest, ok := e.destination.?; ok && e.hop_timer < 0 {
        dir := linalg.normalize0(dest - rect_center(e.collider))

        e.vel.x = dir.x * 200
        e.vel.y = UP.y * 200
        e.destination = nil

        e.hop_timer = rand.float32_range(1, 3)
        switch_animation(&e, "hop")

        if e.vel.x < 0 {
          e.flags += {.Left}
        } else {
          e.flags -= {.Left}
        }
      } else if .Grounded in e.flags {
        e.vel.x = 0
        switch_animation(&e, "idle")
      }
    }

    if .Charge_At_Player in e.behaviors {
      is_charging := e.charge_timer > 0

      if is_charging {
        e.charge_timer -= dt

        if e.charge_timer < 0 {
          is_charging = false
          e.charge_cooldown_timer = 4
          e.vel.x = 0
          e.charge_dir = nil
        }
      } else {
        e.charge_cooldown_timer -= dt
      }

      can_charge := e.charge_cooldown_timer < 0

      if can_charge && !is_charging {
        player := entity_get(gs.player_id)
        player_pos := rect_center(player.collider)

        pos := rect_center(e.collider)

        if linalg.distance(player_pos, pos) < 200 {
          e.charge_dir = linalg.normalize0(player_pos - pos)
          e.charge_timer = 0.35
        }
      }

      if charge_dir, ok := e.charge_dir.?; ok {
        e.vel.x = charge_dir.x * 300
        if charge_dir.x > 0 {
          e.flags += {.Left}
        } else {
          e.flags -= {.Left}
        }
      }
    }
  }
}
