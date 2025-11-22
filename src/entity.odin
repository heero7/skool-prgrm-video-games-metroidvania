package main

import "core:fmt"
import "core:time"
import rl "vendor:raylib"

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
  hit_timer:                  f32,
  hit_duration:               f32,
  hit_response:               Entity_Hit_Response,
  on_death:                   proc(p: ^Entity, gs: ^Game_State),
}

Entity_Hit_Response :: enum {
  Stop,
  Knockback,
}

Entity_Flags :: enum {
  Grounded,
  Dead,
  Kinematic,
  Debug_Draw,
  Left,
  Immortal,
  Frozen,
}

Entity_Id :: distinct int

Entity_Behaviors :: enum {
  Walk,
  Flip_At_Wall,
  Flip_At_Edge,
}

// this adds the entity you create to the entities array!
entity_create :: proc(entity: Entity) -> Entity_Id {
  // pull out the pointers. Find any that are "dead" and replace them.
  for &e, i in gs.entities {
    if .Dead in e.flags {
      e = entity
      e.flags -= {.Dead} // remove the Entity_Flags.Dead flag from the entity
      return Entity_Id(i)
    }
  }

  // if we didn't find anything, add a new one to the back.
  index := len(&gs.entities)
  append(&gs.entities, entity)

  return Entity_Id(index)
}

entity_get :: proc(id: Entity_Id) -> ^Entity {
  count := len(gs.entities)
  if count == 0 || int(id) > count {
    return nil
  }
  return &gs.entities[id]
}

entity_update :: proc(gs: ^Game_State, dt: f32) {
  for &e in gs.entities {
    if e.health == 0 && .Immortal not_in e.flags {
      e.flags += {.Dead}
      if e.on_death != nil {
        e->on_death(gs)
      }
    }

    if e.hit_timer > 0 {
      e.hit_timer -= dt
      if e.hit_timer <= 0 {
        #partial switch e.hit_response {
        // the reverse is in entity_hit, there we start this.
        // this allows the entity to do what it was before (i.e walk)
        case .Stop:
          e.behaviors += {.Walk}
          e.flags -= {.Frozen}
        }
      }
    }

    // Animation handling
    if len(e.animations) > 0 {
      anim := e.animations[e.current_anim_name]

      // Only move the animation timer if we aren't frozen
      if .Frozen not_in e.flags {
        e.animation_timer -= dt
      }

      if e.animation_timer <= 0 {
        e.current_anim_frame += 1

        if .Loop in anim.flags {
          if e.current_anim_frame > anim.end {
            e.current_anim_frame = anim.start
          }
        } else {
          if e.current_anim_frame > anim.end {
            e.current_anim_frame -= 1
            if anim.on_finish != nil {
              anim.on_finish(gs, &e)
            }
          }
        }

        e.animation_timer = anim.time
      }

      // Events
      for &event in anim.timed_events {
        if event.timer > 0 {
          event.timer -= dt
          if event.timer <= 0 {
            event.callback(gs, &e)
          }
        }
      }
    }
  }
}

entity_damage :: proc(id: Entity_Id, amount: int) {
  e := entity_get(id)
  e.health -= amount
  if e.health <= 0 {
    e.flags += {.Dead}
  }
}

entity_hit :: proc(id: Entity_Id, force := Vec2{}) {
  e := entity_get(id)

  e.hit_timer = e.hit_duration

  switch e.hit_response {
  case .Stop:
    e.behaviors -= {.Walk}
    e.flags += {.Frozen}
    e.vel = 0
  case .Knockback:
    e.vel += force
  }
}

/*
   Switches the animation for an entity.
   e: The entity to switch animations.
   name: The name of the animation to switch to.
 */
switch_animation :: proc(e: ^Entity, name: string) {
  e.current_anim_name = name
  anim := e.animations[name]
  e.animation_timer = anim.time
  e.current_anim_frame = anim.start

  // restart the animation event timers
  for &e in anim.timed_events {
    e.timer = e.duration
  }
}
