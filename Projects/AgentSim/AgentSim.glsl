
#ifdef IS_COMP_SHADER

void CS_MoveAgents() {
    
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
}
#endif // IS_PIXEL_SHADER

