local chui = require'ui/chui'

local colorPicker = {}
colorPicker.defaults = {
  text = 'Color Picker', color = {1,0.5,0}, callback = nil, mode = 'HSL',
}

function colorPicker.fromHexcode(hexcode)
  if type(hexcode) == 'table' then return {unpack(hexcode)} end
  local r = bit.band(bit.rshift(hexcode, 16), 0xff) / 255
  local g = bit.band(bit.rshift(hexcode, 8),  0xff) / 255
  local b = bit.band(bit.rshift(hexcode, 0),  0xff) / 255
  return {r, g, b, 1}
end

function colorPicker.toHexcode(rgba)
  local r, g, b = math.floor(rgba[1] * 255), math.floor(rgba[2] * 255), math.floor(rgba[3] * 255)
  return bit.bor(bit.lshift(r, 16), bit.lshift(g, 8), b)
end

function colorPicker.fromHSL(hsla)
  local h, s, l, a = unpack(hsla)
  a = a or 1
  if s < 0 then
    return {l,l,l,a}
  end
  h = h * 6
  local c = (1 - math.abs(2 * l - 1)) * s
  local x = (1 - math.abs(h % 2 - 1)) * c
  local md = (l - 0.5 * c)
  local r, g, b
  if     h < 1 then r, g, b = c, x, 0
  elseif h < 2 then r, g, b = x, c, 0
  elseif h < 3 then r, g, b = 0, c, x
  elseif h < 4 then r, g, b = 0, x, c
  elseif h < 5 then r, g, b = x, 0, c
  else              r, g, b = c, 0, x
  end
  return {r + md, g + md, b + md, a}
end

function colorPicker.toHSL(rgba)
  local r, g, b, a
  if type(rgba) == 'table' then
    r, g, b, a = unpack(rgba)
  elseif type(rgba) == 'userdata' then
    r, g, b, a = unpack(colorPicker.fromHexcode({rgba:unpack()}))
  else
    r, g, b, a = unpack(colorPicker.fromHexcode(rgba))
  end
  a = a or 1
  local min, max = math.min(r, g, b), math.max(r, g, b)
  local h, s, l = 0, 0, (max + min) / 2
  if max ~= min then
      local d = max - min
      s = l > 0.5 and d / (2 - max - min) or d / (max + min)
      if max == r then
          local mod = 6
          if g > b then mod = 0 end
          h = (g - b) / d + mod
      elseif max == g then
          h = (b - r) / d + 2
      else
          h = (r - g) / d + 4
      end
  end
  h = h / 6
  return {h, s, l, a}
end

function colorPicker.normalizeColor(color)
  if type(color) == 'number' then
    return colorPicker.fromHexcode(color)
  elseif type(color) == 'table' then
    if #color == 3 then
      return {color[1], color[2], color[3], 1}
    elseif #color == 4 then
      return color
    end
  elseif type(color) == 'userdata' and color.unpack then
    local r, g, b, a = color:unpack()
    a = a or 1
    return {r, g, b, a}
  end
  return {1, 0.5, 0, 1}
end

function colorPicker.convertColorBack(color, originalColor)
  if type(originalColor) == 'number' then
    return colorPicker.toHexcode(color)
  elseif type(originalColor) == 'table' then
    if #originalColor == 3 then
      return {color[1], color[2], color[3]}
    elseif #originalColor == 4 then
      return color
    end
  elseif type(originalColor) == 'userdata' then
    originalColor:set(unpack(color))
    return originalColor
  end
  return color
end

function colorPicker:init(options)
  local panel = self.parent
  self.span = {0, 0}
  self.originalColor = options.color
  self.color = colorPicker.normalizeColor(options.color)
  self.mode = options.mode or 'HSL'

  local color_panel = chui.panel{ frame = 'none' }
  color_panel.palette = {}
  for k, v in pairs(panel.palette) do
    color_panel.palette[k] = v
  end
  color_panel.palette.active = self.color

  color_panel:label{ text = options.text, span = { 2.5, 0.2 }, text_scale = 1.6, frame = 'none' }
  color_panel:glow{ state = true }

  local slider_a, slider_b, slider_c
  local sliderChange = function()
    if self.mode == 'HSL' then
      self.color = colorPicker.fromHSL{
        slider_a.value,
        slider_b.value,
        slider_c.value
      }
    else
      self.color = {
        slider_a.value,
        slider_b.value,
        slider_c.value
      }
    end

    color_panel.palette.active = self.color
    self.originalColor = colorPicker.convertColorBack(self.color, self.originalColor)
    if options.callback then
      options.callback(self.originalColor)
    end
  end

  local function updateSliders()
    if self.mode == 'HSL' then
      local h, s, l = unpack(colorPicker.toHSL(self.color))
      slider_a.text = 'hue'
      slider_b.text = 'saturation'
      slider_c.text = 'lightness'
      slider_a.value = h
      slider_b.value = s
      slider_c.value = l
    else
      slider_a.text = 'red'
      slider_b.text = 'green'
      slider_c.text = 'blue'
      slider_a.value = self.color[1]
      slider_b.value = self.color[2]
      slider_c.value = self.color[3]
    end
  end

  color_panel:toggle{ text = self.mode, span = {0.7, 0.7}, state = self.mode == 'RGB', callback =
    function(toggle_wgt, state)
      self.mode = state and 'RGB' or 'HSL'
      toggle_wgt.text = self.mode
      updateSliders()
      sliderChange()
    end }

  color_panel:row()

  slider_a = color_panel:slider{ text='hue',        value=0,  span=6, callback=sliderChange }; color_panel:row()
  slider_b = color_panel:slider{ text='saturation', value=0,  span=6, callback=sliderChange }; color_panel:row()
  slider_c = color_panel:slider{ text='lightness',  value=0,  span=6, callback=sliderChange }

  updateSliders()

  color_panel.element = element
  color_panel:layout()
  panel:nest(color_panel)
  return self
end

function colorPicker:draw(pass, pose) end
function colorPicker:update(dt, pointer, pointer_name) end

chui.initWidgetType('colorPicker', colorPicker)

return colorPicker
