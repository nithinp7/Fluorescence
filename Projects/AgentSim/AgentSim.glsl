
uint getTileIdx(uvec2 coord) {
  return coord.y * TILE_COUNT_X + coord.x;
}

uint getTileIdx(vec2 uv) {
  uvec2 coord = uvec2(round(uv * vec2(TILE_COUNT_X, TILE_COUNT_Y)));
  coord.x = clamp(coord.x, 0, TILE_COUNT_X - 1);
  coord.y = clamp(coord.y, 0, TILE_COUNT_Y - 1);
  return getTileIdx(coord);
} 

#ifdef IS_COMP_SHADER

void CS_ClearTiles() {
  uvec2 coord = uvec2(gl_GlobalInvocationID.xy);
  Tile tile;
  tile.head = ~0;
  tile.count = 0;
  tilesBuffer[getTileIdx(coord)] = tile;  
}

void CS_Init() {
  if (globalStateBuffer[0].initialized != 0)
    return;
  
  for (uint i = 0; i < agentCount; ++i) {
    Agent agent;
    agent.position = vec2(wave(1.0, i), wave(2.0, i + 2));
    agent.prevPosition = agent.position;
    agentBuffer[i] = agent;
  }

  globalStateBuffer[0].initialized = 1;
}

void CS_TimeStepAgents() {
  uint threadId = uint(gl_GlobalInvocationID.x);
  if (threadId >= agentCount)
    return;

  Agent agent = agentBuffer[threadId];

  float damping = 0.5;
  vec2 velocityDt = damping * (agent.position - agent.prevPosition);
  velocityDt.y += GRAVITY * DELTA_TIME;
  agent.prevPosition = agent.position;
  agent.position += velocityDt;
  agent.next = ~0;
  agentBuffer[threadId] = agent;
}

void CS_MoveAgents() {
  uint threadId = uint(gl_GlobalInvocationID.x);
  if (threadId >= agentCount)
    return;

  Agent agent = agentBuffer[threadId];

  agent.position.x = clamp(agent.position.x, 0.0, 1.0);
  agent.position.y = clamp(agent.position.y, 0.0, 1.0);

#if 1
  for (int i = 0; i < agentCount; i++) {
    if (i != threadId) {
      vec2 diff = agent.position - agentBuffer[i].prevPosition;
      float dist = length(diff);
      if (dist < RADIUS && dist > 0.0001)
      {
        float k = 0.9;
        agent.position -= k * (RADIUS - dist) / dist * diff;
      }
    }
  }
  {
    vec2 diff = agent.position - uniforms.mouseUv;
    float dist = length(diff);
    if (dist < 2.0 * RADIUS && dist > 0.0001)
    {
      float k = 0.5;
      agent.position -= k * (RADIUS - dist) / dist * diff;
    }
  }
#endif

  agent.radius = 0.7 + 0.02 * wave(3, 2 * threadId);
  
  agentBuffer[threadId] = agent;
}


void CS_WriteAgentsToTiles() {
  uint threadId = uint(gl_GlobalInvocationID.x);
  if (threadId >= agentCount)
    return;

  vec2 pos = agentBuffer[threadId].position;
  uint tileIdx = getTileIdx(pos);
  uint prevElem = atomicExchange(tilesBuffer[tileIdx].head, threadId);
  atomicAdd(tilesBuffer[tileIdx].count, 1);
  agentBuffer[threadId].next = prevElem;
}


#endif // IS_COMP_SHADER

////////////////////////// VERTEX SHADER //////////////////////////

#ifdef IS_VERTEX_SHADER
layout(location = 0) out vec2 outScreenUv;

void VS_AgentSimDisplay() {
  outScreenUv = VS_FullScreen();
}
#endif // IS_VERTEX_SHADER

////////////////////////// PIXEL SHADER //////////////////////////

#ifdef IS_PIXEL_SHADER
layout(location = 0) in vec2 inScreenUv;
layout(location = 0) out vec4 outColor;

void PS_UvTest() {
  outColor = vec4(inScreenUv, wave(0.1, 0.0), 1.0);

  float minDist = 1.0;

  for (uint i = 0; i < agentCount; ++i)
  {
    Agent agent = agentBuffer[i];
    float dist = length(agent.position.xy - inScreenUv);
    minDist = min(dist, minDist);
  }

  {
    float dist = length(uniforms.mouseUv - inScreenUv);
    if (dist < 2.0 * RADIUS)
    {
      outColor = vec4(0.8, 0.1, 0.1, 1.0);
      return;
    }
  }

  if (minDist < RADIUS)
    outColor = vec4(minDist, minDist * 0.2, 0.8, 1.0);

    
  uint tileIdx = getTileIdx(inScreenUv);
  Tile tile = tilesBuffer[tileIdx];
  if (tile.count > 0)
    outColor.x += 0.5;
}

void PS_Tiles() {
  uint tileIdx = getTileIdx(inScreenUv);
  Tile tile = tilesBuffer[tileIdx];
  outColor = vec4(tile.count > 0 ? 1.0 : 0.0, 0.0, 0.0, 1.0);
}
#endif // IS_PIXEL_SHADER

