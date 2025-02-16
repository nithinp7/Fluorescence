#include <Misc/Quantization.glsl>

#extension GL_KHR_shader_subgroup_shuffle : enable
#extension GL_KHR_shader_subgroup_shuffle_relative : enable

// #define PACKED_PRESSURE
//#define QUANTIZED_PRESSURE 

uint coordToFlatIdx(uvec3 coord) {
  return (coord.y * CELLS_X + coord.x) * CELLS_Z + coord.z;
}

uvec3 flatIdxToCoord(uint idx) {
  uint xy = idx / CELLS_Z;
  return uvec3(xy % CELLS_X, xy / CELLS_X, idx % CELLS_Z);
}

ivec3 clampCoord(ivec3 coord) {
  if (CLAMP_MODE == 0) {
    // clamp
    return clamp(coord, ivec3(0), ivec3(CELLS_X - 1, CELLS_Y - 1, CELLS_Z - 1));
  } else {
    // wrap
    return (coord + ivec3(CELLS_X, CELLS_Y, CELLS_Z) % ivec3(CELLS_X, CELLS_Y, CELLS_Z));
  }
}

// TODO improve velocity packing, 8bits currently unused
uint quantizeVelocity(vec3 v) {
  float qoffs = -MAX_VELOCITY;
  float qscale = 2.0 * MAX_VELOCITY;
  uint qv = 
    (quantizeFloatToU8(v.x, qoffs, qscale)) |
    (quantizeFloatToU8(v.y, qoffs, qscale) << 8) |
    (quantizeFloatToU8(v.z, qoffs, qscale) << 16);
  return qv;
}

vec3 dequantizeVelocity(uint vpacked) {
  float qoffs = -MAX_VELOCITY;
  float qscale = 2.0 * MAX_VELOCITY;
  vec3 v = vec3(
    dequantizeU8ToFloat(vpacked & 0xFF, qoffs, qscale), 
    dequantizeU8ToFloat((vpacked >> 8) & 0xFF, qoffs, qscale),
    dequantizeU8ToFloat((vpacked >> 16) & 0xFF, qoffs, qscale));
  return v;
}

vec3 readVelocity(uint flatIdx) {
  return dequantizeVelocity(velocityField[flatIdx].u);
}

vec3 readVelocity(ivec3 coord) {
  ivec3 clampedCoord = clampCoord(coord);
  if (CLAMP_MODE == 0) {
    if (clampedCoord.x != coord.x) return 0.0.xxx;
    if (clampedCoord.y != coord.y) return 0.0.xxx;
    if (clampedCoord.z != coord.z) return 0.0.xxx;
  }
  return readVelocity(coordToFlatIdx(uvec3(clampedCoord)));
}

void writeVelocity(uint flatIdx, vec3 v) {
  uint vpacked = quantizeVelocity(v);
  velocityField[flatIdx].u = vpacked;
}

vec3 readAdvectedVelocity(uint flatIdx) {
  return dequantizeVelocity(advectedVelocityField[flatIdx].u);
}

vec3 readAdvectedVelocity(ivec3 coord) {
  ivec3 clampedCoord = clampCoord(coord);
  if (CLAMP_MODE == 0) {
    if (clampedCoord.x != coord.x) return 0.0.xxx;
    if (clampedCoord.y != coord.y) return 0.0.xxx;
    if (clampedCoord.z != coord.z) return 0.0.xxx;
  }
  return readAdvectedVelocity(coordToFlatIdx(uvec3(clampedCoord)));
}

void writeAdvectedVelocity(uint flatIdx, vec3 v) {
  uint vpacked = quantizeVelocity(v);
  advectedVelocityField[flatIdx].u = vpacked;
}

// TODO quantize divergence
void writeDivergence(uint flatIdx, float div) {
  scratchField[flatIdx].u = floatBitsToUint(div);
}

float readDivergence(uint flatIdx) {
  return uintBitsToFloat(scratchField[flatIdx].u);
}

