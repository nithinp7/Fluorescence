
#include <PathTracing/BRDF.glsl>

#include <Misc/Constants.glsl>
#include <Misc/Sampling.glsl>

vec3 computeLightDir() {
  float theta = 2.0 * PI * LIGHT_ANGLE;
  float c = cos(theta);
  float s = sin(theta);
  return normalize(vec3(0.5 * c, 0.5, 0.5 * s));
}

vec3 computeDir(vec2 uv) {
	vec2 d = uv * 2.0 - 1.0;

	vec4 target = camera.inverseProjection * vec4(d, 1.0.xx);
	return (camera.inverseView * vec4(normalize(target.xyz), 0)).xyz;
}

vec3 sampleEnv(vec3 dir) {
  float c = 5.0;
  vec3 n = 0.5 * normalize(dir) + 0.5.xxx;
  if (BACKGROUND == 0) {
    return round(n * c) / c;
  } else if (BACKGROUND == 1) {
    return round(fract(n * c));
  } else if (BACKGROUND == 2) {
    return round(n);
  } else {
    float f = n.x + n.y + n.z;
    return max(round(fract(f * c)), 0.2).xxx;
  }
}

vec4 samplePath(inout uvec2 seed, vec3 pos, vec3 dir) {
  vec4 color = vec4(0.0.xxx, 1.0);
  color.rgb = sampleEnv(dir);
  return color;
}

vec3 worldPosToGridPos(vec3 pos) {
  return 0.01 * pos;
}

vec3 worldDirToGridDir(vec3 dir) {
  return dir;
}

float sampleDensity(vec3 pos) {
  // float h = AMPL * 0.5 * cos(FREQ_A * PI * pos.x + 10.0 * uniforms.time) * 0.5 * cos(FREQ_B * PI * pos.z) + OFFS;
  // return pos.y < h ? 1.0 : 0.0;
  vec3 c = 0.25.xxx;
  float r = 0.25;

  vec3 diff = pos - c;
  float d = length(diff);
  
  float f = clamp(1.0 - d/r, 0.0, 1.0);
  return f;// * f;
}

float sampleDensityField(vec3 pos, out uvec3 globalId) {
  if (pos.x < 0.0 || pos.y < 0.0 || pos.z < 0.0 || 
      pos.x > 1.0 || pos.y > 1.0 || pos.z > 1.0) {
    return 0.0;
  }

  // move to grid-space
  pos *= vec3(GRID_DIM_X, GRID_DIM_Y, GRID_DIM_Z) * 0.999;
  uvec3 cellId = uvec3(pos);
  // move to chunk-space 
  pos -= vec3(cellId);
  pos *= 3.999.xxx;
  uvec3 chunkId = uvec3(pos) & 3;

  globalId = (cellId << 2) | chunkId; 

  uint cellIdx = (cellId.z * GRID_DIM_Y + cellId.y) * GRID_DIM_X + cellId.x;
  uvec4 packedValues[4] = cellBuffer[cellIdx].packedValues;
  uint byteOffset = chunkId.x << 3;

  uint qvalue = (packedValues[chunkId.z][chunkId.y] >> byteOffset) & 0xFF;
  return float(qvalue) / 256.0;
}

vec3 sampleDensityFieldGrad(vec3 pos) {
  uvec3 unused;
  float D = STEP_SIZE;
  return vec3(
      sampleDensityField(pos + vec3(D, 0.0, 0.0), unused) - sampleDensityField(pos - vec3(D, 0.0, 0.0), unused),
      sampleDensityField(pos + vec3(0.0, D, 0.0), unused) - sampleDensityField(pos - vec3(0.0, D, 0.0), unused),
      sampleDensityField(pos + vec3(0.0, 0.0, D), unused) - sampleDensityField(pos - vec3(0.0, 0.0, D), unused));
}


float phaseFunction(float cosTheta, float g) {
  float g2 = g * g;
  return  
      3.0 * (1.0 - g2) * (1.0 + cosTheta * cosTheta) / 
      (8 * PI * (2.0 + g2) * pow(1.0 + g2 - 2.0 * g * cosTheta, 1.5));
}

vec3 raymarchLight(vec3 pos, vec3 dir) {
  float depth = 0.0;
  vec3 throughput = 1.0.xxx;
  vec3 accumDensity = 0.0.xxx;
  for (uint iter = 0; iter < MAX_ITERS; iter++) {
    depth += STEP_SIZE;
    vec3 samplePos = pos + dir * depth;
    uvec3 globalId;
    float density = sampleDensityField(samplePos, globalId);
    throughput *= exp(-density * DENSITY * STEP_SIZE);
  }

  return sampleEnv(dir) * throughput;
}

