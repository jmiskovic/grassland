local grass = require('grass')
local vfog = require('vfog')
local atmo = require('atmo')
local skybox = require'skybox'

atmo.gpu.sun_position:set(vfog.gpu.sun_position)
atmo.gpu.horizon_offset = 30

local atmo_skybox = skybox.new(128)
atmo_skybox:bake(atmo.draw)

vfog.load()
grass.load()

function lovr.draw(pass)
  pass:setFaceCull('back')
  vfog.setCamera(pass)
  grass.draw(pass)
  local vfog_pass = vfog.calculate()
  atmo_skybox:draw(pass)
  return lovr.graphics.submit(vfog_pass, pass)
end
