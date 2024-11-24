
#include <Misc/Constants.glsl>
#include <Misc/Sampling.glsl>

// IDEAS
/*
- Ring buffer of shape-matching constraints
- Tiles can randomly generate shape-matching constraints on nearby particles
- Old shape-matching constraints get periodically recycled
*/

int getTileIdx(ivec2 coord) {
  coord.x = clamp(coord.x, 0, TILE_COUNT_X - 1);
  coord.y = clamp(coord.y, 0, TILE_COUNT_Y - 1);
  return coord.y * TILE_COUNT_X + coord.x;
}

vec2 getPos(uint i) { return posBuffer[i].pos; }
vec2 getPrevPos(uint i) { return prevPosBuffer[i].pos; }
void setPos(uint i, vec2 p) {  posBuffer[i].pos = p; }
void setPrevPos(uint i, vec2 p) { prevPosBuffer[i].pos = p; }

#ifdef IS_COMP_SHADER

void CS_ClearTiles() {
  ivec2 coord = ivec2(gl_GlobalInvocationID.xy);
  Tile tile;
  tile.head = ~0;
  tile.count = 0;
  tilesBuffer[getTileIdx(coord)] = tile;  
}

void CS_Init() {
  if (globalStateBuffer[0].initialized != 0)
    return;
  
  for (uint i = 0; i < agentCount; ++i) {
    vec2 pos = vec2(wave(1.0, i), wave(2.0, i + 2));
    setPos(i, pos);
    setPrevPos(i,pos);
    agentBuffer[i].next = ~0;
    agentBuffer[i].shape = ~0;
  }

  globalStateBuffer[0].initialized = 1;
}

void CS_TimeStepAgents() {
  uint threadId = uint(gl_GlobalInvocationID.x);
  if (threadId >= agentCount)
    return;

  vec2 pos = getPos(threadId);
  vec2 prevPos = getPrevPos(threadId);

  float damping = 0.5;
  vec2 velocityDt = damping * (pos - prevPos);
  velocityDt.y += GRAVITY * DELTA_TIME;
  prevPos = pos;
  pos += velocityDt;
  
  setPos(threadId, pos);
  setPrevPos(threadId, prevPos);

  agentBuffer[threadId].next = ~0;
}

void CS_MoveAgents() {
  uint threadId = uint(gl_GlobalInvocationID.x);
  if (threadId >= agentCount)
    return;

  vec2 pos = getPos(threadId);

  vec2 tileCoord = pos * vec2(TILE_COUNT_X, TILE_COUNT_Y);
  ivec2 ucoord = ivec2(round(tileCoord - vec2(1.0)));

  float k = 0.9;
  
  for (uint i = 0; i < 4; ++i) {
    ivec2 coord = ucoord + ivec2(i & 1, i >> 1);
    int tileIdx = getTileIdx(coord);
    if (tileIdx < 0)
      continue;
    uint agentIdx = tilesBuffer[tileIdx].head;
    for (int j = 0; j < 20 && agentIdx != ~0; j++) {
      if (agentIdx != threadId) {
        vec2 diff = pos - getPrevPos(agentIdx);
        float dist = length(diff);
        if (dist < 2.0 * RADIUS)
        {
          if (dist < 0.00001)
          {
            pos += k * vec2(2.0 * RADIUS, 0.0) * (agentIdx < threadId ? -1.0 : 1.0);
          } else {
            pos += k * (2.0 * RADIUS - dist) / dist * diff;
          }
        }
      }
      agentIdx = agentBuffer[agentIdx].next;
    }
  }

  pos.x += 1. * (clamp(pos.x, 0.0, 1.0) - pos.x);
  pos.y += 1. * (clamp(pos.y, 0.0, 1.0) - pos.y);

  {
    vec2 diff = pos - uniforms.mouseUv;
    float dist = length(diff);
    if (dist < 0.1 && dist > 0.0001)
    {
      pos += k * (0.1 - dist) / dist * diff;
    }
  }

  setPos(threadId, pos);
}

void CS_CreateShapes() {
  if ((uniforms.inputMask & INPUT_BIT_LEFT_MOUSE) == 0)
    return;
  ivec2 coord = ivec2(gl_GlobalInvocationID.xy);
  Tile tile = tilesBuffer[getTileIdx(coord)];
  if (tile.count < 24)
   return;

  uint shapeSlot = atomicAdd(globalStateBuffer[0].shapeCount, 1);
  shapeSlot = shapeSlot % MAX_SHAPE_COUNT;
  uint count = shapeBuffer[shapeSlot].count;
  for (uint i = 0; i < count; i++) {
    uint agentIdx = shapeBuffer[shapeSlot].agents[i];
    agentBuffer[agentIdx].shape = ~0;
  }

  count = 0;
  uint agentIdx = tile.head;
  for (uint i = 0; i < MAX_AGENTS_PER_SHAPE && agentIdx != ~0; i++) {
    if (agentBuffer[agentIdx].shape == ~0) {
      agentBuffer[agentIdx].shape = shapeSlot;
      shapeBuffer[shapeSlot].agents[count++] = agentIdx; 
    }
    agentIdx = agentBuffer[agentIdx].next;
  }

  shapeBuffer[shapeSlot].count = count;
}

void CS_WriteAgentsToTiles() {
  uint threadId = uint(gl_GlobalInvocationID.x);
  if (threadId >= agentCount)
    return;

  vec2 pos = getPos(threadId);
  int tileIdx = getTileIdx(ivec2(pos * vec2(TILE_COUNT_X, TILE_COUNT_Y)));
  uint prevElem = atomicExchange(tilesBuffer[tileIdx].head, threadId);
  atomicAdd(tilesBuffer[tileIdx].count, 1);
  agentBuffer[threadId].next = prevElem;
}

