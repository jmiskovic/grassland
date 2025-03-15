local vfog = require('vfog')

local span = 22              -- number of tiles drawn around the camera
local tile_size = 8         -- size of a single tile (both grass and terrain mesh)
local blade_count_sqrt = 40  -- square root of grass blades per single tile

local blade_count = blade_count_sqrt * blade_count_sqrt
local blade_count_low_lod = math.floor(blade_count_sqrt * blade_count_sqrt * 0.5)

local grass_offsets
local crude_blade, fancy_blade
local terrain_mesh

local m = {}

m.gpu = {
  baseColor    = Vec3(0.04, 0.12, 0.01),
  tipColor     = Vec3(0.19, 0.48, 0.12),
  variantColor = Vec3(0.15, 0.11, 0.04),
}

local function sewindices(edgeA, edgeB, offsetA, offsetB)
  offsetA, offsetB = offsetA or 0, offsetB or 0
  local indices = {}
  for i = 1, #edgeA - 1 do
    local cA, cB = edgeA[i], edgeB[i]
    local nA, nB = edgeA[i + 1], edgeB[i + 1]
    table.insert(indices, cA + offsetA) -- triangle I
    table.insert(indices, nB + offsetB)
    table.insert(indices, nA + offsetA)
    table.insert(indices, cA + offsetA) -- triangle II
    table.insert(indices, cB + offsetB)
    table.insert(indices, nB + offsetB)
  end
  return indices
end


local function makeGrassBlade(subdivisions, width)
  local vertices = {}
  local edgeA = {}
  for i = 1, subdivisions do -- left side of the blade
    local half_width = width / 2 * math.cos(math.pow(i / subdivisions, 1.2) * math.pi / 2 * 0.9)
    local height = (i - 1) / (subdivisions - 1)
    local vertex = vec3(-half_width, height, -0.02)
    table.insert(vertices, {vertex:unpack()})
    table.insert(edgeA, i)
  end
  for i = 1, subdivisions do  -- right side of the blade
    local half_width = width / 2 * math.cos(math.pow(i / subdivisions, 1.2) * math.pi / 2 * 0.99)
    local height = (i - 1) / (subdivisions - 1)
    local vertex = vec3(half_width, height, -0.02)
    table.insert(vertices, {vertex:unpack()})
  end
  local indices = sewindices(edgeA, edgeA, 0, subdivisions)
  local format = {{'VertexPosition', 'vec3'},
                  {'VertexNormal',   'vec3'}}
  local mesh = lovr.graphics.newMesh(format, vertices, 'gpu')
  mesh:setIndices(indices)
  mesh:setBoundingBox( -- frustum culling: terrain adds height offset so bbox is vertically extended
    -tile_size, tile_size,
    -1e2, 1e2,
    -tile_size, tile_size)
  return mesh
end


