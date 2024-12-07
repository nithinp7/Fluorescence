
#include <Misc/Sampling.glsl>

// defines SPH kernels
#include "Kernels.glsl"
// defines tile packing / unpacking helpers
// - fp16 velocities, R8G8 quantized positions
#include "TileHelpers.glsl"

float sampleDensity(vec2 pos) {
  float density = 0.0;

  // choose four adjacent tiles, based on which quadrant within the 
  // current tile the pixel resides
  vec2 pixelTileCoord = vec2(pos * vec2(TILE_COUNT_X, TILE_COUNT_Y));
  ivec2 tileCoordStart = 
    ivec2(pixelTileCoord) - ivec2(1) + ivec2(round(fract(pixelTileCoord)));
  for (int i = 0; i < 2; i++) for (int j = 0; j < 2; j++) {
    ivec2 tileCoord = tileCoordStart + ivec2(i, j);
    if (tileCoord.x < 0 || tileCoord.y < 0 ||
        tileCoord.x >= TILE_COUNT_X || tileCoord.y >= TILE_COUNT_Y) {
      continue;
    }
  
    uint tileIdx = tileCoord.y * TILE_COUNT_X + tileCoord.x;
    uint offset, count;
    getTile(tileIdx, offset, count);
    for (uint k = 0; k < count; k++) {
      uint particleIdx = offset + k;
      vec2 particlePos = unpackPos(particleIdx);
      vec2 diff = particlePos - pos;
      float r = sqrt(dot(diff, diff));
      float w = W_2D(r);
      density += PARTICLE_MASS * w;
    }
  }

  return density;
}

vec2 sampleVelocity(vec2 pos) {
  vec2 velocity = vec2(0.0);

  // choose four adjacent tiles, based on which quadrant within the 
  // current tile the pixel resides
  vec2 pixelTileCoord = vec2(pos * vec2(TILE_COUNT_X, TILE_COUNT_Y));
  ivec2 tileCoordStart = 
    ivec2(pixelTileCoord) - ivec2(1) + ivec2(round(fract(pixelTileCoord)));
  for (int i = 0; i < 2; i++) for (int j = 0; j < 2; j++) {
    ivec2 tileCoord = tileCoordStart + ivec2(i, j);
    if (tileCoord.x < 0 || tileCoord.y < 0 ||
        tileCoord.x >= TILE_COUNT_X || tileCoord.y >= TILE_COUNT_Y) {
      continue;
    }
  
    uint tileIdx = tileCoord.y * TILE_COUNT_X + tileCoord.x;
    uint offset, count;
    getTile(tileIdx, offset, count);
    for (uint k = 0; k < count; k++) {
      uint particleIdx = offset + k;
      vec2 particlePos = unpackPos(particleIdx);
      vec2 diff = particlePos - pos;
      float r = sqrt(dot(diff, diff));
      float w = W_2D(r);
      velocity += w * unpackVelocity(particleIdx);
    }
  }

  return velocity;
}

/*
vec2 EOS_pullAccelerationForParticle(uint tileAddr) {
  vec2 acceleration = vec2(0.0);
  
  vec2 pos = unpackPosFromTileAddr(tileAddr);

  // choose four adjacent tiles, based on which quadrant within the 
  // current tile the pixel resides
  vec2 pixelTileCoord = vec2(pos * vec2(TILE_COUNT_X, TILE_COUNT_Y));
  ivec2 tileCoordStart = 
    ivec2(pixelTileCoord) - ivec2(1) + ivec2(round(fract(pixelTileCoord)));
  for (int i = 0; i < 2; i++) for (int j = 0; j < 2; j++) {
    ivec2 tileCoord = tileCoordStart + ivec2(i, j);
    if (tileCoord.x < 0 || tileCoord.y < 0 ||
        tileCoord.x >= TILE_COUNT_X || tileCoord.y >= TILE_COUNT_Y) {
      continue;
    }
  
    uint tileIdx = tileCoord.y * TILE_COUNT_X + tileCoord.x;
    uint count = getParticleCountFromTile(tileIdx);
    for (uint k = 0; k < count; k++) {
      uint otherTileAddr = (tileIdx << 4) | k;
      if (tileAddr == otherTileAddr)
        continue;
      
      vec2 particlePos = unpackPosFromTileAddr(otherTileAddr);
      vec2 diff = particlePos - pos;
      float r = sqrt(dot(diff, diff));
      diff /= r; // TODO: guard this

      float w = W_2D(r);
      velocity += w * unpackVelocityFromTileAddr(otherTileAddr);
    }
  }

  return velocity;
}*/

////////////////////////// COMPUTE SHADERS //////////////////////////

#ifdef IS_COMP_SHADER

void CS_Tick() {
  GlobalState state = globalStateBuffer[0];
  state.tileEntryAllocator = 0;
  state.activeTileCount = 0;

  if (state.bInitialized == 0) {
    {
      uvec2 seed = uvec2(1, 2); 
      for (uint i = 0; i < PARTICLE_COUNT; i++) {
        vec2 pos = randVec2(seed);
        reserveTileEntry(pos);
        // need to keep the seeds the same
        // so generate unused velocity
        vec2 velocity = 0.25 * randVec2(seed);
      }
    }

    for (uint i = 0; i < TILE_COUNT; i++) {
      allocateTile(i);
    }
    
    {
      uvec2 seed = uvec2(1, 2); 
      for (uint i = 0; i < PARTICLE_COUNT; i++) {
        vec2 pos = randVec2(seed);
        uint particleIdx = insertTileEntry(pos);
        vec2 velocity = 0.05 * randVec2(seed);
        insertVelocity(particleIdx, velocity);
      }
    }
    
    state.bInitialized = 1;  
  }

  state.bPhase ^= 1;

  globalStateBuffer[0] = state;
}

