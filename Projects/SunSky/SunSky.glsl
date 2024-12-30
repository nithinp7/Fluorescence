
#include <PathTracing/BRDF.glsl>

#include <Misc/Constants.glsl>
#include <Misc/Sampling.glsl>

#define SDF_GRAD_EPS 0.1

// move to utils
bool intersectSphere(
    vec3 origin, 
    vec3 direction, 
    vec3 center, 
    float radius,
    float distLimit,
    out float t0, 
    out float t1) {
  vec3 co = origin - center;

  // Solve quadratic equation (with a = 1)
  float b = 2.0 * dot(direction, co);
  float c = dot(co, co) - radius * radius;

  float b2_4ac = b * b - 4.0 * c;
  if (b2_4ac < 0.0) {
    // No real roots
    return false;
  }

  float sqrt_b2_4ac = sqrt(b2_4ac);
  t0 = max(0.5 * (-b - sqrt_b2_4ac), 0.0);
  t1 = min(0.5 * (-b + sqrt_b2_4ac), distLimit);

  if (t1 <= 0.0 || t0 >= distLimit) {
    // The entire sphere is behind the camera or occluded by the
    // depth buffer.
    return false;
  }

  return true;
}


// TODO: Units are currently 1=10km, change to 1=1m. 
//#define GROUND_ALT 6360000.0
//#define ATMOSPHERE_ALT 6460000.0
//#define ATMOSPHERE_AVG_DENSITY_HEIGHT 8000.0
#define GROUND_ALT (6360000.0 * ATM_SIZE_SCALE)
#define ATMOSPHERE_ALT (6460000.0 * ATM_SIZE_SCALE)
#define ATMOSPHERE_AVG_DENSITY_HEIGHT 80000.0
#define PLANET_CENTER vec3(0.0,-GROUND_ALT,0.0)

#define ATMOSPHERE_RAYMARCH_STEPS 4
#define ATMOSPHERE_LIGHT_RAYMARCH_STEPS 4
#define ATMOSPHERE_RAYMARCH_MAXDEPTH 1000000000.0

#define SCATTERING_COEFF_RAYLEIGH (vec3(5.8, 13.5, 33.1) * 0.000001)
#define SUN_LIGHT vec3(SUN_LIGHT_SCALE)
/*
vec3 computeScatteringCoeffRayleigh(float height) {
  return vec3(5.8, 13.5, 33.1) * 0.000001;
}*/

float getAltitude(vec3 pos) {
  return length(pos - PLANET_CENTER);
}

float getHeight(vec3 pos) {
  return getAltitude(pos) - GROUND_ALT;
}

// float phaseFunction(float cosTheta, float g) { return 1.0 / 4.0 / PI; }
float phaseFunction(float cosTheta, float g) {
  float g2 = g * g;
  return  
      3.0 * (1.0 - g2) * (1.0 + cosTheta * cosTheta) / 
      (8 * PI * (2.0 + g2) * pow(1.0 + g2 - 2.0 * g * cosTheta, 1.5));
}

float phaseFunctionRayleigh(float cosTheta) {
  return 3.0 * (1.0 + cosTheta * cosTheta) / (16.0 * PI);
}

// compute attenuation due to out-scattering along ray segment
// T(start, end)
vec3 outScattering(vec3 start, vec3 end, int steps) {
  return length(end - start).xxx;
}
vec3 outScattering2(vec3 start, vec3 end, int steps) {
  float K = 1.0; //???
  vec3 dx = (end - start) / float(steps - 1);
  float dxMag = length(dx);
  vec3 x = start;
  
  vec3 intg = vec3(0.0);
  for (int i = 0; i < steps; ++i) {
    float height = getHeight(x);
    if (height <= 0.0) {
      break;
    }

    intg += 
        // exp(-height / ATMOSPHERE_AVG_DENSITY_HEIGHT) * 
        dxMag;
    x += dx;
  }

  return intg;//exp(-SCATTERING_COEFF_RAYLEIGH * length(end - start));
  // return SUN_LIGHT * 4.0 * PI * K * SCATTERING_COEFF_RAYLEIGH * exp(- SCATTERING_COEFF_RAYLEIGH * length(end - start));
}