void CS_SolveShapes() {
  uint shapeIdx = uint(gl_GlobalInvocationID.x);
  uint count = shapeBuffer[shapeIdx].count;
  if (count == 0)
    return;

  vec2 avgPos = vec2(0.0);
  for (uint i = 0; i < count; i++) {
    uint agentIdx = shapeBuffer[shapeIdx].agents[i];
    avgPos += getPos(agentIdx) / count;
  }

  float dtheta = 2.0 * PI / count;

  for (uint i = 0; i < count; i++) {
    uint agentIdx = shapeBuffer[shapeIdx].agents[i];
    
    float theta = i * dtheta;
    float c = cos(theta);
    float s = sin(theta);
    
    float k = 0.1 + 0.7 * wave(1.3, 3. * shapeIdx);
    vec2 curPos = getPos(agentIdx);
    // vec2 targetPos = avgPos + 0.025 * vec2(c, s) * (0.5 * wave(0.25, i * shapeIdx) + wave(0.1, shapeIdx));
    vec2 targetPos = avgPos + 0.025 * vec2(c, s) * (0.5 * sin(i * shapeIdx) + cos(shapeIdx));
    // vec2 targetPos = avgPos + 0.02 * vec2(c, s);
    // targetPos += vec2(0.0001 * sin(1.0 * uniforms.time), -0.001 * wave(3., 2.));
    vec2 pos = mix(curPos, targetPos, k);
    setPos(agentIdx, pos);
  }
}

#endif // IS_COMP_SHADER

////////////////////////// VERTEX SHADER //////////////////////////

#ifdef IS_VERTEX_SHADER
layout(location = 0) out vec2 outScreenUv;
layout(location = 1) out vec4 outColor;

void VS_AgentSimDisplay() {
  outScreenUv = VS_FullScreen();
  outColor = vec4(1.0);
}

void VS_Circle() {
  uint agentIdx = uint(gl_InstanceIndex);

  uint shapeIdx = agentBuffer[agentIdx].shape;

  uint i = gl_VertexIndex;
  float dtheta = 2.0 * PI * 3.0 / CIRCLE_VERTS;

  vec2 pos = getPos(agentIdx);
  pos *= vec2(1.0 - 2.0 * PADDING);
  pos += vec2(PADDING);

  if ((i % 3) < 2) {
    uint tidx = i / 3;
    float theta = (tidx + (i % 3)) * dtheta;
    float c = cos(theta);
    float s = sin(theta);
    pos += 0.5 * RADIUS * vec2(c, s);
  }

  outScreenUv = pos;

  uvec2 seed = uvec2(shapeIdx, shapeIdx + 1);
  if (shapeIdx == ~0) {
    outColor = vec4(0.0);//vec4(1.0, 0.0, 0.0, 1.0);
    outColor = vec4(0.01, 0.0, 0.0, 1.0);
  } else { 
    outColor = vec4(randVec3(seed), 1.0);
  }

  gl_Position = vec4(pos * 2.0f - 1.0f, 0.0f, 1.0f);
}

#endif // IS_VERTEX_SHADER

////////////////////////// PIXEL SHADER //////////////////////////

#ifdef IS_PIXEL_SHADER
layout(location = 0) in vec2 inScreenUv;
layout(location = 1) in vec4 inColor;

layout(location = 0) out vec4 outColor;

void PS_Circle() {
  outColor = inColor;//vec4(1.0, 0.0, 0.0, 1.0);
}

void PS_UvTest() {
  outColor = vec4(0.0, 0.0, 0.0, 1.0);  
  // return;
  // outColor = vec4(inScreenUv, wave(0.1, 0.0), 1.0);
  
  // int tileIdx = getTileIdx(ivec2(inScreenUv * vec2(TILE_COUNT_X, TILE_COUNT_Y)));
  // uint count = tilesBuffer[tileIdx].count;

  vec2 tileCoord = inScreenUv * vec2(TILE_COUNT_X, TILE_COUNT_Y);
  ivec2 ucoord = ivec2(round(tileCoord - vec2(1.0)));

  // if (count > 0) 
  {
    vec3 blend = vec3(0.0);
    float wsum = 4.0;


    for (uint i = 0; i < 4; ++i) {
      ivec2 coord = ucoord + ivec2(i & 1, i >> 1);
      int tileIdx = getTileIdx(coord);
      if (tileIdx < 0)
        continue;

      uint count = tilesBuffer[tileIdx].count;
      if (count == 0)
        continue;

      uint agentIdx = tilesBuffer[tileIdx].head;
      for (int j = 0; j < count; j++) {
        uint shapeIdx = agentBuffer[agentIdx].shape;
        uvec2 seed = uvec2(shapeIdx, shapeIdx + 1);
        vec2 diff = inScreenUv - getPos(agentIdx);
        float emissive = 0.00001 * wave(1.5, rngu(seed));
        float w = emissive / dot(diff, diff);
        wsum += w;
        // vec3 color = shapeIdx == ~0 ? vec3(1.0, 0.0, 0.0) : randVec3(seed);
        vec3 color = shapeIdx == ~0 ? vec3(0.0) : randVec3(seed);
        blend += w * color;
        agentIdx = agentBuffer[agentIdx].next;
      }
      outColor = vec4(blend / wsum, 1.0);
    }
  }
}
#endif // IS_PIXEL_SHADER

