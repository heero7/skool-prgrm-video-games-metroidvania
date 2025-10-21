package main

Entity_Flags :: enum {
    Grounded,
    Dead,
    Kinematic,
    Debug_Draw,
}

// this adds the entity you create to the entities array!
entity_create :: proc(entity: Entity) -> Entity_Id {
    // pull out the pointers. Find any that are "dead" and replace them.
    for &e, i in gs.entities {
        if e.is_dead {
            e = entity
            e.is_dead = false
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
