#include <Misc/Sampling.glsl>
#include "Util.glsl"

#define SPHERE_CENTER vec3(0.0, 0.0, -5.0)
#define SPHERE_RADIUS 2.0

vec2 sampleHeightField(vec2 g) {
  g *= 2.0;
  vec2 h;
  h.x = 0.6 + 0.1 * cos(0.145 * g.x) * cos(0.11 * g.y + 23.0);
  h.y = -0.2 + 0.25* cos(0.15 * g.x + 21.45) * cos(0.09 * g.y + 127.0);
  return h;
}

vec2 applyTurbulence(vec2 pos) {
  float freq = TURB_FREQ;
  float amp = TURB_AMP;
  float speed = TURB_SPEED;

  float cosTheta = cos(TURB_ROT);
  float sinTheta = sin(TURB_ROT);
  mat2 drot = mat2(cosTheta, -sinTheta, sinTheta, cosTheta);
  mat2 rot = drot;

  for (int i = 0; i < 10; i++) {
    float phase = freq * (pos * rot).y + speed * uniforms.time + i;
    pos += amp * rot[0] * sin(phase) / freq;

    rot *= drot;
    freq *= TURB_EXP;
  }
  return pos;
}

vec2 advectedTurbulence(vec2 pos) {
  vec3 col = 0.0.xxx;
  float rm_0 = RM_0;
  vec2 heights = 0.0.xx;
  float turbMult = 1.0;
  float throughput = 1.0;
  if (APPLY_TURBULENCE) {
    for (int i = 0; i < 10; i++) {
      vec2 h = sampleHeightField(pos);
      heights += throughput * vec2(1.0 - h.x, h.y) * float(i) / 20.0;
      vec2 dx = turbMult * (1.9 * rm_0 - i/5.0 * RM_1) * (applyTurbulence(pos) - pos);
      pos += dx;
      turbMult *= TURB_MULT;
      // throughput *= exp(-1);
    }
  } else {
    heights += sampleHeightField(pos);
  }
  // TODO remove
  // density = sampleHeightField(pos).x;

  return vec2(1.0 - heights.x, heights.y);
  // return sampleHeightField(pos);
  // return density;
}

float sampleDensity(vec3 pos) {
  vec2 g = (5.0 * pos.xz);
  vec2 h = advectedTurbulence(g);
  if (pos.y < h.x && pos.y > h.y)
    return DENSITY;
  else
    return 0.0;
}

#ifdef  IS_VERTEX_SHADER
VertexOutput VS_SkyBox() {
  return VertexOutput(VS_FullScreen());
}
#endif // IS_VERTEX_SHADER

#ifdef IS_PIXEL_SHADER
void PS_SkyBox(VertexOutput IN) {
  vec2 dims = vec2(SCREEN_WIDTH, SCREEN_HEIGHT);
  uvec2 seed = uvec2(dims * IN.uv) * uvec2(uniforms.frameCount, uniforms.frameCount + 1);
  // uvec2 jitterSeed = uvec2(dims * IN.uv) * uvec2(231, 73);
#define jitterSeed seed
  vec3 camPos = getCameraPos();
  vec3 dir = computeDir(IN.uv + randVec2(jitterSeed) / dims);
  // vec3 dir = computeDir(IN.uv + 4.0 * randVec2(seed) / dims);

  vec3 col = 0.0.xxx;
  vec3 throughput = 1.0.xxx;
  Sphere sphere = Sphere(SPHERE_CENTER, SPHERE_RADIUS);
  Ray ray = Ray(dir, camPos);
  Hit hit;
  
  if (traceRaySphere(sphere, ray, hit)) {
    vec3 normal = normalize(hit.localPos);
    if (REFRACT_BUBBLE)
      dir = refract(dir, normal, ETA); // TODO need to actually retrace the exit point...
    vec3 pos = camPos;
    for (int sidx = 0; sidx < SAMPLE_COUNT; sidx++) {
      throughput = 1.0.xxx;
      float rmJitter = rng(jitterSeed);
      float dt = (hit.t_exit - hit.t_entry) / RM_ITERS;
      for (int i = 0; i < RM_ITERS; i++) {
        float t = mix(hit.t_entry, hit.t_exit, (float(i) + rmJitter) / RM_ITERS);
        pos = camPos + dir * t;
        float density = sampleDensity(pos);
        if (density > 0.0) {
          vec3 wi = getSunDir(); // TODO indirect sky light...
          // vec3 wi = normalize(randVec3(seed) * 2.0 - 1.0.xxx);
          vec3 Li = sampleSky(wi);
          float lt = 0.0;
          float shadowDepth = 0.0;
          float shadowJitter = rng(jitterSeed);
          for (int j = 0; j < SHADOW_ITERS; j++) {
            vec3 lpos = pos + (lt + shadowJitter) * SHADOW_DT * wi;
            shadowDepth += sampleDensity(lpos) * SHADOW_DT;
            lt += SHADOW_DT;
          }
          col += throughput * SUN_INT.xxx * exp(-shadowDepth);// fract(5.0 * pos);
          throughput *= exp(-density * dt);
        }
      }
    }
    col /= SAMPLE_COUNT;
    vec3 exitNormal = normalize(pos);
    if (REFRACT_BUBBLE)
      dir = refract(dir,- exitNormal, 1.0 / ETA);
  } 

  col += throughput * sampleSky(dir);

  col = remapColor(col);
  outColor = vec4(col, 1.0);
}
#endif // IS_PIXEL_SHADER