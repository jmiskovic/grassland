local grass = require('grass')
local vfog = require('vfog')
local atmo = require('atmo')
local skybox = require'skybox'
local fromTable = require('ui/fromTable')

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

-- expose uniforms as UI panels
fromTable.integrate(vfog.gpu,  mat4(-0.2, 1.4, -0.4):scale(0.04):rotate(-math.pi/12, 1,0,0))
fromTable.integrate(grass.gpu, mat4(0.2,  1.4, -0.4):scale(0.04):rotate(-math.pi/12, 1,0,0))
