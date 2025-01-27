#include <Misc/Quantization.glsl>

#extension GL_KHR_shader_subgroup_shuffle : enable
#extension GL_KHR_shader_subgroup_shuffle_relative : enable

uint coordToFlatIdx(uvec2 coord) {
  return coord.y * CELLS_X + coord.x;
}

uvec2 flatIdxToCoord(uint idx) {
  return uvec2(idx % CELLS_X, idx / CELLS_X);
}

ivec2 clampCoord(ivec2 coord) {
  if (CLAMP_MODE == 0) {
    // clamp
    return clamp(coord, ivec2(0), ivec2(CELLS_X - 1, CELLS_Y - 1));
  } else {
    // wrap
    return (coord + ivec2(CELLS_X, CELLS_Y) % ivec2(CELLS_X, CELLS_Y));
  }
}

uint quantizeVelocity(vec2 v) {
  float qoffs = -MAX_VELOCITY;
  float qscale = 2.0 * MAX_VELOCITY;
  uint qv = 
    (quantizeFloatToU8(v.x, qoffs, qscale)) |
    (quantizeFloatToU8(v.y, qoffs, qscale) << 8);
  return qv;
}

vec2 dequantizeVelocity(uint vpacked) {
  float qoffs = -MAX_VELOCITY;
  float qscale = 2.0 * MAX_VELOCITY;
  vec2 v = vec2(
    dequantizeU8ToFloat(vpacked & 0xFF, qoffs, qscale), 
    dequantizeU8ToFloat((vpacked >> 8) & 0xFF, qoffs, qscale));
  return v;
}

vec2 readVelocity(uint flatIdx) {
  uint bitoffs = (flatIdx & 1) << 4;
  uint vpacked = (velocityField[flatIdx >> 1].u >> bitoffs) & 0xFFFF;
  return dequantizeVelocity(vpacked);
}

vec2 readVelocity(ivec2 coord) {
  ivec2 clampedCoord = clampCoord(coord);
  vec2 sn = 1.0.xx;
  if (CLAMP_MODE == 0) {
    if (clampedCoord.x != coord.x) return 0.0.xx;//sn.x = -1.0;
    if (clampedCoord.y != coord.y) return 0.0.xx;//sn.y = -1.0;
  }
  return sn * readVelocity(coordToFlatIdx(uvec2(clampedCoord)));
}

vec2 readAdvectedVelocity(uint flatIdx) {
  uint bitoffs = (flatIdx & 1) << 4;
  uint vpacked = (advectedVelocityField[flatIdx >> 1].u >> bitoffs) & 0xFFFF;
  return dequantizeVelocity(vpacked);
}

vec2 readAdvectedVelocity(ivec2 coord) {
  ivec2 clampedCoord = clampCoord(coord);
  vec2 sn = 1.0.xx;
  if (CLAMP_MODE == 0) {
    if (clampedCoord.x != coord.x) return 0.0.xx;//sn.x = -1.0;
    if (clampedCoord.y != coord.y) return 0.0.xx;//sn.y = -1.0;
  }
  return readAdvectedVelocity(coordToFlatIdx(uvec2(clampCoord(coord))));
}

// TODO quantize divergence
void writeDivergence(uint flatIdx, float div) {
  divergenceField[flatIdx].f = div;
}

float readDivergence(uint flatIdx) {
  return divergenceField[flatIdx].f;
}

// TODO: quantize pressure
void writePressure(int phase, uint flatIdx, float pressure) {
  if (phase == 0)
    pressureFieldB[flatIdx].f = pressure;
  else
    pressureFieldA[flatIdx].f = pressure;
}

float readPressure(int phase, uint flatIdx) {
  if (phase == 0)
    return pressureFieldA[flatIdx].f;
  else
    return pressureFieldB[flatIdx].f;
}

float readPressure(int phase, ivec2 coord) {
  return readPressure(phase, coordToFlatIdx(clampCoord(coord)));
}

struct BilerpResult {
  ExtraFields fields;
  vec2 velocity;
};
BilerpResult bilerpFields(vec2 pos) {
  ivec2 c[4];
  c[0] = ivec2(floor(pos));
  c[1] = c[0] + ivec2(1, 0);
  c[2] = c[0] + ivec2(0, 1);
  c[3] = c[0] + ivec2(1, 1);

  vec2 uv = pos - vec2(c[0]);

  BilerpResult res;
  res.velocity = mix(
      mix(readVelocity(c[0]), readVelocity(c[1]), uv.x),
      mix(readVelocity(c[2]), readVelocity(c[3]), uv.x),
      uv.y);
      
  for (int i = 0; i < 4; i++)
    c[i] = clampCoord(c[i]);

  uint flatIdx[4];
  for (int i = 0; i < 4; i++)
    flatIdx[i] = coordToFlatIdx(c[i]);

  res.fields.color = mix(
      mix(extraFields[flatIdx[0]].color, extraFields[flatIdx[1]].color, uv.x),
      mix(extraFields[flatIdx[2]].color, extraFields[flatIdx[3]].color, uv.x),
      uv.y);
  
  return res;
}