void writeCurl(uint flatIdx, vec3 curl) {
  uint vpacked = quantizeVelocity(curl);
  scratchField[flatIdx].u = vpacked;
}

vec3 readCurl(ivec3 coord) {
  ivec3 clampedCoord = clampCoord(coord);
  if (CLAMP_MODE == 0) {
    if (clampedCoord.x != coord.x) return 0.0.xxx;
    if (clampedCoord.y != coord.y) return 0.0.xxx;
    if (clampedCoord.z != coord.z) return 0.0.xxx;
  }
  uint flatIdx = coordToFlatIdx(coord);
  return dequantizeVelocity(scratchField[flatIdx].u);
}

void writePressure(int phase, uint flatIdx, float pressure) {
#ifdef PACKED_PRESSURE
  uint packed = packHalf2x16(vec2(pressure, subgroupShuffleDown(pressure, 1)));
  if ((flatIdx & 1) == 0) {
    if (phase == 0)
      pressureFieldB[flatIdx >> 1].packed = packed;
    else 
      pressureFieldA[flatIdx >> 1].packed = packed;
  }
#elif defined(QUANTIZED_PRESSURE)
  float qoffs = -MAX_PRESSURE;
  float qscale = 2.0 * MAX_PRESSURE;
  uint packed = quantizeFloatToU16(pressure, qoffs, qscale);
  packed |= subgroupShuffleDown(packed, 1) << 16;
  if ((flatIdx & 1) == 0) {
    if (phase == 0) 
      pressureFieldB[flatIdx >> 1].packed = packed;
    else
      pressureFieldA[flatIdx >> 1].packed = packed;
  }
#else
  // pressure = clamp(pressure, -MAX_PRESSURE, MAX_PRESSURE);
  if (phase == 0)
    pressureFieldB[flatIdx].f = pressure;
  else
    pressureFieldA[flatIdx].f = pressure;
#endif
}

float readPressure(int phase, uint flatIdx) {
#ifdef PACKED_PRESSURE
  if (phase == 0)
    return unpackHalf2x16(pressureFieldA[flatIdx >> 1].packed)[flatIdx & 1];
  else 
    return unpackHalf2x16(pressureFieldB[flatIdx >> 1].packed)[flatIdx & 1];
#elif defined(QUANTIZED_PRESSURE)
  uint bitoffs = (flatIdx & 1) << 4;
  uint packed;
  if (phase == 0)
    packed = (pressureFieldA[flatIdx >> 1].packed >> bitoffs) & 0xFFFF;
  else
    packed = (pressureFieldB[flatIdx >> 1].packed >> bitoffs) & 0xFFFF;
  float qoffs = -MAX_PRESSURE;
  float qscale = 2.0 * MAX_PRESSURE;
  return dequantizeU16ToFloat(packed, qoffs, qscale);
#else
  if (phase == 0)
    return pressureFieldA[flatIdx].f;
  else
    return pressureFieldB[flatIdx].f;
#endif
}

float readPressure(int phase, ivec3 coord) {
  if (coord.x < 0) coord.x = -coord.x - 1;
  if (coord.y < 0) coord.y = -coord.y - 1;
  if (coord.z < 0) coord.z = -coord.z - 1;
  if (coord.x >= CELLS_X) coord.x = 2 * CELLS_X - coord.x - 1;
  if (coord.y >= CELLS_Y) coord.y = 2 * CELLS_Y - coord.y - 1;
  if (coord.z >= CELLS_Z) coord.z = 2 * CELLS_Z - coord.z - 1;
  
  return readPressure(phase, coordToFlatIdx(clampCoord(coord)));
}

