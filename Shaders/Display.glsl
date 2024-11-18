#version 450

#define IS_SHADER
#include "../Include/Shared/CommonStructures.h"

#include <Bindless/GlobalHeap.glsl>

UNIFORM_BUFFER(_uniformsBuffer, _FlrUniforms{
  FlrUniforms u;
});
#define uniforms _uniformsBuffer[0].u

#ifdef IS_VERTEX_SHADER
layout(location = 0) out vec2 outScreenUV;

void VS_FullScreen() {
  vec2 screenPos = vec2((gl_VertexIndex << 1) & 2, gl_VertexIndex & 2);
  outScreenUV = screenPos;
  gl_Position = vec4(screenPos * 2.0f - 1.0f, 0.0f, 1.0f);
}
#endif // IS_VERTEX_SHADER

#ifdef IS_PIXEL_SHADER
layout(location = 0) in vec2 inScreenUV;

layout(location = 0) out vec4 outColor;



#endif // IS_PIXEL_SHADER

