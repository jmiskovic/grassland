local m = {}

local sky_shader = lovr.graphics.newShader([[
vec4 lovrmain() {
  return DefaultPosition;
}
]],[[
// Sun rays scattered through atmosphere
// by Rye Terrell (https://github.com/wwwtyro/glsl-atmosphere)
#define iSteps 16
#define jSteps 8

vec2 rsi(vec3 r0, vec3 rd, float sr) {
    // ray-sphere intersection that assumes
    // the sphere is centered at the origin.
    // No intersection when result.x > result.y
    float a = dot(rd, rd);
    float b = 2.0 * dot(rd, r0);
    float c = dot(r0, r0) - (sr * sr);
    float d = (b*b) - 4.0*a*c;
    if (d < 0.0) return vec2(1e5,-1e5);
    return vec2(
        (-b - sqrt(d))/(2.0*a),
        (-b + sqrt(d))/(2.0*a)
    );
}

vec3 atmosphere(vec3 r, vec3 r0, vec3 pSun, float iSun, float rPlanet, float rAtmos, vec3 kRlh, float kMie, float shRlh, float shMie, float g) {
    // Normalize the sun and view directions.
    pSun = normalize(pSun) * vec3(-1., 1., -1.);
    r = normalize(r);
    // Calculate the step size of the primary ray.
    vec2 p = rsi(r0, r, rAtmos);
    if (p.x > p.y) return vec3(0,0,0);
    p.y = min(p.y, rsi(r0, r, rPlanet).x);
    float iStepSize = (p.y - p.x) / float(iSteps);

    // Initialize the primary ray time.
    float iTime = 0.0;

    // Initialize accumulators for Rayleigh and Mie scattering.
    vec3 totalRlh = vec3(0,0,0);
    vec3 totalMie = vec3(0,0,0);

    // Initialize optical depth accumulators for the primary ray.
    float iOdRlh = 0.0;
    float iOdMie = 0.0;

    // Calculate the Rayleigh and Mie phases.
    float mu = dot(r, pSun);
    float mumu = mu * mu;
    float gg = g * g;
    float pRlh = 3.0 / (16.0 * PI) * (1.0 + mumu);
    float pMie = 3.0 / (8.0 * PI) * ((1.0 - gg) * (mumu + 1.0)) / (pow(1.0 + gg - 2.0 * mu * g, 1.5) * (2.0 + gg));

    // Sample the primary ray.
    for (int i = 0; i < iSteps; i++) {

        // Calculate the primary ray sample position.
        vec3 iPos = r0 + r * (iTime + iStepSize * 0.5);

        // Calculate the height of the sample.
        float iHeight = length(iPos) - rPlanet;

        // Calculate the optical depth of the Rayleigh and Mie scattering for this step.
        float odStepRlh = exp(-iHeight / shRlh) * iStepSize;
        float odStepMie = exp(-iHeight / shMie) * iStepSize;

        // Accumulate optical depth.
        iOdRlh += odStepRlh;
        iOdMie += odStepMie;

        // Calculate the step size of the secondary ray.
        float jStepSize = rsi(iPos, pSun, rAtmos).y / float(jSteps);

        // Initialize the secondary ray time.
        float jTime = 0.0;

        // Initialize optical depth accumulators for the secondary ray.
        float jOdRlh = 0.0;
        float jOdMie = 0.0;

        // Sample the secondary ray.
        for (int j = 0; j < jSteps; j++) {

            // Calculate the secondary ray sample position.
            vec3 jPos = iPos + pSun * (jTime + jStepSize * 0.5);

            // Calculate the height of the sample.
            float jHeight = length(jPos) - rPlanet;

            // Accumulate the optical depth.
            jOdRlh += exp(-jHeight / shRlh) * jStepSize;
            jOdMie += exp(-jHeight / shMie) * jStepSize;

            // Increment the secondary ray time.
            jTime += jStepSize;
        }

        // Calculate attenuation.
        vec3 attn = exp(-(kMie * (iOdMie + jOdMie) + kRlh * (iOdRlh + jOdRlh)));

        // Accumulate scattering.
        totalRlh += odStepRlh * attn;
        totalMie += odStepMie * attn;

        // Increment the primary ray time.
        iTime += iStepSize;

    }

    // Calculate and return the final color.
    return iSun * (pRlh * kRlh * totalRlh + pMie * kMie * totalMie);
}


Constants {
    float horizon_offset;
    vec3 sun_position;
    float sun_intensity;
    float haze;
    vec3 hue;
    float gamma_correction;
    float sun_sharpness;
};

vec4 lovrmain() {
    float planetR = 6371e3;
    vec3 rayDir = normalize(PositionWorld + vec3(0., horizon_offset, 0.));
    vec3 rayOrg = vec3(0., planetR + 1000., 0.);
    float mie_scattering = clamp((4. - 4. * haze) * 2e-6, 0.000005, 3.);
    float mie_dir = clamp(0.5 + sun_sharpness / 2, 0., 0.999);
    vec3 kRlh = max(hue * 3e-5, 0.);
    vec3 color = atmosphere(
        rayDir,           // normalized ray direction
        rayOrg,           // ray origin
        sun_position,     // position of sun
        sun_intensity,    // intensity of the sun
        planetR,          // radius of the planet in meters
        planetR * 1.0157, // radius of the atmosphere in meters
        kRlh,             // Rayleigh scattering coefficient
        mie_scattering,   // Mie scattering coefficient
        10e3,             // Rayleigh scale height
        1.2e3,            // Mie scale height
        mie_dir           // Mie preferred scattering direction
    );
    // Apply exposure
    color = 1.0 - exp(-1. * color);
    color = pow(color, vec3(gamma_correction));
    return vec4(color, Color.a);
}
]])

m.gpu = {
  haze = 0.1,
  horizon_offset = 30,
  sun_intensity = 40,
  sun_sharpness = 0.95,
  sun_position = Vec3(2, 2, -1),
  gamma_correction = 2.2,
  hue = Vec3(0.2, 0.6, 1.0),
}

function m.draw(pass)
  pass:setShader(sky_shader)
  for constant, value in pairs(m.gpu) do
    pass:send(constant, value)
  end
  pass:setColor(1,1,1)
  --pass:plane(mat4(lovr.headset.getPose()):translate(0, 0, -2))
  pass:sphere(mat4():scale(-1000))
  pass:setShader()
end

return m
