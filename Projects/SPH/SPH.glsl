
#include <Misc/Sampling.glsl>

#define EPS 0.001

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

float EOS_computeDensity(uint particleIdx) {
  float density = 0.0;
  vec2 particlePos = unpackPos(particleIdx);

  // choose four adjacent tiles, based on which quadrant within the 
  // current tile the pixel resides
  vec2 pixelTileCoord = vec2(particlePos * vec2(TILE_COUNT_X, TILE_COUNT_Y));
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
      uint otherParticleIdx = offset + k;
      if (particleIdx == otherParticleIdx)
        continue;
      vec2 otherParticlePos = unpackPos(otherParticleIdx);
      vec2 diff = particlePos - otherParticlePos;
      float r = sqrt(dot(diff, diff));
      float w = W_2D(r);
      density += PARTICLE_MASS * w;
    }
  }

  return density;
}

vec2 EOS_computeAcceleration(uint particleIdx) {
  vec2 acceleration = vec2(0.0);
  vec2 particlePos = unpackPos(particleIdx);
  float density0, pressure0;
  unpackDensityPressure(particleIdx, density0, pressure0);
  float d2_0 = (density0 * density0);
  if (d2_0 < EPS)
    return 0.0.xx;
  float p_over_d2_0 = pressure0 / d2_0;

  // choose four adjacent tiles, based on which quadrant within the 
  // current tile the pixel resides
  vec2 pixelTileCoord = vec2(particlePos * vec2(TILE_COUNT_X, TILE_COUNT_Y));
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
      uint otherParticleIdx = offset + k;
      if (particleIdx == otherParticleIdx)
        continue;
      vec2 otherParticlePos = unpackPos(otherParticleIdx);
      float density1, pressure1;
      unpackDensityPressure(otherParticleIdx, density1, pressure1);
      float d2_1 = density1 * density1;
      if (d2_1 < EPS)
        continue;
      float p_over_d2_1 = pressure1 / d2_1;

      vec2 diff = particlePos - otherParticlePos;
      float r = sqrt(dot(diff, diff));
      if (r < EPS)
        continue;
      float w = W_2D(r);
      const float h = PARTICLE_RADIUS;
      acceleration += -PARTICLE_MASS * (p_over_d2_0 + p_over_d2_1) * grad_W_2D(r) * diff / r;
    }
  }

  return acceleration;
}

////////////////////////// COMPUTE SHADERS //////////////////////////

#ifdef IS_COMP_SHADER

