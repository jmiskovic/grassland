local m = {}

local grid_size = {x = 160, y = 100, z = 128}
local pose_matrix = Mat4()
local projection_matrix = Mat4()
local camera_position = Vec3()

local view_proj_inv = Mat4()
local view_proj_prev = Mat4()

m.scatter_volume_index = 1

m.gpu = {
  disabled = false,
  absorption_strength = 8.5,
  scattering_strength = 40,
  fog_distance = 200,
  height_falloff = 0.1,
  sun_position = Vec3(2, 2, -1),
  sun_radiance = Vec3(1, 1, 1),
  ambient_density = 0.16,
  noise_intensity = 1.5,
  noise_frequency = 0.02,
  phase_anisotropy = 0.2,
  temporal_accumulation = 0.4,
  temporal_jitter = 0.2,
}

local transforms_glsl = [[
float depthFromIndex(int index, float near, float fog_far, ivec3 grid_size) {
  return near + near * (exp(float(index) * log(fog_far / near) / (grid_size.z - 1)) - 1.);
}

float uvFromDepth(float depth, float near, float fog_far) {
  return log((depth - near) / near + 1.) / log(fog_far / near);
}

float slice_thickness(int z, float near, float fog_far, ivec3 grid_size) {
  return depthFromIndex(z + 1, near, fog_far, grid_size) - depthFromIndex(z, 0.01, fog_far, grid_size);
}

vec3 worldFromCoord(ivec3 coord, float jitter, float n, float fog_far, mat4 view_proj_inv, ivec3 grid_size) {
    vec2 uv = vec2(
      (float(coord.x) + 0.5) / float(grid_size.x),
      (float(coord.y) + 0.5) / float(grid_size.y));
    vec3 ndc;
    ndc.x = 2.0 * uv.x - 1.0;
    ndc.y = 2.0 * uv.y - 1.0;
    float depth = depthFromIndex(coord.z, n, fog_far, grid_size);
    ndc.z = n / (depth + jitter);
    vec4 p = view_proj_inv * vec4(ndc, 1.0);
    if (p.w > 0.0) {
      p.xyz /= p.w;
    }
    return p.xyz;
}

vec3 uvFromWorld(vec3 world_pos, float n, float fog_far, mat4 vp) {
  vec4 ndc = vp * vec4(world_pos, 1.0);
  if (ndc.w > 0.0) {
    ndc.xyz /= ndc.w;
  }
  vec3 uv;
  uv.x = (ndc.x + 1.0) * 0.5;
  uv.y = (ndc.y + 1.0) * 0.5;
  float depth = n / ndc.z;
  uv.z = uvFromDepth(depth, n, fog_far);
  return uv;
}
]]


