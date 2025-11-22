#+feature dynamic-literals
package main

import "core:encoding/json"
import "core:flags"
import "core:fmt"
import "core:log"
import "core:os"
import "core:slice"
import "core:strings"
import "core:time"
import rl "vendor:raylib"

// Constants
WINDOW_WIDTH :: 1280
WINDOW_HEIGHT :: 720
WINDOW_TITLE :: "MetroidVania-Slice"
BG_COLOR :: rl.Color{50, 44, 67, 255}
RENDER_WIDTH :: 640
RENDER_HEIGHT :: 360
ZOOM :: WINDOW_WIDTH / RENDER_WIDTH
TILE_SIZE :: 16
TARGET_FPS :: 60
SPIKES_BREADTH :: 16
SPIKES_DEPTH :: 12
SPIKES_DIFF :: TILE_SIZE - SPIKES_DEPTH
JUMP_TIME :: 0.2
COYOTE_TIME :: 0.15
ATTACK_COOLDOWN_DURATION :: 0.3
ATTACK_RECOVERY_DURATION :: 0.2

// Type Aliases (reduce typing!) Note, they must come after rl definition
Vec2 :: rl.Vector2
Rect :: rl.Rectangle
Snd :: rl.Sound
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

Enemy_Def :: struct {
  collider_size:       Vec2,
  move_speed:          f32,
  behaviors:           bit_set[Entity_Behaviors],
  health:              int,
  on_hit_damage:       int,
  texture:             rl.Texture2D,
  animations:          map[string]Animation,
  initial_animation:   string,
  hit_response:        Entity_Hit_Response,
  hit_duration:        f32,
  hit_knockback_force: f32,
}

Game_State :: struct {
  player_id:             Entity_Id,
  player_texture:        rl.Texture,
  player_mv_state:       Player_Move_State,
  safe_position:         Vec2,
  safe_reset_timer:      f32,
  camera:                rl.Camera2D,
  tileset_texture:       rl.Texture,
  level_definitions:     map[string]Level,
  level:                 ^Level,
  entities:              [dynamic]Entity,
  colliders:             [dynamic]Rect,
  tiles:                 [dynamic]Tile,
  bg_tiles:              [dynamic]Tile,
  spikes:                [dynamic]Spike,
  falling_logs:          [dynamic]Falling_Log,
  doors:                 [dynamic]Door,
  debug_shapes:          [dynamic]Debug_Shape,
  jump_timer:            f32,
  coyote_timer:          f32,
  enemy_definitions:     map[string]Enemy_Def,
  debug_draw_enabled:    bool,
  attack_cooldown_timer: f32,
  attack_recovery_timer: f32,
  sword_swoosh_snd:      Snd,
  sword_swoosh_snd_2:    Snd,
  sword_hit_soft_snd:    Snd,
  sword_hit_med_snd:     Snd,
  sword_hit_stone_snd:   Snd,
  player_jump_snd:       Snd,
}

Spike :: struct {
  collider: Rect,
  facing:   Direction,
}

Falling_Log :: struct {
  collider:    Rect,
  rope_height: f32,
  state:       enum {
    Default,
    Falling,
    Settled,
  },
}

Tile :: struct {
  pos: Vec2,
  src: Vec2,
  f:   u8,
}

/*
   Certain info required to know
   for animations.
 */
Animation_Flags :: enum {
  // Play once then stop
  Loop,
  // Loop + Ping_Pong will play fowards then backwards, then fowards, repeat.
  Ping_Pong,
}

Animation_Event :: struct {
  timer:    f32,
  duration: f32,
  callback: proc(gs: ^Game_State, e: ^Entity),
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
  size:         Vec2,
  offset:       Vec2,
  start:        int,
  end:          int,
  row:          int,
  time:         f32,
  flags:        bit_set[Animation_Flags],
  on_finish:    proc(gs: ^Game_State, e: ^Entity),
  timed_events: [dynamic]Animation_Event,
}

Ldtk_Data :: struct {
  levels: []Ldtk_Level,
}

Ldtk_Neighbors :: struct {
  levelIid: string,
  dir:      string,
}

