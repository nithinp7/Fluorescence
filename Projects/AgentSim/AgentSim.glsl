#include <Fluorescence.glsl>

////////////////////////// COMMON SECTION //////////////////////////
struct Agent {
  vec3 position;
  float radius;
};

//layout(push_constant) PushConstants {
//  uint agentBuffer
//}
////////////////////////// COMPUTE SHADERS //////////////////////////

#ifdef IS_COMP_SHADER

DECL_BUFFER(RW, Agent, agentBuffer);

void CS_MoveAgents() {
  //BINDLESS(agentBuffer, )
}

#endif // IS_COMP_SHADER

////////////////////////// VERTEX SHADER //////////////////////////

#ifdef IS_VERTEX_SHADER
layout(location = 0) out vec2 outScreenUv;

DECL_BUFFER(R, Agent, agentBuffer);

void main() {
  outScreenUv = VS_FullScreen();
}
#endif // IS_VERTEX_SHADER

////////////////////////// PIXEL SHADER //////////////////////////

#ifdef IS_PIXEL_SHADER
layout(location = 0) in vec2 inScreenUv;
layout(location = 0) out vec4 outColor;

DECL_BUFFER(R, Agent, agentBuffer);

void main() {
  outColor = vec4(inScreenUv, fract(time), 1.0);
}
#endif // IS_PIXEL_SHADER