local density_shader = lovr.graphics.newShader(transforms_glsl .. [[
#include "common_noise.glsl" // vfog height falloff uses terrain contours

layout(rgba16f) uniform writeonly image3D scatter_volume;
layout(rgba16f) uniform readonly image3D scatter_volume_prev;
ivec3 grid_size = imageSize(scatter_volume);

layout(local_size_x = 8, local_size_y = 8, local_size_z = 8) in;

uniform float Time;

uniform vec3 sun_position;
uniform vec3 sun_radiance;

uniform mat4 view_proj_inv;
uniform mat4 view_proj_prev;
uniform vec3 camera_position;

uniform float temporal_jitter;
uniform float scattering_strength;
uniform float absorption_strength;
uniform float fog_distance;
uniform float phase_anisotropy;
uniform float height_falloff;
uniform float temporal_accumulation;
uniform float ambient_density;
uniform float noise_frequency;
uniform float noise_intensity;

struct PointLight {
    vec3 position;
    vec3 radiance;
};
layout(std140) buffer point_lights_buffer {
    PointLight point_lights[];
};

float phaseHenyeyGreenstein(float cosTheta, float g) {
  float g2 = g * g;
  return (1.0 - g2) / pow(1.0 + g2 - 2.0 * g * cosTheta, 1.5) / (4.0 * 3.14159);
}

float sdSphere(vec3 p, float s) {
  return length(p) - s;
}

float mod289(float x){ return x - floor(x * (1.0 / 289.0)) * 289.0; }
vec4 mod289(vec4 x){ return x - floor(x * (1.0 / 289.0)) * 289.0; }
vec4 perm(vec4 x){ return mod289(((x * 34.0) + 1.0) * x); }
float noise(vec3 p) {
    vec3 a = floor(p);
    vec3 d = p - a;
    d = d * d * (3.0 - 2.0 * d);
    vec4 b = a.xxyy + vec4(0.0, 1.0, 0.0, 1.0);
    vec4 k1 = perm(b.xyxy);
    vec4 k2 = perm(k1.xyxy + b.zzww);
    vec4 c = k2 + a.zzzz;
    vec4 k3 = perm(c);
    vec4 k4 = perm(c + 1.0);
    vec4 o1 = fract(k3 * (1.0 / 41.0));
    vec4 o2 = fract(k4 * (1.0 / 41.0));
    vec4 o3 = o2 * d.z + o1 * (1.0 - d.z);
    vec2 o4 = o3.yw * d.x + o3.xz * (1.0 - d.x);
    return o4.y * d.y + o4.x * (1.0 - d.y);
}

float fbm(vec3 x, float alpha) {
  float v = 0.0;
  float a = 0.5;
  x.y -= -alpha;
  vec3 shift = vec3(100. + alpha);
  for (int i = 0; i < 4; ++i) {
    v += a * noise(x);
    x = x * 3.0 + shift;
    a *= 0.5;
  }
  return v * 4. - 1.;
}

void lovrmain() {
  ivec3 coord = ivec3(gl_GlobalInvocationID.xyz);
  if (any(greaterThanEqual(coord, ivec3(grid_size.x, grid_size.y, grid_size.z))))
    return;

  // temporal jitter reduces camera motion artifacts due to raymarching the low resolution texture
  float jitter = noise(vec3(coord.xy, Time * 100.)) * temporal_jitter;

  vec3 worldPos = worldFromCoord(coord, jitter, 0.01, fog_distance, view_proj_inv, grid_size);

  // atmosphere density falling off with height
  float height = (worldPos.y - terrain(worldPos.xz));
  float density = exp(-height * height_falloff);
  // clouds from noise
  density *= mix(1., fbm(worldPos * vec3(noise_frequency, noise_frequency * 2., noise_frequency), Time * 0.05),
    noise_intensity);
  density = clamp(density + ambient_density, 1e-8, 1e3);

  float layerThickness = slice_thickness(coord.z, 0.01, fog_distance, grid_size);
  float scattering = scattering_strength * 1e-6 * density * layerThickness * grid_size.z;
  float absorption = absorption_strength * 1e-6 * density * layerThickness * grid_size.z;
  vec3 viewDir = normalize(worldPos - camera_position);
  vec3 lighting = vec3(0.f);

  // sun
  float cosTheta;
  cosTheta = dot(normalize(sun_position), viewDir);
  float sun_anisotropy = phase_anisotropy; // non-realistic ambience
  lighting += sun_radiance * phaseHenyeyGreenstein(cosTheta, sun_anisotropy);

  // point lights
  for (int i = 0; i < point_lights.length(); ++i) {
    vec3 lightDir = point_lights[i].position.xyz - worldPos;
    cosTheta = dot(viewDir, normalize(lightDir));
    float distance_attenuation = exp(-length(lightDir) * 0.2);
    lighting += point_lights[i].radiance.xyz * distance_attenuation * phaseHenyeyGreenstein(cosTheta, phase_anisotropy);
  }

  vec4 medium = vec4(lighting * scattering, absorption);

  // temporal accumulation with reprojection
  vec3 uv = uvFromWorld(worldPos, 0.01, fog_distance, view_proj_prev);
  if (all(greaterThanEqual(uv, vec3(0.0))) && all(lessThanEqual(uv, vec3(1.0)))) {
    ivec3 coord_prev = ivec3(uv * grid_size);
    vec4 medium_prev = imageLoad(scatter_volume_prev, coord_prev);
    medium = mix(medium, medium_prev, temporal_accumulation);
  }

  if (any(isnan(medium))) // make NaN show up as magenta
    medium.rgb = vec3(1., 0., 1.);

  imageStore(scatter_volume, coord, medium);
}
]])


local raymarching_shader = lovr.graphics.newShader(transforms_glsl .. [[
layout(local_size_x = 8, local_size_y = 8, local_size_z = 1) in;

layout(rgba16f) uniform readonly image3D scatter_volume;
layout(rgba16f) uniform writeonly image3D lookup_volume;
uniform float fog_distance;
uniform float phase_anisotropy;

ivec3 grid_size = imageSize(scatter_volume);

void lovrmain() {
  ivec3 coord = ivec3(gl_GlobalInvocationID.xyz);
  if (any(greaterThanEqual(coord.xy, ivec2(grid_size.x, grid_size.y))))
    return;

  vec4 accum_scattering_transmittance = vec4(0.0f, 0.0f, 0.0f, 1.0f);
  for (int z = 0; z < grid_size.z; z++)
  {
    ivec3 coord = ivec3(gl_GlobalInvocationID.xy, z);
    vec4 slice_scattering_density = imageLoad(scatter_volume, coord);
    float thickness = slice_thickness(z, phase_anisotropy, fog_distance, grid_size);
    float slice_transmittance = exp(-slice_scattering_density.a * thickness);
    vec3 slice_scattering_integral = slice_scattering_density.rgb * (1.0 - slice_transmittance) / slice_scattering_density.a;
    accum_scattering_transmittance.rgb += slice_scattering_integral * accum_scattering_transmittance.a;
    accum_scattering_transmittance.a *= slice_transmittance;

    if (any(isnan(accum_scattering_transmittance)))
      accum_scattering_transmittance.rgb = vec3(1., 0., 1.);

    imageStore(lookup_volume, coord, accum_scattering_transmittance);
  }
}
]])

