package main

import "core:encoding/json"
import "core:flags"
import "core:fmt"
import "core:os"
import "core:slice"
import "core:time"
import rl "vendor:raylib"

// Constants
WINDOW_WIDTH :: 1280
WINDOW_HEIGHT :: 720
WINDOW_TITLE :: "MetroidVania-Slice"
BG_COLOR :: rl.BLACK
RENDER_WIDTH :: 640
RENDER_HEIGHT :: 320
ZOOM :: RENDER_WIDTH / RENDER_HEIGHT
TILE_SIZE :: 16
TARGET_FPS :: 60
SPIKES_BREADTH :: 16
SPIKES_DEPTH :: 12
SPIKES_DIFF :: TILE_SIZE - SPIKES_DEPTH
JUMP_TIME :: 0.2
COYOTE_TIME :: 0.15

// Type Aliases (reduce typing!) Note, they must come after rl definition
Vec2 :: rl.Vector2
Rect :: rl.Rectangle
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

Game_State :: struct {
  player_id:            Entity_Id,
  player_mv_state:      Player_Move_State,
  safe_position:        Vec2,
  safe_reset_timer:     f32,
  camera:               rl.Camera2D,
  entities:             [dynamic]Entity,
  colliders:            [dynamic]Rect,
  tiles:                [dynamic]Tile,
  bg_tiles:             [dynamic]Tile,
  spikes:               map[Entity_Id]Direction,
  debug_shapes:         [dynamic]Debug_Shape,
  level_min, level_max: Vec2,
  jump_timer:           f32,
  coyote_timer:         f32,
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

Ldtk_Level :: struct {
  identifier:     string,
  layerInstances: []Ldtk_Layer_Instance,
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
  __identifier: string,
  __worldX:     f32,
  __worldY:     f32,
}

gs: Game_State

spike_on_enter :: proc(self_id, other_id: Entity_Id) {
  me := entity_get(self_id)
  them := entity_get(other_id)

  if other_id == gs.player_id {
    them.x = gs.safe_position.x
    them.y = gs.safe_position.y

    them.vel = 0

    gs.safe_reset_timer = PLAYER_SAFE_RESET_TIME
    gs.player_mv_state = .Uncontrollable
    switch_animation(them, "idle")
  }

  dir := gs.spikes[self_id]

  switch dir {
  case .Up:
    if them.vel.y > 0 {
      fmt.println("spikes pointing up")
    }
  case .Right:
    if them.vel.x < 0 {
      fmt.println("spikes pointing right")
    }
  case .Down:
    if them.vel.y < 0 {
      fmt.println("spikes pointing down")
    }
  case .Left:
    if them.vel.x > 0 {
      fmt.println("spikes pointing left")
    }
  }
}

/*
   Not yet fixed, but it is the old way of loading level data using
   a simple text file.❗️What is not fixed is how to load the player
   animations.
 */
load_level_simple :: proc(level_data: []byte, player_tex: ^rl.Texture2D) {
  x, y: f32
  for v in level_data {
    switch v {
    case 'e':
      en := entity_create(
        Entity {
          collider = Rect{x, y, TILE_SIZE, TILE_SIZE},
          move_speed = 50,
          flags = {.Debug_Draw},
          behaviors = {.Walk, .Flip_At_Wall, .Flip_At_Edge},
          health = 2,
          max_health = 2,
          on_hit_damage = 1,
          debug_color = rl.RED,
        },
      )
    case '\n':
      y += TILE_SIZE
      x = 0
      continue
    case '#':
    //append(&gs.solid_tiles, Rect{x, y, TILE_SIZE, TILE_SIZE})

    case 'P':
      gs.player_id = entity_create(
        {
          x = x,
          y = y,
          width = 16,
          height = 38,
          flags = {.Debug_Draw},
          debug_color = rl.GREEN,
          jump_force = 650,
          move_speed = 280,
          on_enter = player_on_enter,
          health = 5,
          max_health = 5,
          texture = player_tex,
          current_anim_name = "idle",
        },
      )

    // load the player to load the animations

    //p := entity_get(gs.player_id)
    //p.animations["idle"] = player_anim_idle
    //p.animations["run"] = player_anim_run
    //p.animations["jump"] = player_anim_jump
    //p.animations["jump_fall_inbetween"] = player_anim_jump_fall_inbetween
    //p.animations["fall"] = player_anim_fall
    //p.animations["attack"] = player_anim_attack
    case '^':
      id := entity_create(
        Entity {
          collider = Rect{x, y + SPIKES_DIFF, SPIKES_BREADTH, SPIKES_DEPTH},
          on_enter = spike_on_enter,
          on_hit_damage = 1,
          flags = {.Kinematic, .Debug_Draw, .Immortal},
          debug_color = rl.YELLOW,
        },
      )
      gs.spikes[id] = .Up
    case '>':
      id := entity_create(
        Entity {
          collider = Rect{x, y, SPIKES_DEPTH, SPIKES_BREADTH},
          on_enter = spike_on_enter,
          on_hit_damage = 1,
          flags = {.Kinematic, .Debug_Draw, .Immortal},
          debug_color = rl.YELLOW,
        },
      )
      gs.spikes[id] = .Right
    case '<':
      id := entity_create(
        Entity {
          collider = Rect{x + SPIKES_DIFF, y, SPIKES_DEPTH, SPIKES_BREADTH},
          on_enter = spike_on_enter,
          on_hit_damage = 1,
          flags = {.Kinematic, .Debug_Draw, .Immortal},
          debug_color = rl.YELLOW,
        },
      )
      gs.spikes[id] = .Left
    case 'v':
      id := entity_create(
        Entity {
          collider = Rect{x, y, SPIKES_BREADTH, SPIKES_DEPTH},
          on_enter = spike_on_enter,
          on_hit_damage = 1,
          flags = {.Kinematic, .Debug_Draw, .Immortal},
          debug_color = rl.YELLOW,
        },
      )
      gs.spikes[id] = .Down

    }
    x += TILE_SIZE
  }
}

main :: proc() {
  rl.InitWindow(WINDOW_WIDTH, WINDOW_HEIGHT, WINDOW_TITLE)
  rl.SetTargetFPS(TARGET_FPS)

  gs = Game_State {
    camera = rl.Camera2D{zoom = ZOOM},
  }

  // Load textures
  player_tex := rl.LoadTexture("assets/textures/player_120x80.png")
  ts_tex := rl.LoadTexture("assets/textures/tileset.png")

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
    size      = {120, 80},
    offset    = {52, 42},
    start     = 0,
    end       = 3,
    row       = 3,
    time      = 0.15,
    on_finish = player_on_finish_attack,
  }


  t := Animation_Event {
    timer    = 0.15,
    duration = 0.15,
    callback = player_attack_callback,
  }
  append(&player_anim_attack.timed_events, t)

  // Can create your own scope so that similarly used variables (like x & y)
  // are able to be used. Pretty neat feature.
  {
    //level_data, ok := os.read_entire_file("data/simple_level.dat")
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

    if err != nil {
      fmt.println("❌ Error after unmarshalling json, printing below ❌")
      fmt.println(err)
    }

    fmt.println("✅ Successfully parsed LDTK json")

    for level in ldtk_data.levels {
      if level.identifier != "Level_0" do continue

      gs.level_min = {level.worldX, level.worldY}
      gs.level_max = gs.level_min + {level.pxWid, level.pxHei}

      for layer in level.layerInstances {
        switch layer.__identifier {
        case "Entities":
          for entity in layer.entityInstances {
            switch entity.__identifier {
            case "Player":
              px, py := entity.__worldX, entity.__worldY
              gs.player_id = entity_create(
                {
                  x = px,
                  y = py,
                  width = 16,
                  height = 38,
                  flags = {.Debug_Draw},
                  debug_color = rl.GREEN,
                  jump_force = 650,
                  move_speed = 280,
                  on_enter = player_on_enter,
                  health = 5,
                  max_health = 5,
                  texture = &player_tex,
                  current_anim_name = "idle",
                },
              )
              p := entity_get(gs.player_id)
              p.animations["idle"] = player_anim_idle
              p.animations["run"] = player_anim_run
              p.animations["jump"] = player_anim_jump
              p.animations["jump_fall_inbetween"] =
                player_anim_jump_fall_inbetween
              p.animations["fall"] = player_anim_fall
              p.animations["attack"] = player_anim_attack
            case "Door":
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
	   Right now the 
           we can further improve this optimization by
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
              append(&gs.colliders, big_rect)
              big_rect = rect
            }
          }
          append(&gs.colliders, big_rect)

          for at in layer.autoLayerTiles {
            append(&gs.tiles, Tile{at.px, at.src, at.f})
          }
        case "Background":
          for at in layer.autoLayerTiles {
            append(&gs.bg_tiles, Tile{at.px, at.src, at.f})
          }
        }
      }
    }
  }

  num := len(&gs.colliders)
  assert(num > 0, "🚨 Failed to populate level tiles!")

  for !rl.WindowShouldClose() {
    dt := rl.GetFrameTime()

    player := entity_get(gs.player_id)

    player_update(&gs, dt)
    entity_update(&gs, dt)
    physics_update(gs.entities[:], gs.colliders[:], dt)
    behavior_update(gs.entities[:], gs.colliders[:], dt)

    // camera logic
    render_half_size := Vec2{RENDER_WIDTH, RENDER_HEIGHT} / 2
    gs.camera.target = {player.x, player.y} - render_half_size

    // only allow the camera to go the bounds of the level
    if gs.camera.target.x < gs.level_min.x {
      gs.camera.target.x = gs.level_min.x
    }
    if gs.camera.target.y < gs.level_min.y {
      gs.camera.target.y = gs.level_min.y
    }

    if gs.camera.target.x + RENDER_WIDTH > gs.level_max.x {
      gs.camera.target.x = gs.level_max.x - RENDER_WIDTH
    }
    if gs.camera.target.y + RENDER_HEIGHT > gs.level_max.x {
      gs.camera.target.y = gs.level_max.y - RENDER_HEIGHT
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
        ts_tex,
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
        ts_tex,
        {tile.src.x, tile.src.y, w, h},
        tile.pos,
        rl.WHITE,
      )
    }

    for &e in gs.entities {
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

    // Draw the player after the level tiles!
    //rl.DrawRectangleLinesEx(player.collider, 1, rl.GREEN)


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
    rl.EndMode2D()
    // Draw the current FPS
    rl.DrawFPS(20, 20)
    rl.EndDrawing()

    // clear the array of debug_shapes after drawing
    clear(&gs.debug_shapes)
  }
}