struct BilerpResult {
  ExtraFields fields;
};
BilerpResult bilerpFields(vec3 pos) {
  ivec3 c[8];
  c[0] = ivec3(floor(pos));
  c[1] = c[0] + ivec3(1, 0, 0);
  c[2] = c[0] + ivec3(0, 1, 0);
  c[3] = c[0] + ivec3(1, 1, 0);
  c[4] = c[0] + ivec3(0, 0, 0);
  c[5] = c[0] + ivec3(1, 0, 1);
  c[6] = c[0] + ivec3(0, 1, 1);
  c[7] = c[0] + ivec3(1, 1, 1);

  vec3 uvw = pos - vec3(c[0]);

  for (int i = 0; i < 8; i++)
    c[i] = clampCoord(c[i]);

  uint flatIdx[8];
  for (int i = 0; i < 8; i++)
    flatIdx[i] = coordToFlatIdx(c[i]);

  BilerpResult res;

  res.fields.color = 
      mix(
        mix(
          mix(
            extraFields[flatIdx[0]].color, 
            extraFields[flatIdx[1]].color, 
            uvw.x),
          mix(
            extraFields[flatIdx[2]].color, 
            extraFields[flatIdx[3]].color, 
            uvw.x),
          uvw.y),
        mix(
          mix(
            extraFields[flatIdx[4]].color, 
            extraFields[flatIdx[5]].color, 
            uvw.x),
          mix(
            extraFields[flatIdx[6]].color, 
            extraFields[flatIdx[7]].color, 
            uvw.x),
          uvw.y),
        uvw.z);
  
  return res;
}

vec3 bilerpVelocity(vec3 pos) {
  vec3 sn = 1.0.xxx;
  if (pos.x < 0.0) {
    pos.x = -pos.x;
    sn.x = -1.0;
  }

  if (pos.y < 0.0) {
    pos.y = -pos.y;
    sn.y = -1.0;
  }

  if (pos.z < 0.0) {
    pos.z = -pos.z;
    sn.z = -1.0;
  }

  if (pos.x >= CELLS_X) {
    pos.x = 2.0 * CELLS_X - pos.x - 0.01;
    sn.x = -1.0;
  }
  
  if (pos.y >= CELLS_Y) {
    pos.y = 2.0 * CELLS_Y - pos.y - 0.01;
    sn.y = -1.0;
  }
  
  if (pos.z >= CELLS_Z) {
    pos.z = 2.0 * CELLS_Z - pos.z - 0.01;
    sn.z = -1.0;
  }

  ivec3 c[8];
  c[0] = ivec3(floor(pos));
  c[1] = c[0] + ivec3(1, 0, 0);
  c[2] = c[0] + ivec3(0, 1, 0);
  c[3] = c[0] + ivec3(1, 1, 0);
  c[4] = c[0] + ivec3(0, 0, 0);
  c[5] = c[0] + ivec3(1, 0, 1);
  c[6] = c[0] + ivec3(0, 1, 1);
  c[7] = c[0] + ivec3(1, 1, 1);

  vec3 uvw = pos - vec3(c[0]);

  return sn * 
    mix(
      mix(
        mix(
          readVelocity(c[0]), 
          readVelocity(c[1]), 
          uvw.x),
        mix(
          readVelocity(c[2]), 
          readVelocity(c[3]), 
          uvw.x),
        uvw.y),
      mix(
        mix(
          readVelocity(c[4]), 
          readVelocity(c[5]), 
          uvw.x),
        mix(
          readVelocity(c[6]), 
          readVelocity(c[7]), 
          uvw.x),
        uvw.y),
      uvw.z);
}