void CS_ClearTiles() {
  uint tileIdx = uint(gl_GlobalInvocationID.x);
  if (tileIdx >= TILE_COUNT)
    return;
  
  clearTile(tileIdx);
}

vec2 sampleAccelerationField(vec2 pos) {
  vec2 r = vec2(wave(0.5, 3.0 * pos.x + 5.0 * pos.y), wave(0.5, 7.0 * pos.x + 2.0 * pos.y));
  vec2 a = r * 2.0 - vec2(1.0);
  a *= (0.001 * TEST_SLIDER) * wave(1.3, 1.0);
  return a;
}

void CS_UpdateParticles_Reserve() {
  uint particleIdx = uint(gl_GlobalInvocationID.x);
  if (particleIdx >= PARTICLE_COUNT)
    return;

  vec2 prevPos = unpackPrevPos(particleIdx);
  vec2 vel = unpackPrevVelocity(particleIdx);
  vel += sampleAccelerationField(prevPos);
  vel.y += GRAVITY;
  
  // TODO: clamp velocity
  vec2 dpos = vel * DELTA_TIME;
  vec2 nextPos = prevPos + dpos;

  // TODO: remove hack
  nextPos = fract(nextPos);

  reserveTileEntry(nextPos);
}

void CS_AllocateTiles() {
  uint tileIdx = uint(gl_GlobalInvocationID.x);
  if (tileIdx >= TILE_COUNT) 
    return;
  
  allocateTile(tileIdx);
}

void CS_UpdateParticles_Insert() {
  uint particleIdx = uint(gl_GlobalInvocationID.x);
  if (particleIdx >= PARTICLE_COUNT)
    return;

  vec2 prevPos = unpackPrevPos(particleIdx);
  vec2 vel = unpackPrevVelocity(particleIdx);  
  vel += sampleAccelerationField(prevPos);
  vel.y += GRAVITY;
  
  // TODO: clamp velocity
  vec2 dpos = vel * DELTA_TIME;
  vec2 nextPos = prevPos + dpos;

  // TODO: remove hack
  nextPos = fract(nextPos);

  particleIdx = insertTileEntry(nextPos);
  insertVelocity(particleIdx, vel);
}

void CS_ComputeDensities() {
  uint tileIdx = uint(gl_GlobalInvocationID.x);
  if (tileIdx >= TILE_COUNT)
    return;

}

void CS_ComputePressures() {
  uint tileIdx = uint(gl_GlobalInvocationID.x);
  if (tileIdx >= TILE_COUNT)
    return;

}

void CS_ComputeAccelerations() {
  uint tileIdx = uint(gl_GlobalInvocationID.x);
  if (tileIdx >= TILE_COUNT)
    return;

}

#endif // IS_COMP_SHADER

////////////////////////// VERTEX SHADERS //////////////////////////

#ifdef IS_VERTEX_SHADER
layout(location = 0) out vec2 outScreenUv;
layout(location = 1) out vec3 outColor;

void VS_Tiles() {
  vec2 pos = VS_FullScreen();
  gl_Position = vec4(pos * 2.0 - 1.0, 0.0, 1.0);
  outScreenUv = pos;
}

void VS_Particles() {
  vec2 particlePos = unpackPos(gl_InstanceIndex);
  const float radius = DISPLAY_RADIUS * PARTICLE_RADIUS;
  // const float radius = 0.1 * TILE_WIDTH;
  vec2 vertPos = VS_Circle(gl_VertexIndex, particlePos, radius, PARTICLE_CIRCLE_VERTS);
  outScreenUv = vertPos;
  // uvec2 seed = uvec2(gl_InstanceIndex, gl_InstanceIndex + 1);
  outColor = vec3(1.0,0.0, 1.0);//randVec3(seed);
  gl_Position = vec4(vertPos * 2.0f - 1.0f, 0.0f, 1.0f);
}
#endif // IS_VERTEX_SHADER

////////////////////////// PIXEL SHADERS //////////////////////////

#ifdef IS_PIXEL_SHADER
layout(location = 0) in vec2 inScreenUv;
layout(location = 1) in vec3 inColor;

layout(location = 0) out vec4 outColor;

void PS_Tiles() {
  uint tileIdx = getTileIdxFromUv(inScreenUv);
  vec3 color = vec3(inScreenUv, float(tileIdx % 2));
  uint offset, count;
  getTile(tileIdx, offset, count);
  if (count > 0)
     color = vec3(1.0, 0.0, 0.0);
  outColor = vec4(color, 1.0);
}

void PS_TilesDensity() {
  float density = sampleDensity(inScreenUv);
  float pressure = 
      EOS_SOLVER_STIFFNESS * 
        (pow(density / EOS_SOLVER_REST_DENSITY, EOS_SOLVER_COMPRESSIBILITY) - 1.0);
  // density *= density;
  vec2 velocity = 0.1 * normalize(sampleVelocity(inScreenUv));
  outColor = vec4(vec3(0.001 * pressure), 1.0);//, 1.0);
  // outColor = vec4(vec3(density), 1.0);
}

void PS_Particles() {
  outColor = vec4(inColor, 1.0);
}
#endif // IS_PIXEL_SHADER

