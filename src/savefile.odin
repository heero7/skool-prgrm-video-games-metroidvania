package main

import "core:encoding/json"
import "core:fmt"
import "core:os"
import "core:time"

savefile_save :: proc(sd: Save_Data) -> (success: bool) {
  opts := json.Marshal_Options {
    spec = .SJSON,
  }

  data, err := json.marshal(sd, opts, context.temp_allocator)

  if err == nil {
    path := fmt.tprintf("saves/%d.json", sd.slot)
    success = os.write_entire_file(path, data)
  }

  if success {
    fmt.println("[Game] ⤵️ File saved!")
  }
  return success
}

savefile_load :: proc(path: string) -> (sd: Save_Data, ok: bool) {
  data := os.read_entire_file(path) or_return

  if json.unmarshal(data, &sd, .SJSON) == nil {
    ok = true
  }
  return sd, ok
}

save_data_update :: proc(gs: ^Game_State) {
  gs.save_data.collected_power_ups = gs.collected_power_ups
  gs.save_data.location = gs.level.name

  time_since_last_update := time.diff(gs.last_update_time, time.now())

  gs.last_update_time = time.now()
  gs.save_data.seconds_played += time.duration_seconds(time_since_last_update)
}
