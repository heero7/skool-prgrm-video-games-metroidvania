package main

rect_center :: #force_inline proc(r: Rect) -> Vec2 {
  return Vec2{r.x, r.y} + Vec2{r.width, r.height} * 0.5
}