Ldtk_Level :: struct {
  identifier:     string,
  iid:            string,
  layerInstances: []Ldtk_Layer_Instance,
  __neighbors:    []Ldtk_Neighbors,
  worldX, worldY: f32,
  pxWid, pxHei:   f32,
}

Ldtk_Layer_Instance :: struct {
  __identifier:    string,
  __type:          string,
  __cWid, __cHei:  int,
  intGridCsv:      []int,
  autoLayerTiles:  []Ldtk_Auto_Layer_Tile,
  entityInstances: []Ldtk_Entity,
}


Ldtk_Auto_Layer_Tile :: struct {
  src: Vec2,
  px:  Vec2,
  f:   u8,
}

Ldtk_Entity :: struct {
  iid:            string,
  __identifier:   string,
  __worldX:       f32,
  __worldY:       f32,
  __tags:         []string,
  width, height:  f32,
  fieldInstances: []Ldtk_Field_Instance,
}

Ldtk_Field_Instance :: struct {
  __identifier: string,
  __type:       string,
  __value:      Ldtk_Field_Instance_Value,
}

Ldtk_Field_Instance_Value :: union {
  Ldtk_Entity_Ref,
  bool,
  f32,
  int,
  string,
}

Ldtk_Entity_Ref :: struct {
  entityIid: string,
  layerIid:  string,
  levelIid:  string,
  worldIid:  string,
}

Door :: struct {
  iid:      string,
  rect:     Rect,
  to_level: string,
  to_iid:   string,
}

Level :: struct {
  iid:          string,
  name:         string,
  player_spawn: Maybe(Vec2),
  level_min:    Vec2,
  level_max:    Vec2,
  entities:     [dynamic]Entity,
  colliders:    [dynamic]Rect,
  bg_tiles:     [dynamic]Tile,
  tiles:        [dynamic]Tile,
  spikes:       [dynamic]Spike,
  falling_logs: [dynamic]Falling_Log,
  doors:        [dynamic]Door,
}

gs: ^Game_State

