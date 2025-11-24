#+feature dynamic-literals
package main

import "core:encoding/json"
import "core:flags"
import "core:fmt"
import "core:log"
import "core:math"
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
DASH_DURATION :: 0.3
DASH_COOLDOWN :: 1
DASH_VELOCITY :: 500
BG_COLOR_MAIN_MENU :: rl.Color{0, 0, 28, 255}
SAVE_ITEM_HEIGHT :: 60
SAVE_SLOTS :: 10
SAVE_PANEL_WIDTH :: WINDOW_WIDTH / 2
SAVE_PANEL_HEIGHT :: WINDOW_HEIGHT / 3
SCROLL_SPEED :: 20

VERSION_MAJOR :: 0
VERSION_MINOR :: 1
VERSION_PATCH :: 0

// Type Aliases (reduce typing!) Note, they must come after rl definition
Vec2 :: rl.Vector2
Rect :: rl.Rectangle
Snd :: rl.Sound

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

FIRST_LEVEL_ID :: "95ec7dd0-ac70-11f0-aba9-8934640bd777"
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
  camera:                rl.Camera2D,
  ui_camera:             rl.Camera2D,
  player_id:             Entity_Id,
  player_texture:        rl.Texture,
  player_mv_state:       Player_Move_State,
  safe_position:         Vec2,
  safe_reset_timer:      f32,
  // ideally, don't draw from multiple textures
  hearts_texture:        rl.Texture,
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
  checkpoints:           [dynamic]Checkpoint,
  checkpoint_level_iid:  string,
  checkpoint_iid:        string,
  orig_spawn_point:      Vec2,
  power_ups:             [dynamic]Power_Up,
  collected_power_ups:   bit_set[Power_Up_Type],
  dash_timer:            f32,
  dash_cooldown_timer:   f32,
  scene:                 Scene_Type,
  font_48:               rl.Font,
  font_64:               rl.Font,
  bgm:                   rl.Music,
  main_menu_state:       Main_Menu_State,
  last_update_time:      time.Time,
  save_data:             Save_Data,
}

Scene_Type :: enum {
  Main_Menu,
  Game,
}

Main_Menu_State :: struct {
  menu_type:               Main_Menu_Type,
  save_texture:            rl.RenderTexture2D,
  save_slots:              [SAVE_SLOTS]Save_Data,
  save_list_scroll_offset: f32,
}

Main_Menu_Type :: enum {
  Default,
  Select_Save_Slot,
}

Save_Data :: struct {
  slot:                int,
  version:             struct {
    major: int,
    minor: int,
    patch: int,
  },
  seconds_played:      f64,
  level_iid:           string,
  location:            string,
  checkpoint_iid:      string,
  collected_power_ups: bit_set[Power_Up_Type],
}

Power_Up :: struct {
  using pos: Vec2,
  type:      Power_Up_Type,
}

