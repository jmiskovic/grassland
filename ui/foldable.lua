local chui = require'ui/chui'

-- foldable widget
local foldable_widget = {}
foldable_widget.defaults = { collapsed = false, text = nil, text_span = 2 }

function foldable_widget:init(options)
  self.span = {0, 0}
  self.content = chui.panel(options)
  self.foldable_toggle = self.parent:toggle{ text=(options.collapsed and '+' or '-'), span={0.7, 0.7}, thickness=0.1,
    state=(not options.collapsed), callback=
    function(tgl, is_expanded)
      self.content.visible = is_expanded
      tgl.text = is_expanded and '-' or '+'
      local parent = self.parent
      while parent do
        parent:layout()
        parent = parent.parent
      end
    end}
  if options.text then
    self.foldable_label = self.parent:label{ text=options.text, span=options.text_span }
  end
  self.parent:row()
  self.parent:nest(self.content)
  self.parent:row()
  self.content.visible = self.foldable_toggle.state
end

function foldable_widget:update(dt, pointer, handness) end
function foldable_widget:draw(pass, pose) end

chui.initWidgetType('foldable', foldable_widget)

return foldable_widget
