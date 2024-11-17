#define IS_SHADER
#include <../Include/Shared/CommonStructures.h>

#include <Bindless/GlobalHeap.glsl>

UNIFORM_BUFFER(_uniformsBuffer, _FlrUniforms{
  FlrUniforms u;
});
#define uniforms _uniformsBuffer[0].u

#ifdef IS_VERTEX_SHADER

vec2 VS_FullScreen() {
  vec2 screenPos = vec2((gl_VertexIndex << 1) & 2, gl_VertexIndex & 2);
  gl_Position = vec4(screenPos * 2.0f - 1.0f, 0.0f, 1.0f);
  return screenPos;
}

#endif // IS_VERTEX_SHADER

float wave(float a, float b) {
  return 0.5 * sin(a * uniforms.time + b) + 0.5;
}

float wave(float a, float b, float bottom, float top) {
  float center = 0.5 * (bottom + top);
  return 0.5 * (top - bottom) * sin(a * uniforms.time + b) + center;
}