level_parse_and_store :: proc(gs: ^Game_State, level: ^Ldtk_Level) {
  l: Level

  l.iid = strings.clone(level.iid)
  l.name = strings.clone(level.identifier)

  l.level_min = {level.worldX, level.worldY}
  l.level_max = l.level_min + {level.pxWid, level.pxHei}

  // Iterate through layer instances
  for layer in level.layerInstances {
    switch layer.__identifier {
    case "Entities":
      for entity in layer.entityInstances {
        switch entity.__identifier {
        case "Player":
          l.player_spawn = Vec2{entity.__worldX, entity.__worldY}
        case "Door":
          ref := entity.fieldInstances[0].__value.(Ldtk_Entity_Ref)
          pos := Vec2{entity.__worldX, entity.__worldY}
          size := Vec2{entity.width, entity.height}

          side: Direction

          if entity.__worldX + entity.width == l.level_max.x {
            pos.x += 12
            side = .Right
            size.x = 4
          } else if entity.__worldX == l.level_min.x {
            side = .Left
            size.x = 4
          } else if entity.__worldY + entity.height == l.level_max.y {
            side = .Down
          }

          door := Door {
            rect     = {pos.x, pos.y, size.x, size.y},
            iid      = strings.clone(entity.iid),
            to_level = strings.clone(ref.levelIid),
            to_iid   = strings.clone(ref.entityIid),
          }

          append(&l.doors, door)
        case "Spikes":
          facing := Direction.Right
          px, py := entity.__worldX, entity.__worldY
          w, h := entity.width, entity.height

          switch entity.fieldInstances[0].__value {
          case "Up":
            facing = .Up
            py += SPIKES_DIFF
            h = SPIKES_DEPTH
          case "Right":
            facing = .Right
            w = SPIKES_DEPTH
          case "Down":
            facing = .Down
            h = SPIKES_DEPTH
          case "Left":
            facing = .Left
            w = SPIKES_DEPTH
            px += SPIKES_DIFF
          }
          append(
            &l.spikes,
            Spike {
              collider = {x = px, y = py, width = w, height = h},
              facing = facing,
            },
          )
        case "Falling_Log":
          append(
            &l.falling_logs,
            Falling_Log {
              collider = {
                x = entity.__worldX,
                y = entity.__worldY,
                width = entity.width,
                height = entity.height,
              },
            },
          )
        }

        if slice.contains(entity.__tags, "Enemy") {
          def := &gs.enemy_definitions[entity.__identifier]

          enemy := Entity {
            collider = {
              x = entity.__worldX,
              y = entity.__worldY,
              width = def.collider_size.x,
              height = def.collider_size.y,
            },
            move_speed = def.move_speed,
            behaviors = def.behaviors,
            health = def.health,
            on_hit_damage = def.on_hit_damage,
            texture = &def.texture,
            animations = def.animations,
            current_anim_name = def.initial_animation,
            hit_response = def.hit_response,
            hit_duration = def.hit_duration,
            debug_color = rl.RED,
            flags = {.Debug_Draw},
          }

          append(&l.entities, enemy)
        }
      }
    case "Collision":
      solid_tiles := make([dynamic]Rect, context.temp_allocator)
      x, y: f32
      for v, i in layer.intGridCsv {
        if v != 0 {
          append(&solid_tiles, Rect{x, y, TILE_SIZE, TILE_SIZE})
        }

        x += TILE_SIZE

        /*
	       This is looking for the end of the row.
	       It is looking to do (n-1+1) % n to determine when we
	       just did the last item in the row (since this is 0
	       indexed).

	       i.e. if there are 26 columns in each row, then 0 -> 24, would
	       not ever set this to true. On i = 25, it would set it to true.
	       25 + 1 % 26 => 0. 25 would also represent the last item to
	       process on that row.
	     */
        if (i + 1) % layer.__cWid == 0 {
          y += TILE_SIZE
          x = 0
        }
      }

      wide_rect := solid_tiles[0]
      // instead of single rects, we will have rects consolidated into
      // larger rects. i.e.this means instead of drawing 100 squares, maybe
      // we draw only 4 recs.
      wide_rects := make([dynamic]Rect, context.temp_allocator)
      for i in 1 ..< len(solid_tiles) {
        rect := solid_tiles[i]

        // check if the next square and this square overlap
        // if they do, increase the size of wide_rect
        if rect.x == wide_rect.x + wide_rect.width {
          wide_rect.width += TILE_SIZE
        } else {
          append(&wide_rects, wide_rect)
          wide_rect = rect
        }
      }
      append(&wide_rects, wide_rect)

      /* 
       Right now the we can further improve this optimization by
       also grouping by the y coordinate.
      */
      slice.sort_by(wide_rects[:], proc(a, b: Rect) -> bool {
        if a.x != b.x do return a.x < b.x
        return a.y < b.y
      })

      // Do a similar rectangle add but going vertical.
      // Instead of just comparing width and x values, match
      // the y + height
      big_rect := wide_rects[0]
      for i in 1 ..< len(wide_rects) {
        rect := wide_rects[i]

        if rect.x == big_rect.x &&
           rect.width == big_rect.width &&
           big_rect.y + big_rect.height == rect.y {
          big_rect.height += TILE_SIZE
        } else {
          big_rect.x += level.worldX
          big_rect.y += level.worldY
          append(&l.colliders, big_rect)
          big_rect = rect
        }
      }

      big_rect.x += level.worldX
      big_rect.y += level.worldY
      append(&l.colliders, big_rect)

      for at in layer.autoLayerTiles {
        append(&l.tiles, Tile{at.px + l.level_min, at.src, at.f})
      }
    case "Background":
      for at in layer.autoLayerTiles {
        append(&l.bg_tiles, Tile{at.px + l.level_min, at.src, at.f})
      }
    }
  }

  for &fl in l.falling_logs {
    center := rect_center(fl.collider)
    hits, hits_ok := raycast(
      center,
      UP * (l.level_max.y - l.level_min.y),
      l.colliders[:],
    )

    if hits_ok {
      slice.sort_by(hits, proc(a, b: Vec2) -> bool {
        return a.y > b.y || a.y == b.y
      })

      fl.rope_height = center.y - hits[0].y - fl.collider.height / 2
    }
  }

  // Remove background tiles under spikes
  #reverse for tile, i in l.bg_tiles {
    for s in l.spikes {
      if rl.CheckCollisionRecs({tile.pos.x, tile.pos.y, 16, 16}, s.collider) {
        unordered_remove(&l.bg_tiles, i)
      }
    }
  }

  // store the level in the game state's level definitions
  gs.level_definitions[l.iid] = l
}