void initVelocity(uint flatIdx) {
  if ((uniforms.inputMask & INPUT_BIT_SPACE) != 0)
    return;

  bool bInitRandom = globalStateBuffer[0].initialized <= 1 || (uniforms.inputMask & INPUT_BIT_R) != 0;

  uvec3 coord = flatIdxToCoord(flatIdx);

  if (bInitRandom) {
    uvec2 seed = coord.xy ^ coord.yz;
    vec3 jitter = 2.0 * randVec3(seed) - 1.0.xxx;
    vec3 v = 0.0.xxx;//50.0 * normalize(vec2(coord) / vec2(CELLS_X, CELLS_Y) - 0.5.xx);//(2.0 * randVec2(seed) - 1.0.xx);// + 0.01 * jitter;

    writeVelocity(flatIdx, v);
    writeAdvectedVelocity(flatIdx, v);

    // vec4 rcol = vec4(randVec3(seed), 1.0);
    vec4 col = vec4(0.0.xxx, 1.0);//vec4(fract(0.01 * vec2(coord)), 0.0, 1.0);
    extraFields[flatIdx].color = col;
    advectedExtraFields[flatIdx].color = col;
    writePressure(0, flatIdx, 0.0);
    writePressure(1, flatIdx, 0.0);
  } else {
    uint ventRadius = 10;
    if (coord.y > (CELLS_Y - 20) && 
        coord.x > (CELLS_X / 2 - ventRadius) && coord.x < (CELLS_X / 2 + ventRadius) &&
        coord.z > (CELLS_Z / 2 - ventRadius) && coord.z < (CELLS_Z / 2 + ventRadius)) {
      uint vpacked = quantizeVelocity(vec3(0.0, -0.5 * 0.0 * MAX_VELOCITY, 0.0));
      velocityField[flatIdx].u = vpacked;
      extraFields[flatIdx].color = vec4(1.0, 0.1 * wave(10, 5) + 0.2, 0.05 * wave(32, 1), 1.0);
    } else {
      // TODO 
      extraFields[flatIdx] = advectedExtraFields[flatIdx];
    }
  }
}

float curl2D(vec2 vL, vec2 vR, vec2 vU, vec2 vD) {
  return vR.y - vL.y + vD.x - vU.x;
}

void computeCurl(uint flatIdx) {
  ivec3 coord = ivec3(flatIdxToCoord(flatIdx));
  vec3 vL = readVelocity(coord + ivec3(-1, 0, 0));
  vec3 vR = readVelocity(coord + ivec3(1, 0, 0));
  vec3 vU = readVelocity(coord + ivec3(0, -1, 0));
  vec3 vD = readVelocity(coord + ivec3(0, 1, 0));
  vec3 vB = readVelocity(coord + ivec3(0, 0, -1));
  vec3 vF = readVelocity(coord + ivec3(0, 0, 1));

  vec3 curl = vec3(
    // left-right
    curl2D(vF.yz, vB.yz, vU.yz, vD.yz),
    // up-down
    curl2D(vL.xz, vR.xz, vF.xz, vB.xz),
    // back-front
    curl2D(vL.xy, vR.xy, vU.xy, vD.xy));

  writeCurl(flatIdx, curl);
}

void advectVelocity(uint flatIdx) {
  if ((uniforms.inputMask & INPUT_BIT_SPACE) != 0)
    return;
  
  vec3 aspectRatioFix = vec3(CELLS_X) / vec3(CELLS_X, CELLS_Y, CELLS_Z);
  
  uvec3 coord = flatIdxToCoord(flatIdx);
  
  uvec2 seed = (coord.xy ^ coord.yz) * uvec2(uniforms.frameCount, uniforms.frameCount + 1);
  vec3 jitterVel1 = 0.0.xxx;//JITTER * (randVec3(seed) - 0.5.xxx);
  vec3 jitterVel2 = JITTER * (randVec3(seed) - 0.5.xxx);

  vec3 v = readVelocity(flatIdx) + jitterVel1;
  vec3 pos = vec3(coord);
  pos -= v * DELTA_TIME * aspectRatioFix;

  vec3 srcVel = VEL_DAMPING * (bilerpVelocity(pos) + jitterVel2);
  
  {
    vec3 curlL = readCurl(ivec3(coord) + ivec3(-1, 0, 0));
    vec3 curlR = readCurl(ivec3(coord) + ivec3(1, 0, 0));
    vec3 curlU = readCurl(ivec3(coord) + ivec3(0, -1, 0));
    vec3 curlD = readCurl(ivec3(coord) + ivec3(0, 1, 0));
    vec3 curlB = readCurl(ivec3(coord) + ivec3(0, 0, -1));
    vec3 curlF = readCurl(ivec3(coord) + ivec3(0, 0, 1));

    vec3 vortConf = 
        vec3(curlR.x - curlL.x, curlU.y - curlD.y, curlB.z - curlF.z);
    float vortConfMag = H * length(vortConf);

    // if (vortConfMag > 0.00001)
      // vortConf *= DELTA_TIME * VORT / vortConfMag;
    
    srcVel += DELTA_TIME * VORT * vortConf;
  }

  writeAdvectedVelocity(flatIdx, srcVel);
}

