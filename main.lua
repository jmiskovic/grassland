local grass = require('grass')
local vfog = require('vfog')
local atmo = require('atmo')
local skybox = require'skybox'
local fromTable = require('ui/fromTable')

local atmo_skybox = skybox.new(128)
atmo_skybox:bake(atmo.draw)
vfog.load()
grass.load()


local function onAtmoChange()
  atmo_skybox:bake(atmo.draw)
  vfog.gpu.sun_position:set(atmo.gpu.sun_position)
end


function lovr.draw(pass)
  pass:setFaceCull('back')
  vfog.setCamera(pass)
  grass.draw(pass)
  local vfog_pass = vfog.calculate()
  atmo_skybox:draw(pass)
  return lovr.graphics.submit(vfog_pass, pass)
end


-- expose uniforms as UI panels
vfog.gpu.sun_position = nil              -- temporary remove the duplicate value so the UI skips it
fromTable.integrate(vfog.gpu,  mat4(-0.4, 1.4, -0.4):scale(0.04):rotate(-math.pi/12, 1,0,0))
vfog.gpu.sun_position = Vec3(atmo.gpu.sun_position)
fromTable.integrate(atmo.gpu,  mat4(   0, 1.4, -0.4):scale(0.04):rotate(-math.pi/12, 1,0,0), onAtmoChange)
fromTable.integrate(grass.gpu, mat4( 0.4, 1.4, -0.4):scale(0.04):rotate(-math.pi/12, 1,0,0))
