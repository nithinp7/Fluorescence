#version 460 core

#include <Fluorescence.glsl>

////////////////////////// COMMON SECTION //////////////////////////
struct Agent {
  vec3 position;
  float radius;
};

#include "AgentSim.gen.glsl"

//layout(push_constant) PushConstants {
//  uint agentBuffer
//}
////////////////////////// COMPUTE SHADERS //////////////////////////

#ifdef IS_COMP_SHADER
layout(local_size_x = 32) in;
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

