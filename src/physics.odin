package main

import "core:fmt"
import "core:time"
import rl "vendor:raylib"

PHYSICS_ITERATIONS :: 8
GRAVITY :: 5
TERMINAL_VELOCITY :: 1200

physics_update :: proc(entities: []Entity, static_colliders: []Rect, dt: f32) {
    for &entity, e_id in entities {
        entity_id := Entity_Id(e_id)

        if .Dead in entity.flags do continue

        if .Kinematic not_in entity.flags {
            // Iterate a couple of times for stability.
            for _ in 0 ..< PHYSICS_ITERATIONS {
                step := dt / PHYSICS_ITERATIONS

                entity.vel.y += GRAVITY

                if entity.vel.y > TERMINAL_VELOCITY {
                    entity.vel.y = TERMINAL_VELOCITY
                }
                // Like the sebastian lague physics tutorial, we
                // apply physics horizontally and vertically
                // at separate times

                // Handle vertical collisions first
                entity.y += entity.vel.y * step
                entity.is_grounded = false
                entity.flags -= {.Grounded}

                // static is not a keyword!
                for static in static_colliders {
                    // We have a collision, but we need to make sure that the collision is Vertical (Y)
                    // note: if there is a collision, no matter what we will break!
                    if rl.CheckCollisionRecs(entity.collider, static) {
                        // The if is handling when the collision is above or below the static collider
                        // Either way, no matter what we will set the velocity to 0
                        if entity.vel.y > 0 {
                            entity.is_grounded = true
                            entity.flags += {.Grounded}
                            entity.y = static.y - entity.height // todo(math): how can we draw this?
                            // ^^ I  think this is because we need to find the distance AWAY from the
                            // entity to start drawing.
                        } else {
                            entity.y = static.y + static.height
                        }

                        // No matter what set the velocity to zero and move on.
                        entity.vel.y = 0
                        break
                    }
                }

                entity.x += entity.vel.x * step
                for static in static_colliders {
                    if rl.CheckCollisionRecs(entity.collider, static) {
                        if entity.vel.x > 0 {
                            entity.x = static.x - entity.width
                        } else {
                            entity.x = static.x + static.width
                        }
                        entity.vel.x = 0
                        break
                    }
                }

                // Collision Events (on_enter, on_stay, on_exit)
                for &other, o_id in gs.entities {
                    other_id := Entity_Id(o_id)

                    if entity_id == other_id do continue

                    // collision detected
                    // which means we either started a new collision or we've
                    // continued to collide (enter or stay)

                    // continued, think of the collisions like this. If i the
                    // entity/entity_id am not in the OTHER entity (other,
                    // other_id).
                    if rl.CheckCollisionRecs(entity, other.collider) {
                        if entity_id not_in other.entity_ids {
                            other.entity_ids[entity_id] = time.now()

                            if other.on_enter != nil {
                                other.on_enter(other_id, entity_id)
                            }
                        } else {
                            if other.on_stay != nil {
                                other.on_stay(other_id, entity_id)
                            }
                        }
                    } else if entity_id in other.entity_ids {
                        // if we are not colliding, but were in the other
                        // entity's ids maps remove it
                        if other.on_exit != nil {
                            other.on_exit(other_id, entity_id)
                        }
                        delete_key(&other.entity_ids, entity_id)
                    }
                }
            }
        }
    }
}
