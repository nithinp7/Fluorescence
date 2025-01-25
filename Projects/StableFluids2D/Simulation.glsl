#include <Misc/Quantization.glsl>

#extension GL_KHR_shader_subgroup_shuffle : enable
#extension GL_KHR_shader_subgroup_shuffle_relative : enable

uint coordToFlatIdx(uvec2 coord) {
  return coord.y * CELLS_X + coord.x;
}

uvec2 flatIdxToCoord(uint idx) {
  return uvec2(idx % CELLS_X, idx / CELLS_X);
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

  if (CLAMP_MODE == 0) {
    // clamp
    for (int i = 0; i < 4; i++)
      c[i] = clamp(c[i], ivec2(0), ivec2(CELLS_X - 1, CELLS_Y - 1));
  } else {
    // wrap
    for (int i = 0; i < 4; i++)
      c[i] = (c[i] + ivec2(CELLS_X, CELLS_Y) % ivec2(CELLS_X, CELLS_Y));
  }

  uint flatIdx[4];
  for (int i = 0; i < 4; i++)
    flatIdx[i] = coordToFlatIdx(c[i]);

  BilerpResult res;
  res.velocity = mix(
      mix(readVelocity(flatIdx[0]), readVelocity(flatIdx[1]), uv.x),
      mix(readVelocity(flatIdx[2]), readVelocity(flatIdx[3]), uv.x),
      uv.y);
  res.fields.color = mix(
      mix(extraFields[flatIdx[0]].color, extraFields[flatIdx[1]].color, uv.x),
      mix(extraFields[flatIdx[2]].color, extraFields[flatIdx[3]].color, uv.x),
      uv.y);
  
  return res;
}

void initVelocity(uint flatIdx) {
  bool bInitRandom = globalStateBuffer[0].initialized <= 1 || (uniforms.inputMask & INPUT_BIT_SPACE) != 0;

  if (bInitRandom) {
    uvec2 coord = flatIdxToCoord(flatIdx);
    uvec2 seed = coord;
    vec2 jitter = 2.0 * randVec2(seed) - 1.0.xx;
    vec2 v = 50.0 * normalize(vec2(coord) / vec2(CELLS_X, CELLS_Y) - 0.5.xx);//(2.0 * randVec2(seed) - 1.0.xx);// + 0.01 * jitter;

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
    if ((flatIdx & 1) == 0) {
      velocityField[flatIdx >> 1].u = advectedVelocityField[flatIdx >> 1].u;
    }

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

  advectedExtraFields[flatIdx] = bilerp.fields;
}