vec3 inScattering(
    vec3 start, 
    vec3 end, 
    int steps, 
    int outScatterSteps, 
    vec3 sunDir,
    float g) {
  vec3 dx = (end - start) / float(steps - 1);
  float dxMag = length(dx);

  // The phase function does not change along the camera view ray
  // since the sun is treated as infinitely far away
  float phase = //phaseFunctionRayleigh(dot(normalize(start - end), sunDir)); 
      phaseFunction(dot(normalize(start - end), sunDir), g);//-0.99);
  // phase /= 4.0 * PI;
  vec3 x = start;
  vec3 intg = vec3(0.0);
  for (int i = 0; i < steps; ++i) {
    float height = getHeight(x);
    if (height <= 0.0) {
      break;
    }

    vec3 cameraOutScatter = outScattering(x, start, outScatterSteps);
    // Trace a ray to the sun
    float t0;
    float t1;
    // TODO: Is there any reason this would fail?
    bool b = intersectSphere(
        x,
        sunDir,
        PLANET_CENTER,
        ATMOSPHERE_ALT,
        ATMOSPHERE_RAYMARCH_MAXDEPTH,
        t0,
        t1);
    if (!b) {
      x += dx;
      continue;
    }

    // Check if the sun ray is shadowed by the planet
    float gt0;
    float gt1;
    if (intersectSphere(
          x,
          sunDir,
          PLANET_CENTER,
          GROUND_ALT,
          ATMOSPHERE_RAYMARCH_MAXDEPTH,
          gt0,
          gt1)) {
      if (gt0 < t1) {
        x += dx;
        continue;
      }
    }

    // TODO: Assume t0 is 0, since the ray should originate
    // from within the atmosphere
    vec3 sunOutScatter = outScattering(x + t0 * sunDir, x + t1 * sunDir, outScatterSteps);
    // vec3 sunOutScatter = 100000.0.xxx;//outScattering(x + t0 * sunDir, x + t1 * sunDir, outScatterSteps);

    intg += 
        exp(-(sunOutScatter + cameraOutScatter) * phaseFunction(1.0, g) * SCATTERING_COEFF_RAYLEIGH) *
        // exp(-height / ATMOSPHERE_AVG_DENSITY_HEIGHT) *
        // exp(-(cameraOutScatter + sunOutScatter)) * //* scatteringCoeff) * 
        dxMag;
    x += dx;
  }

  return phase * SUN_LIGHT * SCATTERING_COEFF_RAYLEIGH * intg;//SUN_LIGHT * exp(-SCATTERING_COEFF_RAYLEIGH * length(end - start));
}


// TODO: Atmosphere should also render in front of far-away objects
// TODO: Support flying through the atmosphere and into space
vec3 sampleSky(vec3 cameraPos, vec3 dir) {
  // TODO: Parameterize
  float sunTheta = 2.0 * PI * TIME_OF_DAY;
  vec3 sunDir = normalize(vec3(cos(sunTheta), sin(sunTheta), 0.5));

  // Intersect atmosphere
  float t0;
  float t1;
  if (!intersectSphere(
        cameraPos,
        dir,
        PLANET_CENTER,
        ATMOSPHERE_ALT,
        ATMOSPHERE_RAYMARCH_MAXDEPTH,
        t0,
        t1)) {
    return vec3(0.0);
  }

  // Intersect planet sphere
  float t0_;
  float t1_;
  if (intersectSphere(
        cameraPos,
        dir,
        PLANET_CENTER,
        GROUND_ALT,
        ATMOSPHERE_RAYMARCH_MAXDEPTH,
        t0_,
        t1_)) {
    // If the ground blocks part of the atmosphere, take
    // that into account.
    if (t0_ < t0) {
      t0 = t0_;
    }

    if (t0_ < t1) {
      t1 = t0_;
    }
  }

  // float mu = 0.1;
  // float throughput = 1.0;
  // float dt = (t1 - t0) / float(ATMOSPHERE_RAYMARCH_STEPS - 1);
  // for (int i = 0; i < ATMOSPHERE_RAYMARCH_STEPS; ++i) {
  //   float t = t0 + i * dt;
  //   vec3 pos = cameraPos + t * dir;
  //   float density = sampleDensity(pos);
  //   throughput *= exp(-mu * density * dt);
  // }
  vec3 color = 
      inScattering(
        cameraPos + t0 * dir, 
        cameraPos + (t1 - 10.0) * dir,  // ???
        ATMOSPHERE_RAYMARCH_STEPS, 
        ATMOSPHERE_LIGHT_RAYMARCH_STEPS, 
        sunDir,
        0.0) +
      inScattering(
        cameraPos + t0 * dir, 
        cameraPos + t1 * dir, 
        ATMOSPHERE_RAYMARCH_STEPS, 
        ATMOSPHERE_LIGHT_RAYMARCH_STEPS, 
        sunDir,
        -0.9999);

  return color;//vec3(t1 / ATMOSPHERE_ALT);
}