vec2 bilerpVelocity(vec2 pos) {
  ivec2 c[4];
  c[0] = ivec2(floor(pos));
  c[1] = c[0] + ivec2(1, 0);
  c[2] = c[0] + ivec2(0, 1);
  c[3] = c[0] + ivec2(1, 1);

  vec2 uv = pos - vec2(c[0]);

  for (int i = 0; i < 4; i++)
    c[i] = clampCoord(c[i]);

  uint flatIdx[4];
  for (int i = 0; i < 4; i++)
    flatIdx[i] = coordToFlatIdx(c[i]);

  return mix(
      mix(readVelocity(flatIdx[0]), readVelocity(flatIdx[1]), uv.x),
      mix(readVelocity(flatIdx[2]), readVelocity(flatIdx[3]), uv.x),
      uv.y);
}

void initVelocity(uint flatIdx) {
  bool bInitRandom = globalStateBuffer[0].initialized <= 1 || (uniforms.inputMask & INPUT_BIT_SPACE) != 0;

  uvec2 coord = flatIdxToCoord(flatIdx);

  if (bInitRandom) {
    uvec2 seed = coord;
    vec2 jitter = 2.0 * randVec2(seed) - 1.0.xx;
    vec2 v = 0.0.xx;//50.0 * normalize(vec2(coord) / vec2(CELLS_X, CELLS_Y) - 0.5.xx);//(2.0 * randVec2(seed) - 1.0.xx);// + 0.01 * jitter;

    uint vpacked = quantizeVelocity(v);
    vpacked |= subgroupShuffleDown(vpacked, 1) << 16;
    if ((flatIdx & 1) == 0) {
      velocityField[flatIdx >> 1].u = vpacked;
      advectedVelocityField[flatIdx >> 1].u = vpacked;
    }

    vec4 rcol = vec4(randVec3(seed), 1.0);
    extraFields[flatIdx].color = rcol;
    advectedExtraFields[flatIdx].color = rcol;
  } else {

    if (coord.x < 40 && coord.y > (SCREEN_HEIGHT / 2 - 20) && coord.y < (SCREEN_HEIGHT / 2 + 20)) {
      if ((flatIdx & 1) == 0) {
        uint vpacked = quantizeVelocity(20000 * vec2(1.0, 0.0));
        vpacked |= vpacked << 16;
        velocityField[flatIdx >> 1].u = vpacked;
      }
    }

    // TODO 
    extraFields[flatIdx] = advectedExtraFields[flatIdx];
  }
}

void advectVelocity(uint flatIdx) {
  if ((uniforms.inputMask & INPUT_BIT_SPACE) != 0) 
    return;
  
  uvec2 coord = flatIdxToCoord(flatIdx);
  vec2 v = readVelocity(flatIdx);
  vec2 pos = vec2(coord);
  pos -= v * DELTA_TIME;

  BilerpResult bilerp = bilerpFields(pos);

  uint vpacked = quantizeVelocity(bilerp.velocity);
  vpacked |= subgroupShuffleDown(vpacked, 1) << 16;
  if ((flatIdx & 1) == 0) {
    advectedVelocityField[flatIdx >> 1].u = vpacked;
  }

  // TODO
  advectedExtraFields[flatIdx] = bilerp.fields;
}

void computeDivergence(uint flatIdx) {
  ivec2 center = ivec2(flatIdxToCoord(flatIdx));
  vec2 vL = readAdvectedVelocity(center + ivec2(-1, 0));
  vec2 vR = readAdvectedVelocity(center + ivec2(1, 0));
  vec2 vU = readAdvectedVelocity(center + ivec2(0, -1));
  vec2 vD = readAdvectedVelocity(center + ivec2(0, 1));

  float div = 0.5 / H * (vR.x - vL.x + vD.y - vU.y);
  writeDivergence(flatIdx, div);
}

void computePressure(int phase, uint flatIdx) {
  ivec2 center = ivec2(flatIdxToCoord(flatIdx));
  float pL = readPressure(phase, center + ivec2(-2, 0));
  float pR = readPressure(phase, center + ivec2(2, 0));
  float pU = readPressure(phase, center + ivec2(0, -2));
  float pD = readPressure(phase, center + ivec2(0, 2));

  float div = readDivergence(flatIdx);

  float p = 0.25 * (pL + pR + pU + pD - div * H * H);
  writePressure(phase, flatIdx, p);
}

void resolveVelocity(uint flatIdx) {
  ivec2 center = ivec2(flatIdxToCoord(flatIdx));
  vec2 v = readAdvectedVelocity(flatIdx);
  float pL = readPressure(0, center + ivec2(-1, 0));
  float pR = readPressure(0, center + ivec2(1, 0));
  float pU = readPressure(0, center + ivec2(0, -1));
  float pD = readPressure(0, center + ivec2(0, 1));

  v -= 0.5 / H * vec2(pR - pL, pD - pU);
  
  uint vpacked = quantizeVelocity(v);
  vpacked |= subgroupShuffleDown(vpacked, 1) << 16;
  if ((flatIdx & 1) == 0) {
    velocityField[flatIdx >> 1].u = vpacked;
  }
}