void CS_Tick() {
  GlobalState state = globalStateBuffer[0];
  state.tileEntryAllocator = 0;
  state.activeTileCount = 0;

  if (state.bInitialized == 0 || (uniforms.inputMask & INPUT_BIT_SPACE) != 0) {
    state.bPhase = 0;

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
        vec2 velocity = 0.05 * randVec2(seed);
        insertTileEntry(pos, velocity);
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
  a *= (0.001 * WAVES) * (wave(1.3, 1.0) + 0.1 * wave(2.3 + 0.1 * pos.y * pos.x, pos.x + pos.y));
  return a;
}

void CS_AdvectParticles_Reserve() {
  uint particleIdx = uint(gl_GlobalInvocationID.x);
  if (particleIdx >= PARTICLE_COUNT)
    return;

  vec2 prevPos = unpackPrevPos(particleIdx);
  vec2 vel = unpackPrevVelocity(particleIdx);
  
  // TODO: clamp velocity
  vec2 dpos = vel * DELTA_TIME;
  vec2 nextPos = prevPos + dpos;

  {
    vec2 diff = nextPos - uniforms.mouseUv;
    float r = length(diff);
    if (r < 5.0 * PARTICLE_RADIUS && r > EPS) {
      diff /= r;
      nextPos += (PARTICLE_RADIUS * 5.0 - r) * diff;
    }
  }

  nextPos = clamp(nextPos, 0.0.xx, 1.0.xx);

  reserveTileEntry(nextPos);
}

void CS_AllocateTiles() {
  uint tileIdx = uint(gl_GlobalInvocationID.x);
  if (tileIdx >= TILE_COUNT) 
    return;
  
  allocateTile(tileIdx);
}

void CS_AdvectParticles_Insert() {
  uint particleIdx = uint(gl_GlobalInvocationID.x);
  if (particleIdx >= PARTICLE_COUNT)
    return;

  vec2 prevPos = unpackPrevPos(particleIdx);
  vec2 vel = unpackPrevVelocity(particleIdx);
  
  // TODO: clamp velocity
  vec2 dpos = vel * DELTA_TIME;
  vec2 nextPos = prevPos + dpos;

  {
    vec2 diff = nextPos - uniforms.mouseUv;
    float r = length(diff);
    if (r < 5.0 * PARTICLE_RADIUS && r > EPS) {
      diff /= r;
      nextPos += (PARTICLE_RADIUS * 5.0 - r) * diff;
    }
  }
  nextPos = clamp(nextPos, 0.0.xx, 1.0.xx);

  insertTileEntry(nextPos, vel);
}

void CS_ComputePressures() {
  uint particleIdx = uint(gl_GlobalInvocationID.x);
  if (particleIdx >= PARTICLE_COUNT)
    return;

  vec2 densityPressure;
  float density = EOS_computeDensity(particleIdx);
  float pressure = 
      EOS_SOLVER_STIFFNESS * 
        max(pow(density / EOS_SOLVER_REST_DENSITY, EOS_SOLVER_COMPRESSIBILITY) - 1.0, 0.0);

  packDensityPressure(particleIdx, density, pressure);
}

void CS_UpdateVelocities() {
  uint particleIdx = uint(gl_GlobalInvocationID.x);
  if (particleIdx >= PARTICLE_COUNT)
    return;

  vec2 pos = unpackPos(particleIdx);
  vec2 vel = unpackVelocity(particleIdx);
  vel *= 1.0 - DAMPING;
  vel += sampleAccelerationField(pos);

  uvec2 seed = uvec2(particleIdx, uniforms.frameCount);
  // vel += 0.001 * (2.0 * randVec2(seed) - 1.0.xx);
  vel.y += GRAVITY;

  float density, pressure;
  unpackDensityPressure(particleIdx, density, pressure);
  
  vec2 acceleration = EOS_computeAcceleration(particleIdx);
  // vel.y += -0.0000005 * density * density;
  vel += acceleration * DELTA_TIME;

  packVelocity(particleIdx, vel);
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
  uint particleIdx = gl_InstanceIndex;
  vec2 particlePos = unpackPos(particleIdx);
  const float radius = DISPLAY_RADIUS * PARTICLE_RADIUS;
  // const float radius = 0.1 * TILE_WIDTH;
  vec2 vertPos = VS_Circle(gl_VertexIndex, particlePos, radius, PARTICLE_CIRCLE_VERTS);
  outScreenUv = vertPos;
  
  float density, pressure;
  unpackDensityPressure(particleIdx, density, pressure);

  vec2 acceleration = EOS_computeAcceleration(particleIdx);

  if (DISPLAY_MODE == 0)
    outColor = vec3(0.01 * density, 0.0, 0.05);
  else if (DISPLAY_MODE == 1)
    outColor = vec3(0.0001 * abs(pressure), 0.0, 0.05);
  else if (DISPLAY_MODE == 2)
    outColor = vec3(0.5 * (acceleration) + vec2(0.5), 0.8);
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
  outColor = vec4(vec3(0.01 * pressure), 1.0);//, 1.0);
  if (DISPLAY_MODE == 0) {
    vec2 velocity = sampleVelocity(inScreenUv);
    float speed = length(velocity);
    float theta = 0.01 * speed;
    vec2 cs = 0.5 * vec2(cos(theta), sin(theta)) + 0.5.xx;
    // float theta = atan(velocity.y, velocity.x);
    outColor = vec4(velocity, 0.0, 1.0);//, 1.0);
    // outColor = vec4(0.1 * fract(0.5 * theta / PI), 0.01 * speed, 0.0, 1.0);
    outColor = vec4(0.001 * speed * cs, 0.0, 1.0);
  } else if (DISPLAY_MODE == 3) {
    float accumDensity = 0.0;
    uint ITERS = 25;
    vec2 step = (uniforms.mouseUv - inScreenUv) / ITERS;
    vec2 currentUv = inScreenUv;
    for (uint i = 0; i < ITERS; i++) {
      currentUv += step;
      float d = sampleDensity(currentUv);
      accumDensity += 0.01 * d;
    }
    outColor = vec4(accumDensity.xxx, 1.0);
  }
  // outColor = vec4(vec3(density), 1.0);
}

void PS_Particles() {
  outColor = vec4(inColor, 1.0);
}
#endif // IS_PIXEL_SHADER

