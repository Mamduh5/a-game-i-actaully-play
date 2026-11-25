-- Original fixture art. Run in the pinned Aseprite batch interpreter.
local output = assert(app.params.output, "Supply the source directory as output")
local width, height = 72, 88
local rgba = app.pixelColor.rgba

local function pixel(image, x, y, r, g, b, a)
  image:drawPixel(x, y, rgba(r, g, b, math.floor(math.max(0, math.min(255, a)))))
end

local function segment(x, y, a, b)
  local dx, dy = b[1] - a[1], b[2] - a[2]
  local t = ((x - a[1]) * dx + (y - a[2]) * dy) / (dx * dx + dy * dy)
  t = math.max(0, math.min(1, t))
  return math.sqrt((x - a[1] - dx * t)^2 + (y - a[2] - dy * t)^2)
end

local function polygon_distance(x, y, points)
  local nearest = 100
  local inside = false
  for index, a in ipairs(points) do
    local b = points[index % #points + 1]
    nearest = math.min(nearest, segment(x, y, a, b))
    if (a[2] > y) ~= (b[2] > y) and x < (b[1] - a[1]) * (y - a[2]) / (b[2] - a[2]) + a[1] then
      inside = not inside
    end
  end
  return inside and -nearest or nearest
end

local function make_master(alternate)
  local sprite = Sprite(width, height, ColorMode.RGB)
  sprite:assignColorSpace(ColorSpace{ sRGB=true })
  sprite.data = "Original fixture art. Foot pivot 36,70. Rune socket 35,42."
  local shadow = sprite.layers[1]
  shadow.name = "Soft graphite ground shadow"
  local pencil = sprite:newLayer()
  pencil.name = "Stone faces and graphite strokes"
  local wash = sprite:newLayer()
  wash.name = "Watercolor rune"
  local outline = alternate and
    {{23, 66}, {21, 44}, {27, 30}, {38, 19}, {48, 24}, {55, 39}, {53, 65}, {38, 72}} or
    {{20, 65}, {24, 38}, {31, 24}, {39, 16}, {49, 21}, {53, 44}, {51, 66}, {36, 72}}
  local ridge = alternate and {{43, 23}, {47, 47}, {46, 68}} or {{41, 21}, {44, 43}, {44, 68}}
  local accent = alternate and {163, 111, 73} or {71, 126, 138}
  local duration = {0.18, 0.12, 0.26}
  local intensity = {0.48, 1.0, 0.25}
  for stage = 1, 3 do
    if stage > 1 then sprite:newEmptyFrame() end
    sprite.frames[stage].duration = duration[stage]
    local shadow_frame, stone_frame, wash_frame = Image(width, height), Image(width, height), Image(width, height)
    for y = 0, height - 1 do
      for x = 0, width - 1 do
        local noise = ((x * 37 + y * 47 + x * y * 17) % 101) / 101
        local ground = ((x - 37) / 23)^2 + ((y - 69) / 6)^2
        if ground < 1 then
          pixel(shadow_frame, x, y, 50, 44, 39, 103 * (1 - ground)^1.8 * (0.65 + 0.35 * noise))
        end
        local edge = polygon_distance(x + 0.5, y + 0.5, outline) + (noise - 0.5) * 1.2
        if edge < 2.3 then
          if edge > 0 then
            pixel(stone_frame, x, y, 216, 209, 191, (2.3 - edge) * 58)
          elseif edge > -2.1 then
            local ink = 41 + math.floor(noise * 37)
            pixel(stone_frame, x, y, ink, ink - 3, ink - 6, 244)
          else
            local bevel = x > ridge[1][1] + (y - ridge[1][2]) * 0.08
            local strokes = ((x + 2 * y + math.floor(noise * 2)) % 9 < 2) and 19 or 0
            local shade = (bevel and 126 or 190) + math.floor(noise * 24) - strokes - math.floor(y * 0.24)
            if math.min(segment(x, y, ridge[1], ridge[2]), segment(x, y, ridge[2], ridge[3])) < 0.7 then
              shade = shade - 38
            end
            pixel(stone_frame, x, y, shade, shade - 5, shade - 11, 255)
          end
          local rune = math.abs(math.abs(x - 35) + math.abs(y - 42) * 0.72 - 8)
          local line = math.abs(x - 35) < 1.15 and math.abs(y - 42) < 13
          if edge < -3 and (rune < 1.5 or line) then
            pixel(wash_frame, x, y, accent[1], accent[2], accent[3],
              206 * intensity[stage] * (0.76 + noise * 0.24))
          elseif edge < -1 and rune < 4 and stage == 2 then
            pixel(wash_frame, x, y, accent[1], accent[2], accent[3], (4 - rune) * (16 + noise * 8))
          end
        end
      end
    end
    sprite:newCel(shadow, stage, shadow_frame, Point(0, 0))
    sprite:newCel(pencil, stage, stone_frame, Point(0, 0))
    sprite:newCel(wash, stage, wash_frame, Point(0, 0))
  end
  sprite:newTag(1, 3).name = "cue"
  local name = alternate and "waystone_alternate" or "waystone"
  sprite:saveAs(app.fs.joinPath(output, name .. ".aseprite"))
  sprite:close()
end

make_master(false)
make_master(true)
