package main

import "core:fmt"

Entity_Flags :: enum {
  Grounded,
  Dead,
  Kinematic,
  Debug_Draw,
  Left,
  Immortal,
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
  if int(id) > len(gs.entities) {
    return nil
  }
  return &gs.entities[id]
}

entity_update :: proc(gs: ^Game_State, dt: f32) {
  for &e, i in gs.entities {
    if e.health == 0 && .Immortal not_in e.flags {
      e.flags += {.Dead}
    }

    // Animation handling
    if len(e.animations) > 0 {
      anim := e.animations[e.current_anim_name]

      e.animation_timer -= dt
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
