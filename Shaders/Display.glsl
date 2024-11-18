#version 450

#define IS_SHADER
#include "../Include/Shared/CommonStructures.h"

#include <Bindless/GlobalHeap.glsl>

SAMPLER2D(textureHeap);

layout(set = 1, binding = 0) uniform _FlrUniforms{
  FlrUniforms uniforms;
};

layout(push_constant) uniform PushConstant {
  FlrPush push;
};

#ifdef IS_VERTEX_SHADER
layout(location = 0) out vec2 outScreenUV;

void main() {
  vec2 screenPos = vec2((gl_VertexIndex << 1) & 2, gl_VertexIndex & 2);
  outScreenUV = screenPos;
  gl_Position = vec4(screenPos * 2.0f - 1.0f, 0.0f, 1.0f);
}
#endif // IS_VERTEX_SHADER

#ifdef IS_PIXEL_SHADER
layout(location = 0) in vec2 inScreenUV;
layout(location = 0) out vec4 outColor;
void main() {
  if (push.push0 == INVALID_BINDLESS_HANDLE) {
    outColor = vec4(0.6, 0.2, 0.8, 1.0);
    return;
  }

  outColor = texture(textureHeap[push.push0], inScreenUV);
}
#endif // IS_PIXEL_SHADER