Power_Up_Type :: enum {
  Dash,
  HighJump,
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

Checkpoint :: struct {
  iid:            string,
  using position: Vec2,
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
  checkpoints:  [dynamic]Checkpoint,
  power_ups:    [dynamic]Power_Up,
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
          gs.orig_spawn_point = Vec2{entity.__worldX, entity.__worldY}
        case "Power_Up":
          p_up_name := entity.fieldInstances[0].__value
          switch p_up_name {
          case "Dash":
            append(
              &l.power_ups,
              Power_Up{pos = {entity.__worldX, entity.__worldY}, type = .Dash},
            )
          case "HighJump":
            append(
              &l.power_ups,
              Power_Up {
                pos = {entity.__worldX, entity.__worldY},
                type = .HighJump,
              },
            )
          }
        case "Checkpoint":
          append(
            &l.checkpoints,
            Checkpoint {
              iid = strings.clone(entity.iid),
              x = entity.__worldX,
              y = entity.__worldY,
            },
          )
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
  player_health: int

  if player != nil {
    player_anim_name = strings.clone(
      player.current_anim_name,
      context.temp_allocator,
    )
    player_health = player.health
  }

  // Clear all the existing level data.
  clear(&gs.entities)
  clear(&gs.colliders)
  clear(&gs.bg_tiles)
  clear(&gs.tiles)
  clear(&gs.spikes)
  clear(&gs.falling_logs)
  clear(&gs.doors)
  clear(&gs.checkpoints)

  // Load the new level data.
  append(&gs.entities, ..level.entities[:])
  append(&gs.colliders, ..level.colliders[:])
  append(&gs.bg_tiles, ..level.bg_tiles[:])
  append(&gs.tiles, ..level.tiles[:])
  append(&gs.spikes, ..level.spikes[:])
  append(&gs.falling_logs, ..level.falling_logs[:])
  append(&gs.doors, ..level.doors[:])
  append(&gs.checkpoints, ..level.checkpoints[:])

  // only append if you haven't collected the power up
  for power_up in level.power_ups {
    if power_up.type not_in gs.collected_power_ups {
      append(&gs.power_ups, power_up)
    }
  }

  spawn_player(gs)

  if player_anim_name != "" {
    player = entity_get(gs.player_id)
    player.health = player_health
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

  player_anim_dash := Animation {
    size   = {120, 80},
    offset = {52, 42},
    start  = 4,
    end    = 5,
    row    = 3,
    time   = 0.15,
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
      health = 6,
      max_health = 6,
      texture = &gs.player_texture,
      current_anim_name = "idle",
      on_death = player_on_death,
    },
  )

  p := entity_get(gs.player_id)
  p.animations["idle"] = player_anim_idle
  p.animations["run"] = player_anim_run
  p.animations["jump"] = player_anim_jump
  p.animations["jump_fall_inbetween"] = player_anim_jump_fall_inbetween
  p.animations["fall"] = player_anim_fall
  p.animations["attack"] = player_anim_attack
  p.animations["dash"] = player_anim_dash

  if pos, ok := gs.level.player_spawn.?; ok {
    gs.safe_position = pos
  }
}

game_init :: proc(gs: ^Game_State) {
  gs.last_update_time = time.now()

  gs.player_texture = rl.LoadTexture("assets/textures/player_120x80.png")
  gs.tileset_texture = rl.LoadTexture("assets/textures/tileset.png")
  gs.hearts_texture = rl.LoadTexture("assets/textures/health_hearts.png")

  // Load sounds
  gs.sword_swoosh_snd = rl.LoadSound("assets/sounds/player_sword_swing.wav")
  gs.sword_swoosh_snd_2 = rl.LoadSound(
    "assets/sounds/player_sword_swing_2.wav",
  )
  gs.sword_hit_soft_snd = rl.LoadSound("assets/sounds/sword_hit_soft.wav")
  gs.sword_hit_med_snd = rl.LoadSound("assets/sounds/sword_hit_medium.wav")
  gs.sword_hit_stone_snd = rl.LoadSound("assets/sounds/sword_hit_stone.wav")
  gs.player_jump_snd = rl.LoadSound("assets/sounds/player_jump.wav")

  gs.bgm = rl.LoadMusicStream("assets/music/bgm.ogg")
  rl.PlayMusicStream(gs.bgm)

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

  gs.enemy_definitions["Jumper"] = Enemy_Def {
    collider_size = {50, 48},
    move_speed = 0,
    health = 2,
    behaviors = {.Wander, .Hop},
    on_hit_damage = 1,
    texture = rl.LoadTexture("assets/textures/bunny_50x48.png"),
    animations = {
      "idle" = Animation{size = {50, 48}},
      "hop" = Animation {
        size = {50, 48},
        offset = {},
        start = 0,
        end = 2,
        time = 0.15,
        flags = {},
      },
    },
    initial_animation = "idle",
    hit_response = .Knockback,
    hit_duration = 0.25,
  }

  gs.enemy_definitions["Charger"] = Enemy_Def {
    collider_size = {64, 35},
    move_speed = 25,
    health = 3,
    behaviors = {.Walk, .Flip_At_Wall, .Flip_At_Edge, .Charge_At_Player},
    on_hit_damage = 2,
    texture = rl.LoadTexture("assets/textures/pig_64x35.png"),
    animations = {
      "walk" = Animation {
        size = {64, 35},
        start = 0,
        end = 3,
        time = 0.25,
        flags = {.Loop},
      },
      "charge" = Animation{size = {64, 35}, start = 0, end = 3, time = 0.15},
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

  level_load(gs, &gs.level_definitions[FIRST_LEVEL_ID])

  num := len(&gs.colliders)
  assert(num > 0, "🚨 Failed to populate level tiles!")

  gs.scene = .Game
}

main_menu_item_draw :: proc(
  text: cstring,
  pos: Vec2,
  color := rl.WHITE,
  hover_color := rl.YELLOW,
) -> (
  pressed: bool,
) {
  pos := pos
  text_size := rl.MeasureTextEx(gs.font_48, text, 48, 0)
  pos.x -= text_size.x / 2
  rect := Rect{pos.x, pos.y, text_size.x, text_size.y}

  if rl.CheckCollisionPointRec(rl.GetMousePosition(), rect) {
    rl.DrawTextEx(gs.font_48, text, pos, 48, 0, hover_color)
    if rl.IsMouseButtonPressed(.LEFT) {
      pressed = true
    }
  } else {
    rl.DrawTextEx(gs.font_48, text, pos, 48, 0, color)
  }
  return pressed
}

load_game_item_draw :: proc(
  slot: int,
  panel_pos: Vec2,
  offset: f32,
  location: string = "",
  time_played: f64 = 0,
) -> (
  pressed: bool,
) {
  text: cstring

  if time_played == 0 {
    text = "New Game"
  } else {
    dur := time.Duration(i64(time_played * 1000 * 1000 * 1000))
    buf: [time.MIN_HMS_LEN]u8
    time_played_str := time.to_string_hms(dur, buf[:])
    text = fmt.ctprintf("%d - %s, %s", slot + 1, location, time_played_str)
  }

  pos := Vec2{0, f32(slot) * SAVE_ITEM_HEIGHT}
  m_pos := rl.GetMousePosition()

  s_pos := panel_pos + {0, pos.y + offset}

  if rl.CheckCollisionPointRec(
    m_pos,
    {s_pos.x, s_pos.y, SAVE_PANEL_WIDTH, SAVE_ITEM_HEIGHT},
  ) {
    rl.DrawTextEx(gs.font_48, text, pos, 48, 0, rl.YELLOW)
    if rl.IsMouseButtonPressed(.LEFT) {
      pressed = true
    }
  } else {
    rl.DrawTextEx(gs.font_48, text, pos, 48, 0, rl.WHITE)
  }
  return pressed
}

main_menu_update :: proc(gs: ^Game_State) {
  for !rl.WindowShouldClose() {
    center := Vec2{WINDOW_WIDTH, WINDOW_HEIGHT} / 2

    tile_text: cstring = "METROIDVANIA"
    tile_text_size := rl.MeasureTextEx(gs.font_64, tile_text, 64, 4)

    rl.BeginDrawing()
    rl.ClearBackground(BG_COLOR_MAIN_MENU)

    rl.DrawTextEx(
      gs.font_64,
      tile_text,
      {center.x - tile_text_size.x / 2, center.y / 2},
      64,
      4,
      rl.WHITE,
    )

    switch gs.main_menu_state.menu_type {
    case .Default:
      if main_menu_item_draw("Play", center) {
        gs.main_menu_state.menu_type = .Select_Save_Slot
      }

      if main_menu_item_draw("Settings", center + {0, 60}) {
        // todo:
        return
      }

      if main_menu_item_draw("Quit", center + {0, 120}) {
        rl.CloseWindow()
        return
      }
    case .Select_Save_Slot:
      target := gs.main_menu_state.save_texture
      panel_pos := Vec2 {
        (WINDOW_WIDTH - SAVE_PANEL_WIDTH) / 2,
        WINDOW_HEIGHT / 2,
      }

      mouse_wheel_move := rl.GetMouseWheelMove()

      gs.main_menu_state.save_list_scroll_offset = clamp(
        gs.main_menu_state.save_list_scroll_offset +
        mouse_wheel_move * SCROLL_SPEED,
        SAVE_ITEM_HEIGHT - SAVE_ITEM_HEIGHT * SAVE_SLOTS,
        0,
      )

      rl.BeginTextureMode(target)
      rl.ClearBackground(BG_COLOR_MAIN_MENU)

      for sd, i in gs.main_menu_state.save_slots {
        if sd.seconds_played > 0 {   // means that this is taken
          if load_game_item_draw(
            i,
            panel_pos,
            gs.main_menu_state.save_list_scroll_offset,
            sd.location,
            sd.seconds_played,
          ) {
            gs.save_data = sd
            game_init(gs)
            level_def := &gs.level_definitions[FIRST_LEVEL_ID]

            if sd.level_iid != "" {
              level_def, _ = &gs.level_definitions[sd.level_iid]
              gs.checkpoint_level_iid = sd.level_iid
              gs.checkpoint_iid = sd.checkpoint_iid
            }

            for c in level_def.checkpoints {
              if c.iid == sd.checkpoint_iid {
                level_def.player_spawn = c.position
              }
            }

            gs.level_definitions[level_def.iid] = level_def^
            gs.collected_power_ups = gs.save_data.collected_power_ups

            level_load(gs, level_def)
          }
        } else {
          // new game
          if load_game_item_draw(
            i,
            panel_pos,
            gs.main_menu_state.save_list_scroll_offset,
          ) {
            game_init(gs)

            gs.save_data.slot = i
            gs.save_data.version.major = VERSION_MAJOR
            gs.save_data.version.minor = VERSION_MINOR
            gs.save_data.version.patch = VERSION_PATCH

            level_load(gs, &gs.level_definitions[FIRST_LEVEL_ID])

            save_data_update(gs)

            gs.save_data.seconds_played = 1
            savefile_save(gs.save_data)
          }
        }
      }

      rl.EndTextureMode()

      rl.DrawTextureRec(
        gs.main_menu_state.save_texture.texture,
        Rect {
          0,
          gs.main_menu_state.save_list_scroll_offset - SAVE_PANEL_HEIGHT,
          SAVE_PANEL_WIDTH,
          -SAVE_PANEL_HEIGHT,
        },
        panel_pos,
        rl.WHITE,
      )

      {
        text :: "Back"
        size := rl.MeasureTextEx(gs.font_48, text, 48, 0)
        if main_menu_item_draw(text, {32 + size.x / 2, WINDOW_HEIGHT - 60}) {
          gs.main_menu_state.menu_type = .Default
        }
      }
    }

    rl.EndDrawing()

    if gs.scene != .Main_Menu {
      return
    }
  }
}

game_update :: proc(gs: ^Game_State) {
  for !rl.WindowShouldClose() {
    if rl.IsKeyPressed(.TAB) {
      gs.debug_draw_enabled = !gs.debug_draw_enabled
    }

    rl.UpdateMusicStream(gs.bgm)
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

        for c in gs.checkpoints {
          x := i32(c.x)
          y := i32(c.y) - 16 * 2
          rl.DrawText("CheckPoint!", x, y, 1, rl.ORANGE)
          rl.DrawRectangleLinesEx({c.x, c.y - 16, 32, 32}, 1, rl.ORANGE)
        }

        for p in gs.power_ups {
          rl.DrawRectangleLinesEx({p.x, p.y, 16, 16}, 3, rl.GOLD)
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

    // Well we can't draw this AND the health UI
    // Draw the current FPS
    //rl.DrawFPS(20, 20)

    rl.BeginMode2D(gs.ui_camera)
    // Draw Player Health & UI
    {
      full_hearts := player.health / 2
      has_half_heart := f32(player.health) / 2 > f32(full_hearts)
      total_hearts := math.ceil(f32(player.max_health) / 2)

      acct_for_half := 0
      if has_half_heart {
        acct_for_half = 1
      }

      empty_hearts := int(total_hearts) - full_hearts - acct_for_half

      x := f32(16)

      for _ in 0 ..< full_hearts {
        rl.DrawTextureRec(
          gs.hearts_texture,
          {32, 32, 16, 16},
          {x, 16},
          rl.WHITE,
        )
        x += 16
      }

      if has_half_heart {
        rl.DrawTextureRec(
          gs.hearts_texture,
          {16, 32, 16, 16},
          {x, 16},
          rl.WHITE,
        )
        x += 16
      }

      for _ in 0 ..< empty_hearts {
        rl.DrawTextureRec(
          gs.hearts_texture,
          {0, 16, 16, 16},
          {x, 16},
          rl.WHITE,
        )
        x += 16
      }

      // Print dash ability status.
      if .Dash in gs.collected_power_ups {
        rl.DrawRectangleRounded({72, 16, 48, 16}, 8, 5, {40, 40, 40, 255})
        if gs.dash_timer <= 0 && gs.dash_cooldown_timer <= 0 {
          rl.DrawText("Dash O", 76, 19, 2, rl.WHITE)
        } else {
          rl.DrawText("Dash X", 76, 19, 2, rl.WHITE)
        }
      }

      if .HighJump in gs.collected_power_ups {
        rl.DrawRectangleRounded({144, 16, 48, 16}, 8, 5, {40, 40, 40, 255})
        rl.DrawText("H.Jump", 152, 19, 2, rl.WHITE)
      }
    }
    rl.EndMode2D()

    rl.EndDrawing()

    // clear the array of debug_shapes after drawing
    clear(&gs.debug_shapes)
    free_all(context.temp_allocator)
  }
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
  gs.ui_camera = rl.Camera2D {
    zoom = ZOOM,
  }
  gs.debug_draw_enabled = debug_draw

  // Check for save files
  {
    cp := os.get_current_directory(context.temp_allocator)
    s_dir_path := fmt.tprintf("%s/saves", cp)
    s_dir, err := os.open(s_dir_path)

    if err != nil {
      fmt.printf(
        "[Debug] 🪲 Error opening save dir path %v \n[Debug] 🪲 Error message: %v\n",
        s_dir_path,
        err,
      )
    }

    when ODIN_OS == .Windows {
      if err == .Not_Exist {
        fmt.println("[Debug] 🪲 saves directory doesn't exist.")
        m_err := os.make_directory(s_dir_path)
        s_dir, err = os.open(s_dir_path)

        if m_err != nil || err != nil {
          panic("[Game] 🚨 Could not create save directory")
        }
      }
    }

    when ODIN_OS == .Darwin {
      if err == .ENOENT {
        fmt.println("[Debug] 🪲 saves directory doesn't exist.")
        m_err := os.make_directory(s_dir_path)
        s_dir, err = os.open(s_dir_path)

        if m_err != nil || err != nil {
          panic("[Game] 🚨 Could not create save directory")
        }
        fmt.println("[Game] Success creating file structure.")
      }
    }

    files, read_dir_err := os.read_dir(s_dir, 0, context.temp_allocator)
    if read_dir_err != nil {
      fmt.println("sdir: ", s_dir)
      panic("[Game] 🚨 Failed to read save directory")
    }

    for f in files {
      sd, ok := savefile_load(f.fullpath)
      if ok {
        gs.main_menu_state.save_slots[sd.slot] = sd
      }
    }
  }

  //Setup Main Menu texture
  {
    width :: SAVE_PANEL_WIDTH
    height :: SAVE_SLOTS * SAVE_ITEM_HEIGHT
    gs.main_menu_state.save_texture = rl.LoadRenderTexture(width, height)
  }

  gs.font_48 = rl.LoadFontEx("assets/fonts/Gogh-ExtraBold.ttf", 48, nil, 256)
  gs.font_64 = rl.LoadFontEx("assets/fonts/Gogh-ExtraBold.ttf", 64, nil, 256)

  for !rl.WindowShouldClose() {
    switch gs.scene {
    case .Main_Menu:
      main_menu_update(gs)
    case .Game:
      game_update(gs)
    }
  }
}
