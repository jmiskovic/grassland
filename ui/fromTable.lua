local chui = require'ui/chui'
require'ui/foldable'
require'ui/colorPicker'

local axisFromIndex = { 'x', 'y', 'z', 'w' }
local color_keywords = { 'color', 'radiance', 'hue', 'shade', 'tint', 'tone' }

-- number slider widget
local number_slider_widget = {}
number_slider_widget.defaults = { source_table = nil, key = nil, callback = nil }

function number_slider_widget:init(options)
  self.span = {0, 0}
  local panel = chui.panel{ frame='none', palette=self.parent.palette }
  local value = options.source_table[options.key]
  local min_init = value < 0 and value * 2 or 1e-5
  local max_init = math.max(math.abs(value) * 2, 1e-4)
  local s
  panel:toggle{ text = '-', span=0.3, thickness=0.15, state = value < 0, callback =
    function(_, allow_neg)
      if allow_neg then
        s.min = -s.max
      else
        s.min = 1e-5
        s.value = math.max(s.min, s.value)
      end
    end }
  s = panel:slider{ text=options.key, value=value, min=min_init, max=max_init, span=6, thickness=0.05,
    format = string.format('%%s %%.%df', 3),
    callback = function(self, value)
      options.source_table[options.key] = value
      if options.callback then
        options.callback(self, value, options.source_table)
      end
    end}
  panel:button{ text = '<<', span=0.3, thickness=0.15, callback =
    function()
      s.max = s.max * 0.5
      s.value = math.min(s.value, s.max)
      if s.min < 0 then
        s.min = -s.max
        s.value = math.max(s.value, s.min)
      end
    end }
  panel:button{ text = '>>', span=0.3, thickness=0.15, callback =
    function()
      s.max = s.max * 2
      if s.min < 0 then
        s.min = -s.max
      end
    end }
  panel:layout('right')
  self.parent:nest(panel)
end

function number_slider_widget:update(dt, pointer, handness) end
function number_slider_widget:draw(pass, pose) end

chui.initWidgetType('numberSlider', number_slider_widget)

-- boolean toggle widget
local boolean_toggle_widget = {}
boolean_toggle_widget.defaults = { source_table = nil, key = nil }

function boolean_toggle_widget:init(options)
  local state = options.source_table[options.key]
  self.parent:toggle{ text=options.key, state=state, span = 2,
    callback = function(self, state)
      options.source_table[options.key] = state
    end}
end

function boolean_toggle_widget:update(dt, pointer, handness) end
function boolean_toggle_widget:draw(pass, pose) end

chui.initWidgetType('booleanToggle', boolean_toggle_widget)

-- vector sliders widget
local vector_components_widget = {}
vector_components_widget.defaults = { source_table = nil, key = nil }

function vector_components_widget:init(options)
  self.span = {0, 0}
  assert(options.source_table and options.key and options.source_table[options.key],
    'source_table specified in options needs to have a vector object stored under key')
  local vec_source = options.source_table[options.key]
  local list = { vec_source:unpack() }
  local callback = function(slider, value, source_table)
    vec_source:set(unpack(list))
  end
  local panel = chui.panel{ frame='none', palette=self.parent.palette }
  panel:label{ text = options.key:upper(), span = { 2.5, 0.2 }, text_scale = 1.6 }
  panel:row()
  for i = 1, #list do
    local value = list[i]
    panel:numberSlider{ source_table=list, key=i, callback=callback }
    panel:row()
  end
  panel:layout()
  self.parent:nest(panel)
end

function vector_components_widget:update(dt, pointer, handness) end
function vector_components_widget:draw(pass, pose) end

chui.initWidgetType('vectorComponents', vector_components_widget)

local function isColorVector(key)
  for _, keyword in ipairs(color_keywords) do
    if key:lower():find(keyword) then
      return true
    end
  end
  return false
end


local from_table_widget = {}
from_table_widget.defaults = { source_table = nil, key = nil }

function from_table_widget:init(options)
  local folding_panel = chui.panel{ palette=chui.palettes[9], frame='none' }
  local panel = folding_panel:foldable{ text=options.key, text_span=1.4, frame='none', collapsed=false, palette=chui.palettes[9] }.content
  --local panel = chui.panel({palette=chui.palettes[9], frame='none'})

  panel.source_table = options.source_table
  local keys = {}
  for k, v in pairs(options.source_table) do
    local etype = type(v)
    if etype == 'number' or etype == 'boolean' or etype == 'userdata' then
      table.insert(keys, k)
    end
  end

  table.sort(keys)

  for i, key in ipairs(keys) do
    local etype = type(options.source_table[key])
    if etype == 'number' then
      panel:numberSlider{ source_table=options.source_table, key=key }
      panel:row()
    elseif etype == 'boolean' then
      panel:booleanToggle{ source_table=options.source_table, key=key }
      panel:row()
    elseif etype == 'userdata' and options.source_table[key].unpack then
      local list = {options.source_table[key]:unpack()}
      if #list <= 4 then
        if isColorVector(key) then
          panel:colorPicker{ color=options.source_table[key] }
          panel:row()
        else
          panel:vectorComponents{ source_table=options.source_table, key=key }
          panel:row()
        end
      end
    else
      print('skipping unsuported table value', key)
    end
  end
  if #panel.rows[#panel.rows] == 0 then -- remove last row if empty
    panel.rows[#panel.rows] = nil
  end
  panel:layout()
  folding_panel:layout()
  --self.key = folding_panel
  self.parent:nest(folding_panel)
  return self
end

function from_table_widget:update(dt, pointer, handness) end
function from_table_widget:draw(pass, pose) end

chui.initWidgetType('fromTable', from_table_widget)

local m = {}

function m.integrate(source_table, pose)
  pose = pose or mat4(0, 1.5, -0.5):scale(0.2)
  function m.update(dt)
    chui.update(dt)
  end
  function m.draw(pass)
    chui.draw(pass)
  end

  local chui = require'ui/chui'
  local panel = chui.panel()
  panel:fromTable({source_table=source_table})
  panel:layout()
  panel.pose:set(pose)

  local stub_fn = function() end
  local existing_cb = {
    update = lovr.update or stub_fn,
    draw = lovr.draw or stub_fn,
  }

  local function wrap(callback)
    return function(...)
      m[callback](...)
      existing_cb[callback](...)
    end
  end

  lovr.update = wrap('update')
  lovr.draw = wrap('draw')
  return panel
end

return m