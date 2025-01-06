
#include <PathTracing/BRDF.glsl>

#include <Misc/Constants.glsl>
#include <Misc/Sampling.glsl>

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

bool sampleDensity(vec3 pos) {
  float h = AMPL * 0.5 * cos(FREQ_A * PI * pos.x + 10.0 * uniforms.time) * 0.5 * cos(FREQ_B * PI * pos.z) + OFFS;
  return pos.y < h;
}

bool sampleBitField(vec3 pos, out uvec3 globalId) {
  if (pos.x < 0.0 || pos.y < 0.0 || pos.z < 0.0 || 
      pos.x > 1.0 || pos.y > 1.0 || pos.z > 1.0) {
    return false;
  }

  // move to grid-space
  pos *= vec3(GRID_DIM_X, GRID_DIM_Y, GRID_DIM_Z) * 0.999;
  uvec3 cellId = uvec3(pos);
  // move to chunk-space 
  pos -= vec3(cellId);
  pos *= 3.999.xxx;
  uvec3 chunkId = uvec3(pos) & 3;
  // move to bit-space
  pos -= vec3(chunkId);
  pos *= 1.999.xxx;
  uvec3 bitId = uvec3(pos) & 1;
  uint bitIdx = (bitId.z << 2) | (bitId.y << 1) | bitId.x;

  globalId = (cellId << 3) | (chunkId << 1) | bitId; 

  uint cellIdx = (cellId.z * GRID_DIM_Y + cellId.y) * GRID_DIM_X + cellId.x;
  uvec4 bitfield[4] = cellBuffer[cellIdx].packedValues;
  uint byteOffset = chunkId.x << 3;

  uint val = ((bitfield[chunkId.z][chunkId.y] >> byteOffset) >> bitIdx) & 1;
  return val != 0;
}

vec3 sampleBitFieldGradient(vec3 pos) {
  uvec3 unused;
  float D = STEP_SIZE;
  return vec3(
      float(sampleBitField(pos + vec3(D, 0.0, 0.0), unused)) - float(sampleBitField(pos - vec3(D, 0.0, 0.0), unused)),
      float(sampleBitField(pos + vec3(0.0, D, 0.0), unused)) - float(sampleBitField(pos - vec3(0.0, D, 0.0), unused)),
      float(sampleBitField(pos + vec3(0.0, 0.0, D), unused)) - float(sampleBitField(pos - vec3(0.0, 0.0, D), unused)));
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
  vec3 subCellSize = 0.125.xxx / vec3(GRID_DIM_X, GRID_DIM_Y, GRID_DIM_Z); // 1 / 8

  // each cell contains a 8x8x8 bitfield
  // this is composed of a 4x4x4 grid of one-byte chunks
  // each one-byte chunk represents a 2x2x2 bitfield
  uvec4 bitfield[4] = {uvec4(0),uvec4(0),uvec4(0),uvec4(0)};
  for (uint byteIdx = 0; byteIdx < 64; byteIdx++) {
    uvec3 chunkId = (uvec3(byteIdx) >> uvec3(0,2,4)) & 3;
    uint byte = 0;
    for (uint bitIdx = 0; bitIdx < 8; bitIdx++) {
      uvec3 bitId = (uvec3(bitIdx) >> uvec3(0,1,2)) & 1;
      vec3 pos = cellStartPos + subCellSize * vec3((chunkId << 1) | bitId);
      byte |= sampleDensity(pos) ? (1 << bitIdx) : 0;
    }
    
    uint byteOffset = chunkId.x << 3;
    bitfield[chunkId.z][chunkId.y] |= (byte << byteOffset);   
  }

  uint cellIdx = (cellId.z * GRID_DIM_Y + cellId.y) * GRID_DIM_X + cellId.x;
  cellBuffer[cellIdx].packedValues = bitfield;
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

  float depth = 0.0;
  bool bPrevInside = false;
  vec3 accumDensity = 0.0.xxx;
  for (uint iter = 0; iter < MAX_ITERS; iter++) {
    depth += STEP_SIZE;
    vec3 samplePos = pos + dir * depth;
    uvec3 globalId;
    bool bInside = sampleBitField(samplePos, globalId);
    if (bInside) {
      if (RENDER_MODE == 0) {
        // outColor = vec4(fract(samplePos), 1.0);
        vec3 n = normalize(sampleBitFieldGradient(samplePos));
        outColor = vec4(sampleEnv(n), 1.0);
        return;
      } else if (RENDER_MODE == 1) {
        uvec2 seed = globalId.xz ^ globalId.yy;
        outColor = vec4(randVec3(seed), 1.0);
        return;
      } else if (RENDER_MODE == 2) {
        if (!bPrevInside) {
          uvec2 seed = globalId.xz ^ globalId.yy;
          mat3 m = LocalToWorld(dir);  
          vec2 deviation = REFRACTION * (2.0 * randVec2(seed) - 1.0.xx);
          dir = normalize(m * vec3(deviation, 1.0));   
        }
        accumDensity += DENSITY * STEP_SIZE;
        continue;
      }
    } 

    bPrevInside = bInside;
  }

  vec3 throughput = exp(-accumDensity.rgb * vec3(RED, GREEN, BLUE));
  outColor = vec4(throughput * sampleEnv(dir), 1.0);
}
#endif // IS_PIXEL_SHADER