level_load :: proc(gs: ^Game_State, level: ^Level) {
  gs.level = level

  player := entity_get(gs.player_id)

  player_anim_name: string

  if player != nil {
    player_anim_name = strings.clone(
      player.current_anim_name,
      context.temp_allocator,
    )
  }

  // Clear all the existing level data.
  clear(&gs.entities)
  clear(&gs.colliders)
  clear(&gs.bg_tiles)
  clear(&gs.tiles)
  clear(&gs.spikes)
  clear(&gs.falling_logs)
  clear(&gs.doors)

  // Load the new level data.
  append(&gs.entities, ..level.entities[:])
  append(&gs.colliders, ..level.colliders[:])
  append(&gs.bg_tiles, ..level.bg_tiles[:])
  append(&gs.tiles, ..level.tiles[:])
  append(&gs.spikes, ..level.spikes[:])
  append(&gs.falling_logs, ..level.falling_logs[:])
  append(&gs.doors, ..level.doors[:])

  spawn_player(gs)

  if player_anim_name != "" {
    player = entity_get(gs.player_id)
    for k in player.animations {
      if k == player_anim_name {
        player.current_anim_name = k
      }
    }
  }
}

spawn_player :: proc(gs: ^Game_State) {
  player_anim_idle := Animation {
    size   = {120, 80},
    offset = {52, 42},
    start  = 0,
    end    = 9,
    row    = 0,
    time   = 0.15,
    flags  = {.Loop},
  }

  player_anim_run := Animation {
    size   = {120, 80},
    offset = {52, 42},
    start  = 0,
    end    = 9,
    row    = 2,
    time   = 0.15,
    flags  = {.Loop},
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
    flags  = {.Loop},
  }

  player_anim_attack := Animation {
    size         = {120, 80},
    offset       = {52, 42},
    start        = 0,
    end          = 3,
    row          = 3,
    time         = 0.05,
    on_finish    = player_on_finish_attack,
    timed_events = {
      {timer = 0.01, duration = 0.01, callback = player_attack_sfx},
      {timer = 0.05, duration = 0.05, callback = player_attack_callback},
    },
  }
  gs.player_id = entity_create(
    {
      x = gs.level.player_spawn.?.x,
      y = gs.level.player_spawn.?.y,
      width = 16,
      height = 38,
      flags = {.Debug_Draw},
      debug_color = rl.GREEN,
      jump_force = 650,
      move_speed = 280,
      on_enter = player_on_enter,
      health = 5,
      max_health = 5,
      texture = &gs.player_texture,
      current_anim_name = "idle",
    },
  )

  p := entity_get(gs.player_id)
  p.animations["idle"] = player_anim_idle
  p.animations["run"] = player_anim_run
  p.animations["jump"] = player_anim_jump
  p.animations["jump_fall_inbetween"] = player_anim_jump_fall_inbetween
  p.animations["fall"] = player_anim_fall
  p.animations["attack"] = player_anim_attack

  if pos, ok := gs.level.player_spawn.?; ok {
    gs.safe_position = pos
  }
  //todo: might not need this
  //t := Animation_Event {
  //  timer    = 0.15,
  //  duration = 0.15,
  //  callback = player_attack_callback,
  //}
  //append(&player_anim_attack.timed_events, t)
}