local function makeTerrainTile(size, subdivisions)
  local step = 1 / math.max(math.floor(subdivisions or 1), 1)
  local vertices = {}
  local indices  = {}
  for y = -0.5, 0.5 - step, step do
    for x = -0.5, 0.5 - step, step do
      table.insert(vertices, {size * x, 0, size * y})
      table.insert(vertices, {size * x, 0, size * (y + step)})
      table.insert(vertices, {size * (x + step), 0, size * y})
      table.insert(vertices, {size * (x + step), 0, size * (y + step)})
      table.insert(indices, #vertices - 3)
      table.insert(indices, #vertices - 2)
      table.insert(indices, #vertices - 1)
      table.insert(indices, #vertices - 2)
      table.insert(indices, #vertices)
      table.insert(indices, #vertices - 1)
    end
  end
  mesh = lovr.graphics.newMesh({{ 'VertexPosition', 'vec3' }}, vertices)
  mesh:setIndices(indices)
  mesh:setBoundingBox( -- frustum culling: terrain adds height offset so bbox is vertically extended
    -size / 2, size / 2,
    -1e2, 1e2,
    -size / 2, size / 2)
  return mesh
end


local terrain_shader = lovr.graphics.newShader([[
#include "common_noise.glsl"

vec4 lovrmain() {
  PositionWorld = (WorldFromLocal * VertexPosition).xyz;
  PositionWorld.y += terrain(PositionWorld.xz);
  return Projection * View * vec4(PositionWorld, VertexPosition.w);
}
]], vfog.fragment .. [[
vec4 lovrmain() {
  vec4 color = DefaultColor;
  addVFog(color);
  return color;
}
]])


local grass_shader = lovr.graphics.newShader([[
#include "common_noise.glsl"

layout(std430) buffer Offsets {
  vec2 offsets[160];
};

float rand(float seed) {
  return fract(sin(seed) * 43758.5453123);
}

mat3 rotateX(float angle) {
  float c = cos(angle); float s = sin(angle);
  return mat3(1., 0., 0.,
              0., c, -s,
              0., s,  c);
}

mat3 rotateY(float angle) {
  float c = cos(angle); float s = sin(angle);
  return mat3(c,  0., s,
              0., 1., 0.,
             -s,  0., c);
}

out float bladeLength;
out float terrainHeight;
out float alongBlade;

vec4 lovrmain() {
  float GRASS_HEIGHT = 2.5;
  // offset from input buffer
  vec2 offset2D = offsets[InstanceIndex];
  vec3 offset = vec3(offset2D.x, 0.f, offset2D.y);
  vec3 offsetPos = PositionWorld.xyz + offset;
  // per-instance orientation and curving
  float curvingAmount = (rand(InstanceIndex) - 0.5) * 1.4 * VertexPosition.y;
  mat3 curvingMat = rotateX(curvingAmount);
  mat3 orientationMat = rotateY(rand(InstanceIndex) * TAU);
  PositionWorld = (WorldFromLocal * vec4(orientationMat * curvingMat * VertexPosition.xyz + offset, VertexPosition.w)).xyz;
  alongBlade = PositionWorld.y;

  terrainHeight = 0.;
  // light rolling hills
  terrainHeight += terrain(offsetPos.xz);
  // bushes
  terrainHeight += 1.4 * pow(max(0., noise2(offsetPos.xz * 0.3) + 0.3), 4.);

  PositionWorld.y += terrainHeight;
  // wind bending the blades
  float malleability = 0.1 + 0.9 * rand(InstanceIndex);
  vec2 wind_direction = vec2(noise2(0.03 * (PositionWorld.xz + 17.237 + Time * 5.)) - 0.5,
                             noise2(0.03 * (PositionWorld.xz + 3.7181 + Time * 3.)) - 0.5);
  float wind_strength = 0;
  // occasional gusts
  wind_strength += 1.2 * pow(noise2(0.03 * (PositionWorld.xz * 5. + Time * 3.)), 3.5);
  // constant trembling in slight breeze
  wind_strength += 2. * noise2(1.35 * (PositionWorld.xz + Time));
  // limit wind
  const float wind_max_strength = 1.3;
  wind_strength = wind_max_strength / (1.0 + exp(-max(wind_strength / wind_max_strength, 0.)));
  PositionWorld.xz += malleability * wind_direction * wind_strength * pow(VertexPosition.y, 2.5) * 0.5;

  Normal = vec3(0, 0, 1);
  Normal = orientationMat * curvingMat * Normal;

  return Projection * View * vec4(PositionWorld, VertexPosition.w);
}
]], vfog.fragment .. [[
#include "common_noise.glsl"
in float bladeLength;
in float terrainHeight;
in float alongBlade;

uniform vec3 baseColor;
uniform vec3 tipColor;
uniform vec3 variantColor;

float easeIn(float x, float t) {
  return pow(x, t);
}

vec4 lovrmain() {
  vec4 color = vec4(1.);
  // blade color gradient along its lenght
  vec3 bladeColor = mix(baseColor, tipColor,
    clamp(easeIn(alongBlade, 10.) * 4., 0., 1.));
  // random blobs tinted
  bladeColor = mix(bladeColor, variantColor,
    clamp(easeIn(noise2(PositionWorld.xz * 0.08), 0.6), 0.0, 1.0));
  // simple height-based ambient occlusion
  bladeColor *= clamp(easeIn(alongBlade, 3.4) * 5., 0., 1.);
  color.rgb = bladeColor;
  // fog
  addVFog(color);

  return color;
}
]])


function m.load()
  terrain_mesh = makeTerrainTile(tile_size, 2)
  -- init blade geometry in high and low resolution
  fancy_blade = makeGrassBlade(12, 0.1)
  crude_blade = makeGrassBlade(3,  0.3) -- less details, much ticker
  -- init blade offsets within a tile
  local offsets = {}
  for i = 1, blade_count_sqrt * blade_count_sqrt do
    local x = math.floor((i - 1) / blade_count_sqrt)
    local z = (i - 1) - x * blade_count_sqrt
    x = (x + 0.5 - blade_count_sqrt / 2) / blade_count_sqrt * tile_size
    z = (z + 0.5 - blade_count_sqrt / 2) / blade_count_sqrt * tile_size
    x = x + lovr.math.randomNormal(0.4, 0)
    z = z + lovr.math.randomNormal(0.4, 0)
    offsets[i] = vec2(x, z)
  end
  -- shuffle offsets
  for i = 1, blade_count_sqrt * blade_count_sqrt do
    local j = lovr.math.random(1, blade_count_sqrt * blade_count_sqrt)
    offsets[i], offsets[j] = offsets[j], offsets[i]
  end
  grass_offsets = lovr.graphics.newBuffer('vec2', offsets)
end


function m.draw(pass)
  pass:setFaceCull() -- grass blade only has front face which needs to be rendered from both sides
  pass:setViewCull(true)
  pass:setShader(grass_shader)
  pass:send('Offsets', grass_offsets)
  pass:send('baseColor', m.gpu.baseColor)
  pass:send('tipColor', m.gpu.tipColor)
  pass:send('variantColor', m.gpu.variantColor)
  vfog.send(pass)
  local r_high_lod = span * tile_size * 0.15
  local r2_high_lod = r_high_lod^2
  local r_low_lod = span * tile_size
  local r2_low_lod = r_low_lod^2
  local headset_pose = mat4(lovr.headset.getPose())
  headset_pose:translate(0, 0, -r_high_lod * 0.7)
  local xh, _, zh = headset_pose:unpack()
  local xg = math.floor(xh / tile_size + 0.5) * tile_size
  local zg = math.floor(zh / tile_size + 0.5) * tile_size
  for x = xg - span * tile_size, xg + span * tile_size, tile_size do
    for z = zg - span * tile_size, zg + span * tile_size, tile_size do
      -- use more geometry for close-up grass (in a circle in front of the camera)
      local d2 = (x - xh) * (x - xh) + (z - zh) * (z - zh)
      if d2 < r2_high_lod then
        pass:draw(fancy_blade, x, 0, z, 1, 0, 0,1,0, blade_count)
      elseif d2 < r2_low_lod then
        pass:draw(crude_blade, x, 0, z, 1, 0, 0,1,0, blade_count_low_lod)
      end
    end
  end
  pass:setShader(terrain_shader)
  pass:setFaceCull('back')
  pass:setColor(0.13, 0.15, 0.1)
  for x = xg - span * tile_size, xg + span * tile_size, tile_size do
    for z = zg - span * tile_size, zg + span * tile_size, tile_size do
      local d2 = (x - xh) * (x - xh) + (z - zh) * (z - zh)
      if d2 < r2_low_lod then
        pass:draw(terrain_mesh, x, 0, z)
      end
    end
  end
  pass:setColor(1,1,1)
  pass:setShader()
end

return m