struct Material {
  vec3 diffuse;
  float roughness;
  vec3 emissive;
  float metallic;
};

struct HitResult {
  Material material;
  vec3 pos;
  vec3 grad;
};

vec3 colorRemap(vec3 color) {
  color = vec3(1.0) - exp(-color * 0.3);
  return color;
}

float sampleSdf_Floor(vec3 pos) {
    return pos.y - 2.0;
}

float sampleSdf_Spheres(vec3 pos) {
  // pos = fract(abs(pos) / 10.0) * 10.0;
  //pos;//fract(pos / 10.0) * 10.0;
  pos.x = fract(0.1 * abs(pos.x)) * 10.0;
  pos.y = fract(0.1 * abs(pos.y)) * 10.0;
  // vec3 c = vec3(0.0, 2.0, -5.0);
  vec3 c = 5.0.xxx;
  vec3 diff = pos - c;
  vec3 offs = SLIDER_A * diff;
  float r = 2.0 + 0.05 * wave(10., SLIDER_B * offs.x * offs.z + offs.y + -SLIDER_C * pos.x * pos.y * pos.z);
  float d = length(diff);
  return d - r;
}
float sampleSdf(vec3 pos) {
  return min(sampleSdf_Floor(pos), sampleSdf_Spheres(pos));
}

vec3 sampleSdfGrad(vec3 pos) {
  return vec3(
      sampleSdf(pos + vec3(SDF_GRAD_EPS, 0.0, 0.0)) - sampleSdf(pos - vec3(SDF_GRAD_EPS, 0.0, 0.0)),
      sampleSdf(pos + vec3(0.0, SDF_GRAD_EPS, 0.0)) - sampleSdf(pos - vec3(0.0, SDF_GRAD_EPS, 0.0)),
      sampleSdf(pos + vec3(0.0, 0.0, SDF_GRAD_EPS)) - sampleSdf(pos - vec3(0.0, 0.0, SDF_GRAD_EPS)));
}

Material sampleSdfMaterial(vec3 pos) {
  Material mat;
  // mat.diffuse = vec3(RED * round(fract(abs(3.0 * pos.x - 5.0))), GREEN, BLUE);
  mat.diffuse = vec3(RED, GREEN, BLUE * round(fract(abs(pos.x- 0.25))));
  // mat.diffuse = vec3(0.85, 0.15, 0.15);
  mat.roughness = ROUGHNESS * round(fract(abs(pos.x- 0.25)));// * round(fract(10. * (pos.x + pos.y + pos.z)));
  if (pos.y < 2.1) {
    mat.diffuse = 1.0.xxx;
    // mat.roughness = 0.1;
  mat.roughness = 0.05 + 0.1 * round(fract(abs(pos.x - 0.25))) * round(fract(abs(pos.z - 0.25)));// * round(fract(10. * (pos.x + pos.y + pos.z)));

  }
  
  mat.metallic = 1.0;
  mat.emissive = 0.0.xxx;

  return mat;
}

bool raymarch(vec3 pos, vec3 dir, out HitResult result) {
  for (int i = 0; i < MAX_ITERS; i++) {
    float sdf = (sampleSdf(pos));
    if (sdf < 0.001) {
      result.pos = pos;
      result.grad = sampleSdfGrad(pos);
      result.material = sampleSdfMaterial(pos);
      return true;
    }
    
    pos += dir * sdf;
  }

  return false;
}

vec3 computeDir(vec2 uv) {
	vec2 d = uv * 2.0 - 1.0;

	vec4 target = camera.inverseProjection * vec4(d, 1.0.xx);
	return (camera.inverseView * vec4(normalize(target.xyz), 0)).xyz;
}

vec3 sampleEnv(vec3 dir) {
  return round(0.5 * normalize(dir) + 0.5.xxx);
}

