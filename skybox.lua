local vfog = require('vfog')

local m = {}
m.__index = m

local cubemap_transforms = {
  Mat4():lookAt(vec3(0, 0, 0), vec3( 1, 0, 0), vec3(0, 1, 0)),
  Mat4():lookAt(vec3(0, 0, 0), vec3(-1, 0, 0), vec3(0, 1, 0)),
  Mat4():lookAt(vec3(0, 0, 0), vec3( 0, 1, 0), vec3(0, 0,-1)),
  Mat4():lookAt(vec3(0, 0, 0), vec3( 0,-1, 0), vec3(0, 0, 1)),
  Mat4():lookAt(vec3(0, 0, 0), vec3( 0, 0, 1), vec3(0, 1, 0)),
  Mat4():lookAt(vec3(0, 0, 0), vec3( 0, 0,-1), vec3(0, 1, 0))
}

function m.new(resolution)
  local self = setmetatable({}, m)
  self.resolution = math.floor(resolution or 256)
  assert(self.resolution > 0 and self.resolution < 6000)
  self.cubetex = lovr.graphics.newTexture(
    self.resolution, self.resolution, 6,
    {type='cube', mipmaps=false, usage = {'render', 'sample', 'transfer'}})
  self.horizon_color = lovr.math.newVec3()
  return self
end


function m:bake(drawfn)
  -- render scene to cubemap texture
  self.render_pass = self.render_pass or lovr.graphics.newPass({self.cubetex, samples=1})
  self.render_pass:reset()
  local projection = mat4():perspective(math.pi / 2, 1, 0, 0)
  for i, transform in ipairs(cubemap_transforms) do
    self.render_pass:setProjection(i, projection)
    self.render_pass:setViewPose(i, transform)
  end
  drawfn(self.render_pass)
  lovr.graphics.submit(self.render_pass)
end


function m:readback_horizon_color()
  local readbacks = {
    self.cubetex:newReadback(0, 0, 1),
    self.cubetex:newReadback(0, 0, 2),
    self.cubetex:newReadback(0, 0, 3),
    self.cubetex:newReadback(0, 0, 4),
    self.cubetex:newReadback(0, 0, 5),
    self.cubetex:newReadback(0, 0, 6)
  }
  self.images = {}
  local save_pngs = lovr.system.isKeyDown('f3')
  for i, readback in ipairs(readbacks) do
    readback:wait()
    self.images[i] = readback:getImage()
    if save_pngs then
      local image_names = { 'px.png', 'nx.png', 'py.png', 'ny.png', 'pz.png', 'nz.png' }
      lovr.filesystem.write(image_names[i], self.images[i]:encode())
    end
  end
  if save_pngs then
      lovr.timer.sleep(0.5) -- stupid way to save once
  end
  -- sample rendered images at four points along the horizon
  local r1, g1, b1 = self.images[1]:getPixel(math.floor(self.resolution / 2), math.floor(self.resolution / 2))
  local r2, g2, b2 = self.images[2]:getPixel(math.floor(self.resolution / 2), math.floor(self.resolution / 2))
  local r3, g3, b3 = self.images[5]:getPixel(math.floor(self.resolution / 2), math.floor(self.resolution / 2))
  local r4, g4, b4 = self.images[6]:getPixel(math.floor(self.resolution / 2), math.floor(self.resolution / 2))
  -- take harmonic mean, to remove outliers such as sun
  self.horizon_color:set(4 / (1 / r1 + 1 / r2 + 1 / r3 + 1 / r4),
                         4 / (1 / g1 + 1 / g2 + 1 / g3 + 1 / g4),
                         4 / (1 / b1 + 1 / b2 + 1 / b3 + 1 / b4))
  return self.horizon_color
end


function m:readback_sun_color(sun_position, pass)
  local sun_dir = vec3(sun_position):normalize()
  sun_dir = quat(-math.pi / 20, 1,0,0):mul(sun_dir)
  local x, y, z = sun_dir:unpack()
  local absx, absy, absz = math.abs(x), math.abs(y), math.abs(z)
  local face_index, u, v
  local uv = vec2()
  if absx > absy and absx > absz then
    if x < 0 then
      face_index = 1
      u = 0.5 * (-z / absx + 1)
      v = 0.5 * (-y / absx + 1)
    else
      face_index = 2
      u = 0.5 * ( z / absx + 1)
      v = 0.5 * (-y / absx + 1)
    end
  elseif absy > absx and absy > absz then
    if y > 0 then
      face_index = 3
      u = 0.5 * (-x / absy + 1)
      v = 0.5 * ( z / absy + 1)
    else
      face_index = 4
      u = 0.5 * (-x / absy + 1)
      v = 0.5 * ( z / absy + 1)
    end
  else
    if z > 0 then
      face_index = 5
      u = 0.5 * (-x / absz + 1)
      v = 0.5 * (-y / absz + 1)
    else
      face_index = 6
      u = 0.5 * ( x / absz + 1)
      v = 0.5 * (-y / absz + 1)
    end
  end
  local readback = self.cubetex:newReadback(0, 0, face_index)
  readback:wait()
  local image = readback:getImage()
  local px = math.floor(u * (self.resolution - 1))
  local py = math.floor(v * (self.resolution - 1))
  local color = vec3(image:getPixel(px, py))
  return color
end


local skybox_vfog_shader = lovr.graphics.newShader('cubemap', vfog.fragment .. [[
layout(set = 1, binding = 1) uniform textureCube SkyboxTexture;
uniform mat4 vp;

void addVFogPosition(inout vec4 color, vec3 position) {
  if (disabled) return;
  vec3 frustumCoord = uvFromWorld(position, 0.01, fog_distance, vp);
  vec4 scatteringInfo = getPixel(lookup_volume, frustumCoord);
  color.rgb *= scatteringInfo.a;   // transmittance
  color.rgb += scatteringInfo.rgb; // in-scattering
}

vec4 lovrmain() {
  vec4 color = Color * getPixel(SkyboxTexture, Normal * vec3(1, 1, -1));
  vec3 position = CameraPositionWorld + normalize(Normal) * fog_distance * 0.96;
  addVFogPosition(color, position);
  return color;
}
]])


function m:draw(pass)
  local pose = pass:getViewPose(1, mat4(), true)
  local projection = pass:getProjection(1, mat4())
  pass:setShader(skybox_vfog_shader)
  vfog.send(pass)
  pass:send('vp', projection * pose)
  pass:setColor(1,1,1)
  pass:skybox(self.cubetex)
end

return m
