
#include <Misc/Constants.glsl>
#include <Misc/Sampling.glsl>

#define SDF_GRAD_EPS 0.1

struct Material {
  vec3 diffuse;
  float roughness;
};

struct HitResult {
  Material material;
  vec3 pos;
  vec3 grad;
};

vec3 colorRemap(vec3 color) {
  color *= 25;
  color = vec3(1.0) - exp(-color * 0.05);
  vec3 color2 = color * color;
  vec3 color3 = color2 * color;
  color = -2 * color3 + 3 * color2;
  color *= color;
  return color;
}

float sampleSdf(vec3 pos) {
  vec3 fractPos = fract(abs(pos) / 10.0) * 10.0;
  // vec3 fractPos = fract(abs(wave(0.5, 0.001 * pos.x * pos.y - 0.01 *pos.z) * pos) / 10.0) * 10.0;
  vec3 c = 5.0.xxx;
  vec3 diff = fractPos - c;
  vec3 offs = SLIDER_A * diff;
  float r = 1.5 + 0.1 * wave(10., SLIDER_B * offs.x * offs.z + offs.y + -SLIDER_C * pos.x * pos.y * pos.z);
  float d = length(diff);
  return d - r;
}

vec3 sampleSdfGrad(vec3 pos) {
  return vec3(
      sampleSdf(pos + vec3(SDF_GRAD_EPS, 0.0, 0.0)) - sampleSdf(pos - vec3(SDF_GRAD_EPS, 0.0, 0.0)),
      sampleSdf(pos + vec3(0.0, SDF_GRAD_EPS, 0.0)) - sampleSdf(pos - vec3(0.0, SDF_GRAD_EPS, 0.0)),
      sampleSdf(pos + vec3(0.0, 0.0, SDF_GRAD_EPS)) - sampleSdf(pos - vec3(0.0, 0.0, SDF_GRAD_EPS)));
}

Material sampleSdfMaterial(vec3 pos) {
  Material mat;
  mat.diffuse = fract(0.05 * pos);
  mat.roughness = 0.3;
  return mat;
}

bool raymarch(vec3 pos, vec3 dir, out HitResult result) {
  for (int i = 0; i < MAX_ITERS; i++) {
    float sdf = (sampleSdf(pos));
    if (sdf < 0.01) {
      result.pos = pos;
      result.grad = sampleSdfGrad(pos);
      result.material = sampleSdfMaterial(pos);
      return true;
    }
    
    pos += dir * sdf;
  }

  return false;
}
/*
vec3 samplePath(vec3 pos, vec3 dir) {
  int bounces = 3;
  float throughput = 1.0;
  for (int i = 0; i < bounces; i++) {
    
  }
}*/

vec3 computeDir(vec2 uv) {
	vec2 d = uv * 2.0 - 1.0;

	vec4 target = camera.inverseProjection * vec4(d, 1.0.xx);
	return (camera.inverseView * vec4(normalize(target.xyz), 0)).xyz;
}

vec3 sampleEnv(vec3 dir) {
  return 0.5 * normalize(dir) + 0.5.xxx;
}

////////////////////////// COMPUTE SHADERS //////////////////////////

#ifdef IS_COMP_SHADER
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
  vec3 dir = computeDir(inScreenUv); // normalize(inDir);
  vec3 pos = camera.inverseView[3].xyz;
  
  HitResult hit;
  bool bResult = raymarch(pos, dir, hit);
  if (RENDER_MODE == 0) {
    if (bResult) {
      vec3 normal = normalize(hit.grad);
      vec3 reflDir = reflect(dir, normal);
      HitResult reflHit;
      bool bReflResult = raymarch(hit.pos + SDF_GRAD_EPS * normal, reflDir, reflHit);
      // outColor = vec4(hit.material.diffuse, 1.0);
      if (bReflResult) {
        outColor = vec4(reflHit.material.diffuse, 1.0);
      }
      else
        outColor = vec4(sampleEnv(reflDir), 1.0);
    }
    else
      outColor = vec4(sampleEnv(dir), 1.0);
  }
  if (RENDER_MODE == 1) {
    if (bResult)
      outColor = vec4(0.5 * 0.5 * normalize(hit.grad) + 0.25.xxx, 1.0);
    else 
      outColor = vec4(0.0.xxx, 1.0);
  }
  if (RENDER_MODE == 2) {
    float depth = length(hit.pos - pos);
    if (bResult)
      outColor = vec4((1.0 - depth / (depth + 1.0)).xxx, 1.0);
    else 
      outColor = vec4(0.0.xxx, 1.0);
  }
  
  if (COLOR_REMAP)
    outColor.xyz = colorRemap(outColor.xyz);

  if (TEST == 6)
    outColor.x = 1.0;
}
#endif // IS_PIXEL_SHADER

