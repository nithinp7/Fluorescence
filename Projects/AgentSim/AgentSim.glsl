
#ifdef IS_COMP_SHADER

void CS_MoveAgents() {
  uint threadId = uint(gl_GlobalInvocationID.x);
  if (threadId >= agentCount)
    return;

  float t = uniforms.time + threadId * 0.1f;
  float c = cos(t);
  float s = sin(t);

  vec2 uv = 0.3 * vec2(c, s) + 0.5;

  Agent agent;
  agent.position = vec3(uv, 0.0);
  agent.radius = 0.7 + 0.02 * sin(uniforms.time * 3 + 2 * threadId);
  
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
  outColor = vec4(inScreenUv, fract(uniforms.time), 1.0);

  float minDist = 1.0;

  for (uint i = 0; i < 25; ++i)
  {
    Agent agent = agentBuffer[i];
    float dist = length(agent.position.xy - inScreenUv);
    minDist = min(dist, minDist);
  }

  if (minDist < 1.0)
    outColor = vec4(minDist, minDist * 0.2, 0.8, 1.0);
}
#endif // IS_PIXEL_SHADER