function m.load(w, h, d)
  grid_size.x = w or grid_size.x
  grid_size.y = h or grid_size.y
  grid_size.z = d or grid_size.z
  m.pass = lovr.graphics.newPass()
  -- frustum-aligned voxels for medium: RGB is in-scattering, A is extinction
  m.scatter_volumes = {}
  for i = 1, 2 do
    m.scatter_volumes[i] = lovr.graphics.newTexture(
      grid_size.x, grid_size.y, grid_size.z,
      {
        type = '3d',
        format = 'rgba32f',
        linear = true,
        mipmaps = false,
        usage = {'storage', 'sample', 'transfer'}
      }
    )
  end
  -- frustum-aligned voxels for lookup: RGB is in-scattering, A is transmittance
  m.lookup_volume = lovr.graphics.newTexture(
    grid_size.x, grid_size.y, grid_size.z,
    {
      type = '3d',
      format = 'rgba16f',
      linear = true,
      mipmaps = false,
      usage = {'storage', 'sample'}
    }
  )
  m.volume_sampler = lovr.graphics.newSampler({
    min = 'linear',
    mag = 'linear',
    wrap = 'clamp',
  })
  m.point_lights_buffer = lovr.graphics.newBuffer({
    { 'position', 'vec3' },
    { 'radiance', 'vec3' },
    layout = 'std140'
  }, 0)
end


function m.setCamera(pass)
  if m.gpu.disabled then return end
  pass:getViewPose(1, pose_matrix)
  pass:getProjection(1, projection_matrix)
  camera_position:set(pose_matrix)
  view_proj_prev:set(view_proj_inv):invert()
  view_proj_inv:set(pose_matrix * projection_matrix:invert())
end


function m.calculate()
  if m.gpu.disabled then return end
  local dispatch_x = math.ceil(grid_size.x / 8)
  local dispatch_y = math.ceil(grid_size.y / 8)
  local dispatch_z = math.ceil(grid_size.z / 8)
  -- Stage 1: Density estimation & light scattering
  m.pass:reset()
  m.pass:setShader(density_shader)
  m.pass:send('Time', lovr.timer.getTime())
  m.pass:send('scatter_volume', m.scatter_volumes[m.scatter_volume_index])
  m.pass:send('scatter_volume_prev', m.scatter_volumes[3 - m.scatter_volume_index])
  m.pass:send('view_proj_inv', view_proj_inv)
  m.pass:send('view_proj_prev', view_proj_prev)
  m.pass:send('camera_position', camera_position)
  m.pass:send('absorption_strength', m.gpu.absorption_strength)
  m.pass:send('phase_anisotropy', m.gpu.phase_anisotropy)
  m.pass:send('scattering_strength', m.gpu.scattering_strength)
  m.pass:send('height_falloff', m.gpu.height_falloff)
  m.pass:send('temporal_accumulation', m.gpu.temporal_accumulation)
  m.pass:send('ambient_density', m.gpu.ambient_density)
  m.pass:send('noise_frequency', m.gpu.noise_frequency)
  m.pass:send('noise_intensity', m.gpu.noise_intensity)
  m.pass:send('fog_distance', m.gpu.fog_distance)
  m.pass:send('sun_position', m.gpu.sun_position)
  m.pass:send('sun_radiance', m.gpu.sun_radiance)
  m.pass:send('temporal_jitter', m.gpu.temporal_jitter)
  m.pass:send('point_lights_buffer', m.point_lights_buffer)
  m.pass:compute(dispatch_x, dispatch_y, dispatch_z)
  m.pass:barrier()
  -- Stage 2: Ray marching
  m.pass:setShader(raymarching_shader)
  m.pass:send('scatter_volume', m.scatter_volumes[m.scatter_volume_index])
  m.pass:send('lookup_volume', m.lookup_volume)
  m.pass:send('fog_distance', m.gpu.fog_distance)
  m.pass:send('phase_anisotropy', m.gpu.phase_anisotropy)
  m.pass:compute(dispatch_x, dispatch_y)
  lovr.graphics.submit(m.pass)
  m.scatter_volume_index = 3 - m.scatter_volume_index -- flip between 1 and 2 buffers
  return m.pass
end


m.fragment = transforms_glsl .. [[
uniform texture3D lookup_volume;
uniform float fog_distance;
uniform bool disabled;

void addVFog(inout vec4 color) {
  if (disabled) return;
  vec3 frustumCoord = uvFromWorld(PositionWorld, 0.01, fog_distance, ViewProjection);
  vec4 scatteringInfo = getPixel(lookup_volume, frustumCoord);
  color.rgb *= scatteringInfo.a;   // transmittance
  color.rgb += scatteringInfo.rgb; // in-scattering
}
]]


function m.send(pass)
  pass:setSampler(m.volume_sampler)
  pass:send('lookup_volume', m.lookup_volume)
  pass:send('fog_distance', m.gpu.fog_distance)
  pass:send('disabled', m.gpu.disabled)
end


return m