vec4 samplePath(inout uvec2 seed, vec3 pos, vec3 dir) {
  vec4 color = vec4(0.0.xxx, 1.0);

  vec3 throughput = 1.0.xxx;
  for (int bounce = 0; bounce < BOUNCES; bounce++) {
    HitResult hit;
    bool bResult = raymarch(pos, dir, hit);
    vec3 normal = normalize(hit.grad);

    if (!bResult) {
      color.rgb = throughput * 2.0 * sampleSky(pos, dir);//// sampleEnv(dir);
      break;
    }

    if (length(hit.material.emissive) > 0.0)
    {
      color.rgb += throughput * hit.material.emissive;
      break;
    }

    vec3 reflDir;
    float pdf;
    vec3 f = sampleMicrofacetBrdf(
      randVec2(seed), -dir, normal,
      hit.material.diffuse, hit.material.metallic, hit.material.roughness, 
      reflDir, pdf);
    
    if (pdf < 0.05)
      continue;

    throughput *= f * hit.material.diffuse / pdf;

    dir = normalize(reflDir);
    pos = hit.pos + SDF_GRAD_EPS * dir;
  }

  return color;
}

////////////////////////// COMPUTE SHADERS //////////////////////////

#ifdef IS_COMP_SHADER
void CS_Tick() {
  if (!ACCUMULATE || (uniforms.inputMask & INPUT_BIT_SPACE) != 0) 
  {
    globalStateBuffer[0].accumulationFrames = 1;
  } 
  else 
  {
    globalStateBuffer[0].accumulationFrames++;
  }
}

void CS_PathTrace() {
  uvec2 pixelCoord = uvec2(gl_GlobalInvocationID.xy);
  if (pixelCoord.x >= SCREEN_WIDTH || pixelCoord.y >= SCREEN_HEIGHT) {
    return;
  }

  vec4 prevColor = imageLoad(accumulationBuffer, ivec2(pixelCoord));

  uvec2 seed = pixelCoord * uvec2(uniforms.frameCount, uniforms.frameCount + 1);
  
  vec2 uv = vec2(pixelCoord) / vec2(SCREEN_WIDTH, SCREEN_HEIGHT);
  vec3 dir = normalize(computeDir(uv));
  vec3 pos = camera.inverseView[3].xyz;

  vec4 color = samplePath(seed, pos, dir);
  color.rgb = mix(prevColor.rgb, color.rgb, 1.0 / globalStateBuffer[0].accumulationFrames);
  imageStore(accumulationBuffer, ivec2(pixelCoord), color);
}
#endif // IS_COMP_SHADER

////////////////////////// VERTEX SHADERS //////////////////////////

#ifdef IS_VERTEX_SHADER
layout(location = 0) out vec2 outScreenUv;

void VS_SDF() {
  vec2 uv = VS_FullScreen();
  gl_Position = vec4(uv * 2.0 - 1.0, 0.0, 1.0);
  outScreenUv = uv;
}

#endif // IS_VERTEX_SHADER

////////////////////////// PIXEL SHADERS //////////////////////////

#ifdef IS_PIXEL_SHADER
layout(location = 0) in vec2 inScreenUv;

layout(location = 0) out vec4 outColor;

void PS_SDF() {
  vec3 dir = normalize(computeDir(inScreenUv));
  vec3 pos = camera.inverseView[3].xyz;
  
  if (RENDER_MODE == 0) {
    outColor = texture(accumulationTexture, inScreenUv);
  }
  if (RENDER_MODE == 1) {
    HitResult hit;
    bool bResult = raymarch(pos, dir, hit);
    //if (bResult)
      outColor = vec4(0.5 * 0.5 * normalize(hit.grad) + 0.25.xxx, 1.0);
    // else 
      // outColor = vec4(0.0.xxx, 1.0);
  }
  if (RENDER_MODE == 2) {
    HitResult hit;
    bool bResult = raymarch(pos, dir, hit);
    float depth = length(hit.pos - pos);
    if (bResult)
      outColor = vec4((1.0 - depth / (depth + 1.0)).xxx, 1.0);
    else 
      outColor = vec4(0.0.xxx, 1.0);
  }
  
  if (COLOR_REMAP)
    outColor.xyz = colorRemap(outColor.xyz);
}
#endif // IS_PIXEL_SHADER

