#ifndef _WORLD_
#define _WORLD_

#include <Misc/Sampling.glsl>

// find a different spot for this ??
float W(float r, float h) {
  const float o = 1.0 / PI / h / h / h;
  float r_h = r / h;

  if (r_h > 2.0)
    return 0.0;
  
  if (r_h <= 1.0) {
    float r_h_2 = r_h * r_h;
    float r_h_3 = r_h_2 * r_h;
    return o * (1.0 - 1.5 * r_h_2 + 0.75 * r_h_3);
  }
  else 
  {
    float t = 2.0 - r_h;
    return o * (0.25 * t * t * t);
  }
}

struct AllocInfo {
  uint offs;
  uint count;
};

AllocInfo getGridAlloc(uint cidx) {
  uint alloc = gridAllocs[cidx];
  return AllocInfo(alloc>>16, alloc&0xFFFF);
}

bool withinGrid(ivec2 c) {
  return c == clamp(c, ivec2(0), ivec2(CELLS_X-1, CELLS_Y-1));
}

uvec2 getGridCell(vec2 uv) {
  ivec2 c = ivec2(uv * vec2(CELLS_X, CELLS_Y));
  return uvec2(clamp(c, ivec2(0), ivec2(CELLS_X-1, CELLS_Y-1)));
}

uvec2 flatToGrid(uint idx) {
  return uvec2(idx % CELLS_X, idx / CELLS_X);
}

uint gridToFlat(uvec2 c) {
  return c.y * CELLS_X + c.x;
}

vec4 getGridColor(uvec2 c) {
  return vec4(randVec3(c), 1.0);
}

Material getParticleMaterial(uint pidx) {
  return materials[particleMaterials[pidx]];
}

vec4 getParticleColor(uint pidx) {
  return vec4(getParticleMaterial(pidx).color, 1.0);
}

uint getCurPhase() { return uniforms.frameCount&1; }
uint getPrevPhase() { return getCurPhase()^1; }

vec2 getCurPos(uint pidx) {
  return positions(getCurPhase())[pidx];
}

void setCurPos(uint pidx, vec2 pos) {
  positions(getCurPhase())[pidx] = pos;
}

vec2 getPrevPos(uint pidx) {
  return positions(getPrevPhase())[pidx];
}

void initParticle(uint pidx, vec2 pos, vec2 vel, uint matIdx) {
  positions(0)[pidx] = pos;
  positions(1)[pidx] = pos;
  impulses[pidx] = vel;
  particleMaterials[pidx] = matIdx;
}

GlobalState initWorld() {
  uvec2 seed = uvec2(25, 27);

  GlobalState state;
  state.particleCount = 0;
  state.segmentCount = 0;
  state.shapeCount = 0;

  for (uint i = 0; i < 4 * 128; i++) {
    uint shapeIdx = state.shapeCount++;

    Shape shape;
    shape.particleStart = state.particleCount;
    state.particleCount += 31;//uint(100.0 * rng(seed));
    bool bOutOfParticles = state.particleCount >= MAX_PARTICLES;
    if (bOutOfParticles) 
      state.particleCount = MAX_PARTICLES;
    shape.particleEnd = state.particleCount;
    shapes[shapeIdx] = shape;

    // one material per shape or now
    uint matIdx = shapeIdx;
    Material mat;
    mat.color = randVec3(seed); 
    mat.shapeIdx = shapeIdx;
    materials[matIdx] = mat;

    vec2 pos = randVec2(seed);
    for (uint j = shape.particleStart; j < shape.particleEnd; j++) {
      vec2 dx = 0.025 * SPACING * (2.0 * randVec2(seed) - 1.0.xx);
      vec2 vel = 0.0.xx;
      initParticle(j, pos, vel, matIdx);
      pos += dx;
    }

    if (bOutOfParticles)
      break;
  }

  globalState[0] = state;

  return state;
}

uint getParticleCount() {
  return globalState[0].particleCount;
}

uint getShapeCount() {
  return globalState[0].shapeCount;
}

uint getSegmentCount() {
  return globalState[0].segmentCount;
}
#endif // _WORLD_