vec3 raymarchCellId(vec3 pos, vec3 dir) {
  float depth = 0.0;
  vec3 throughput = 1.0.xxx;
  vec3 accumDensity = 0.0.xxx;
  for (uint iter = 0; iter < MAX_ITERS; iter++) {
    depth += STEP_SIZE;
    vec3 samplePos = pos + dir * depth;
    uvec3 globalId;
    float density = sampleDensityField(samplePos, globalId);
    if (density > 0.0) {
      uvec2 seed = globalId.xz ^ globalId.yy;
      return randVec3(seed);
    }
  }
}

vec3 raymarchReflection(vec3 pos, vec3 dir) {
  float depth = 0.0;
  vec3 throughput = 1.0.xxx;
  vec3 accumDensity = 0.0.xxx;
  for (uint iter = 0; iter < MAX_ITERS; iter++) {
    depth += STEP_SIZE;
    vec3 samplePos = pos + dir * depth;
    uvec3 globalId;
    float density = sampleDensityField(samplePos, globalId);
    if (density > 0.0) {
      vec3 n = normalize(sampleDensityFieldGrad(samplePos));
      return sampleEnv(n);
    }
  }
}

////////////////////////// COMPUTE SHADERS //////////////////////////

#ifdef IS_COMP_SHADER
void CS_Tick() {

}

void CS_UpdateVoxels() {
  uvec3 cellId = uvec3(gl_GlobalInvocationID.xyz);
  if (cellId.x >= GRID_DIM_X || 
      cellId.y >= GRID_DIM_Y ||
      cellId.z >= GRID_DIM_Z) {
    return;
  }

  vec3 cellStartPos = vec3(cellId) / vec3(GRID_DIM_X, GRID_DIM_Y, GRID_DIM_Z);
  vec3 chunkSize = 0.25.xxx / vec3(GRID_DIM_X, GRID_DIM_Y, GRID_DIM_Z);

  // each cell contains a 4x4x4 block of 8bit quantized densities
  uvec4 packedValues[4] = {uvec4(0),uvec4(0),uvec4(0),uvec4(0)};
  for (uint byteIdx = 0; byteIdx < 64; byteIdx++) {
    uvec3 chunkId = (uvec3(byteIdx) >> uvec3(0,2,4)) & 3;
    vec3 pos = cellStartPos + chunkSize * vec3(chunkId);
    float density = sampleDensity(pos);
    uint qdensity = clamp(uint(density * 256.0), 0, 255);
    uint byteOffset = chunkId.x << 3;
    packedValues[chunkId.z][chunkId.y] |= (qdensity << byteOffset);   
  }

  uint cellIdx = (cellId.z * GRID_DIM_Y + cellId.y) * GRID_DIM_X + cellId.x;
  cellBuffer[cellIdx].packedValues = packedValues;
}
#endif // IS_COMP_SHADER

////////////////////////// VERTEX SHADERS //////////////////////////

#ifdef IS_VERTEX_SHADER
layout(location = 0) out vec2 outScreenUv;

void VS_RayMarchVoxels() {
  vec2 uv = VS_FullScreen();
  gl_Position = vec4(uv * 2.0 - 1.0, 0.0, 1.0);
  outScreenUv = uv;
}

#endif // IS_VERTEX_SHADER

////////////////////////// PIXEL SHADERS //////////////////////////

#ifdef IS_PIXEL_SHADER
layout(location = 0) in vec2 inScreenUv;

layout(location = 0) out vec4 outColor;

void PS_RayMarchVoxels() {
  vec3 dir = worldDirToGridDir(normalize(computeDir(inScreenUv)));
  vec3 pos = worldPosToGridPos(camera.inverseView[3].xyz);

  uvec2 jitterSeed = uvec2(inScreenUv * vec2(SCREEN_WIDTH, SCREEN_HEIGHT));
  pos += 0.01 * rng(jitterSeed) * dir;

  if (RENDER_MODE == 0) {
    outColor = vec4(raymarchReflection(pos, dir), 1.0);
  }
  else if (RENDER_MODE == 1) {
    outColor = vec4(raymarchCellId(pos, dir), 1.0);
  }
  else if (RENDER_MODE == 2) {
    outColor = vec4(raymarchLight(pos, dir), 1.0);
  }
}
#endif // IS_PIXEL_SHADER