main :: proc() {
  rl.SetConfigFlags({.VSYNC_HINT})
  rl.SetTargetFPS(TARGET_FPS)
  rl.InitAudioDevice()
  rl.InitWindow(WINDOW_WIDTH, WINDOW_HEIGHT, WINDOW_TITLE)

  args := os.args[1:]
  fmt.printf("[GameINFO] Command Line: %v\n", args)
  debug_draw := false
  if len(args) > 0 && args[0] == "--debug" {
    debug_draw = true
  }

  gs = new(Game_State)
  gs.camera = rl.Camera2D {
    zoom = ZOOM,
  }
  gs.debug_draw_enabled = debug_draw

  // Load textures
  gs.player_texture = rl.LoadTexture("assets/textures/player_120x80.png")
  gs.tileset_texture = rl.LoadTexture("assets/textures/tileset.png")

  // Load sounds
  gs.sword_swoosh_snd = rl.LoadSound("assets/sounds/player_sword_swing.wav")
  gs.sword_swoosh_snd_2 = rl.LoadSound(
    "assets/sounds/player_sword_swing_2.wav",
  )
  gs.sword_hit_soft_snd = rl.LoadSound(
    "assets/sounds/player_sword_hit_soft.wav",
  )
  gs.sword_hit_med_snd = rl.LoadSound("assets/sounds/player_sword_medium.wav")
  gs.sword_hit_stone_snd = rl.LoadSound("assets/sounds/player_sword_stone.wav")
  gs.player_jump_snd = rl.LoadSound("assets/sounds/player_jump.wav")

  fmt.println("[Game] Loading bgm..")
  bgm := rl.LoadMusicStream("assets/music/bgm.ogg")
  fmt.println("[Game] End Loading bgm..")
  rl.PlayMusicStream(bgm)

  gs.enemy_definitions["Walker"] = Enemy_Def {
    collider_size = {36, 18},
    move_speed = 35,
    health = 3,
    behaviors = {.Walk, .Flip_At_Wall, .Flip_At_Edge},
    on_hit_damage = 1,
    texture = rl.LoadTexture("assets/textures/opossum_36x28.png"),
    animations = {
      "walk" = Animation {
        size = {36, 28},
        offset = {0, 10},
        start = 0,
        end = 5,
        time = 0.15,
        flags = {.Loop},
      },
    },
    initial_animation = "walk",
    hit_response = .Stop,
    hit_duration = 0.25,
  }

  // Can create your own scope so that similarly used variables (like x & y)
  // are able to be used. Pretty neat feature.
  // Load Level Data
  {
    level_data, ok := os.read_entire_file(
      "data/world.ldtk",
      allocator = context.allocator,
    )
    assert(ok, "Failed to read level data.")

    // new -> we are asking for memory NOW
    // loads data on the heap
    ldtk_data := new(Ldtk_Data, context.temp_allocator)
    err := json.unmarshal(
      level_data,
      ldtk_data,
      allocator = context.temp_allocator,
    )

    for &level in ldtk_data.levels {
      level_parse_and_store(gs, &level)
    }

    if err != nil {
      log.panicf("[Error] Failed to parse JSON: %v", err)
    }
  }

  level_load(gs, &gs.level_definitions["95ec7dd0-ac70-11f0-aba9-8934640bd777"])

  num := len(&gs.colliders)
  assert(num > 0, "🚨 Failed to populate level tiles!")

  for !rl.WindowShouldClose() {
    if rl.IsKeyPressed(.TAB) {
      gs.debug_draw_enabled = !gs.debug_draw_enabled
    }

    rl.UpdateMusicStream(bgm)
    dt := rl.GetFrameTime()

    player := entity_get(gs.player_id)

    player_update(gs, dt)
    entity_update(gs, dt)
    physics_update(gs.entities[:], gs.colliders[:], gs.falling_logs[:], dt)
    behavior_update(gs.entities[:], gs.colliders[:], dt)

    for &falling_log in gs.falling_logs {
      if falling_log.state == .Falling {
        falling_log.collider.y += dt * 600

        for col in gs.colliders {
          if rl.CheckCollisionRecs(col, falling_log.collider) {
            if col.y <= falling_log.collider.y + falling_log.collider.height {
              falling_log.state = .Settled
              append(&gs.colliders, falling_log.collider)
              break
            }
          }
        }

        for e, i in gs.entities {
          if rl.CheckCollisionRecs(e.collider, falling_log.collider) {
            entity_damage(Entity_Id(i), 999)
          }
        }
      }
    }

    // camera logic
    render_half_size := Vec2{RENDER_WIDTH, RENDER_HEIGHT} / 2
    gs.camera.target = {player.x, player.y} - render_half_size

    //only allow the camera to go the bounds of the level
    if gs.camera.target.x < gs.level.level_min.x {
      gs.camera.target.x = gs.level.level_min.x
    }
    if gs.camera.target.y < gs.level.level_min.y {
      gs.camera.target.y = gs.level.level_min.y
    }

    if gs.camera.target.x + RENDER_WIDTH > gs.level.level_max.x {
      gs.camera.target.x = gs.level.level_max.x - RENDER_WIDTH
    }
    if gs.camera.target.y + RENDER_HEIGHT > gs.level.level_max.y {
      gs.camera.target.y = gs.level.level_max.y - RENDER_HEIGHT
    }

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
        for spike in gs.spikes {
          if rl.CheckCollisionRecs(spike.collider, player.collider) {
            break safety_check
          }
        }
        _, hit_ground_left := raycast(
          pos + {0, size.y},
          DOWN * 2,
          gs.colliders[:],
        )
        if !hit_ground_left do break safety_check

        _, hit_ground_right := raycast(pos + size, DOWN * 2, gs.colliders[:])
        if !hit_ground_right do break safety_check

        _, hit_entity_left := raycast(pos, LEFT * TILE_SIZE, targets[:])
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

    for rect in gs.colliders {
      // Draw as an orange debug lines to visualize each square
      //rl.DrawRectangleRec(rect, rl.WHITE)
      rl.DrawRectangleLinesEx(rect, 1, rl.ORANGE)
      rl.DrawRectangleRec(rect, {255, 255, 255, 40})
    }

    for tile in gs.bg_tiles {
      w: f32 = TILE_SIZE
      h: f32 = TILE_SIZE

      if tile.f == 1 || tile.f == 3 {
        w = -TILE_SIZE
      } else if tile.f == 2 || tile.f == 3 {
        h = -TILE_SIZE
      }

      rl.DrawTextureRec(
        gs.tileset_texture,
        {tile.src.x, tile.src.y, w, h},
        tile.pos,
        rl.WHITE,
      )
    }
    for tile in gs.tiles {
      w: f32 = TILE_SIZE
      h: f32 = TILE_SIZE

      if tile.f == 1 || tile.f == 3 {
        w = -TILE_SIZE
      } else if tile.f == 2 || tile.f == 3 {
        h = -TILE_SIZE
      }

      rl.DrawTextureRec(
        gs.tileset_texture,
        {tile.src.x, tile.src.y, w, h},
        tile.pos,
        rl.WHITE,
      )
    }

    for &e in gs.entities {
      if .Dead in e.flags do continue

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

        rl.DrawTextureRec(e.texture^, src, {e.x, e.y} - anim.offset, rl.WHITE)
      }

      for spike in gs.spikes {
        rl.DrawRectangleLinesEx(spike.collider, 1, rl.YELLOW)
      }

      for falling_log in gs.falling_logs {
        center := rect_center(falling_log.collider)

        if falling_log.state == .Default {
          rope_pos := Vec2 {
            center.x,
            center.y - falling_log.collider.height / 2,
          }
          rl.DrawLineEx(
            rope_pos,
            rope_pos - {0, falling_log.rope_height},
            1,
            rl.BROWN,
          )
        }
        rl.DrawRectangleLinesEx(falling_log.collider, 4, rl.BROWN)
      }

      if gs.debug_draw_enabled {
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

        // Draw the safe position
        debug_draw_rect(
          gs.safe_position,
          {player.width, player.height},
          1,
          rl.BLUE,
        )

        // Draw the attack area
        debug_draw_circle(
          {player.collider.x, player.collider.y} +
          {.Left in player.flags ? -30 + player.collider.width : 30, 20},
          25,
          rl.GREEN,
        )

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
      }
    }

    for door in gs.doors {
      rl.DrawRectangleLinesEx(door.rect, 1, rl.BLUE)
    }

    rl.EndMode2D()
    // Draw the current FPS
    rl.DrawFPS(20, 20)
    rl.EndDrawing()

    // clear the array of debug_shapes after drawing
    clear(&gs.debug_shapes)
    free_all(context.temp_allocator)
  }
}