void computeDivergence(uint flatIdx) {
  ivec3 center = ivec3(flatIdxToCoord(flatIdx));
  vec3 vL = readAdvectedVelocity(center + ivec3(-1, 0, 0));
  vec3 vR = readAdvectedVelocity(center + ivec3(1, 0, 0));
  vec3 vU = readAdvectedVelocity(center + ivec3(0, -1, 0));
  vec3 vD = readAdvectedVelocity(center + ivec3(0, 1, 0));
  vec3 vB = readAdvectedVelocity(center + ivec3(0, 0, -1));
  vec3 vF = readAdvectedVelocity(center + ivec3(0, 0, 1));

  float div = 0.5 / H * (vR.x - vL.x + vD.y - vU.y + vF.z - vB.z);
  writeDivergence(flatIdx, div);
}

void computePressure(int phase, uint flatIdx) {
  uvec3 coord = flatIdxToCoord(flatIdx);
  ivec3 center = ivec3(coord);
  float prevP = readPressure(phase, center);
  float pL = readPressure(phase, center + ivec3(-1, 0, 0));
  float pR = readPressure(phase, center + ivec3(1, 0, 0));
  float pU = readPressure(phase, center + ivec3(0, -1, 0));
  float pD = readPressure(phase, center + ivec3(0, 1, 0));
  float pB = readPressure(phase, center + ivec3(0, 0, -1));
  float pF = readPressure(phase, center + ivec3(0, 0, 1));

  float div = readDivergence(flatIdx);

  uvec2 seed = (coord.xy ^ coord.yz) * uvec2(uniforms.frameCount, uniforms.frameCount + 1);
  float jitter = (rng(seed) - 0.5) * PRESSURE_JITTER * MAX_PRESSURE;
  float p = (pL + pR + pU + pD + pB + pF - div * H * H) / 6.0 + jitter;

  // p = mix(prevP, p, 0.9);

  writePressure(phase, flatIdx, p);
}

void resolveVelocity(uint flatIdx) {
  if ((uniforms.inputMask & INPUT_BIT_SPACE) != 0)
    return;
  
  ivec3 center = ivec3(flatIdxToCoord(flatIdx));
  vec3 v = readAdvectedVelocity(flatIdx);
  float pL = readPressure(0, center + ivec3(-1, 0, 0));
  float pR = readPressure(0, center + ivec3(1, 0, 0));
  float pU = readPressure(0, center + ivec3(0, -1, 0));
  float pD = readPressure(0, center + ivec3(0, 1, 0));
  float pB = readPressure(0, center + ivec3(0, 0, -1));
  float pF = readPressure(0, center + ivec3(0, 0, 1));

  v -= 0.5 / H * vec3(pR - pL, pD - pU, pF - pB);
  
  writeVelocity(flatIdx, v);
}

void advectColor(uint flatIdx) {
  vec3 aspectRatioFix = vec3(CELLS_X) / vec3(CELLS_X, CELLS_Y, CELLS_Z);

  uvec3 coord = flatIdxToCoord(flatIdx);
  vec3 v = readVelocity(flatIdx);
  vec3 pos = vec3(coord);
  pos -= v * DELTA_TIME * aspectRatioFix;

  ExtraFields fields = bilerpFields(pos).fields;
  fields.color.xyz *= vec3(0.998, 0.992, 0.98);
  float a = BUOYANCY * fields.color.r;//length(fields.color.xyz);
  v += vec3(0.0, -a, 0.0);
  // v += 10.0 * vec3(0.0, 1.0, 0.0) * (1.0 - fields.color.r);
  writeVelocity(flatIdx, v);
  
  advectedExtraFields[flatIdx] = fields;
}
