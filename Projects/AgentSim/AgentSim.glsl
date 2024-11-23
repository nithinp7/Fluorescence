
#include <Misc/Constants.glsl>

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
  globalStateBuffer[0].shapeCount = 
      globalStateBuffer[0].shapeCount % MAX_SHAPE_COUNT;
  if (globalStateBuffer[0].initialized != 0)
    return;
  
  for (uint i = 0; i < agentCount; ++i) {
    vec2 pos = vec2(wave(1.0, i), wave(2.0, i + 2));
    setPos(i, pos);
    setPrevPos(i,pos);
  }

  globalStateBuffer[0].initialized = 1;
}

void CS_TimeStepAgents() {
  uint threadId = uint(gl_GlobalInvocationID.x);
  if (threadId >= agentCount)
    return;

  vec2 pos = getPos(threadId);
  vec2 prevPos = getPrevPos(threadId);

  float damping = 0.9;
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

  float k = 0.0;
  
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

  pos.x += k * (clamp(pos.x, 0.0, 1.0) - pos.x);
  pos.y += k * (clamp(pos.y, 0.0, 1.0) - pos.y);

  {
    vec2 diff = pos - uniforms.mouseUv;
    float dist = length(diff);
    if (dist < 4.0 * RADIUS && dist > 0.0001)
    {
      pos += k * (4.0 *  RADIUS - dist) / dist * diff;
    }
  }

  setPos(threadId, pos);
}

void CS_CreateShapes() {
  ivec2 coord = ivec2(gl_GlobalInvocationID.xy);
  Tile tile = tilesBuffer[getTileIdx(coord)];
  if (tile.count < 10)
   return;

  uint shapeSlot = atomicAdd(globalStateBuffer[0].shapeCount, 1);
  shapeSlot = shapeSlot % MAX_SHAPE_COUNT;
  shapeBuffer[shapeSlot].count = 0;
  uint agentIdx = tile.head;
  uint count = 0;
  for (; count < MAX_AGENTS_PER_SHAPE && agentIdx != ~0; count++) {
    shapeBuffer[shapeSlot].agents[count] = agentIdx; 
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
  if (shapeIdx >= globalStateBuffer[0].shapeCount)
    return;

  uint count = shapeBuffer[shapeIdx].count;
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
    
    float k = 0.8 * wave(1.0, 3.);
    vec2 curPos = getPos(agentIdx);
    vec2 targetPos = avgPos + 0.05 * vec2(c, s);
    setPos(agentIdx, mix(curPos, targetPos, k));
  }
}

#endif // IS_COMP_SHADER

////////////////////////// VERTEX SHADER //////////////////////////

#ifdef IS_VERTEX_SHADER
layout(location = 0) out vec2 outScreenUv;

void VS_AgentSimDisplay() {
  outScreenUv = VS_FullScreen();
}

void VS_Circle() {
  uint agentIdx = uint(gl_InstanceIndex);

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
    pos += RADIUS * vec2(c, s);
  }

  outScreenUv = pos;
  gl_Position = vec4(pos * 2.0f - 1.0f, 0.0f, 1.0f);
}

#endif // IS_VERTEX_SHADER

////////////////////////// PIXEL SHADER //////////////////////////

#ifdef IS_PIXEL_SHADER
layout(location = 0) in vec2 inScreenUv;
layout(location = 0) out vec4 outColor;

void PS_Circle() {
  outColor = vec4(1.0, 0.0, 0.0, 1.0);
}

void PS_UvTest() {
  outColor = vec4(inScreenUv, wave(0.1, 0.0), 1.0);
  int tileIdx = getTileIdx(ivec2(inScreenUv * vec2(TILE_COUNT_X, TILE_COUNT_Y)));
  if (tileIdx >= 0 && tilesBuffer[tileIdx].count > 0) {
//    outColor = vec4(1.0, 0.0, 0.0, 1.0);
  }
}
#endif // IS_PIXEL_SHADER

