
#ifdef IS_COMP_SHADER


void CS_TimeStepAgents() {
  uint threadId = uint(gl_GlobalInvocationID.x);
  if (threadId >= agentCount)
    return;

  Agent agent = agentBuffer[threadId];

  vec2 velocityDt = agent.position - agent.prevPosition;
  velocityDt.y += 0.001 * GRAVITY * DELTA_TIME;

  agent.position += velocityDt;

#if 0
  // reset
  agent.position = vec2(wave(1.0, threadId), wave(2.0, threadId + 2));
  agent.prevPosition = agent.position;
#endif

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
      vec2 diff = agent.position - agentBuffer[threadId].prevPosition;
      float dist = length(diff);
      if (dist < RADIUS && dist > 0.0001)
      {
        float k = 0.5;
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

  for (uint i = 0; i < 25; ++i)
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
}
#endif // IS_PIXEL_SHADER

