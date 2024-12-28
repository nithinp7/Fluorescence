
#include <PathTracing/BRDF.glsl>

#include <Misc/Constants.glsl>
#include <Misc/Sampling.glsl>

#define SDF_GRAD_EPS 0.1

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
  // color *= 25;
  color = vec3(1.0) - exp(-color * 0.3);
  // vec3 color2 = color * color;
  // vec3 color3 = color2 * color;
  // color = -2 * color3 + 3 * color2;
  // color *= color;
  return color;
}

float sampleSdf(vec3 pos) {
  vec3 c = vec3(0.0, 0.0, -5.0);
  vec3 diff = pos - c;
  vec3 offs = SLIDER_A * diff;
  float r = 2.0 + 0.05 * wave(10., SLIDER_B * offs.x * offs.z + offs.y + -SLIDER_C * pos.x * pos.y * pos.z);
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
  mat.diffuse = vec3(0.85, 0.15, 0.15);
  mat.roughness = ROUGHNESS;
  mat.metallic = 0.0;
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
      color.rgb = sampleEnv(dir);
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

