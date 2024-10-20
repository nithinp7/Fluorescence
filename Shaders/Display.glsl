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

void spinnySpiral()
{
  vec2 d = 2.0 * (inScreenUV - 0.5.xx);
  float s = sin(uniforms.time + length(d));
  float theta = atan(d.y, d.x) + cos(uniforms.time * .3);

  float f = cos(0.01 * s * length(d) * uniforms.time);
  float g = cos(0.01 * theta * uniforms.time);

  vec3 palette0 = vec3(0.2, 0.2, 0.4) * s;
  vec3 palette1 = vec3(0.8, 0.3, 0.13);
  vec3 palette2 = vec3(0.3, 0.2, 0.93);

  vec3 color = mix(palette0, palette1, f) + g * palette2;
  //color = normalize(color);

  //color = color / (1.0 + color);
  outColor = vec4(color, 1.0);
}

void PS_Default() {
  spinnySpiral();
}

#endif // IS_PIXEL_SHADER

