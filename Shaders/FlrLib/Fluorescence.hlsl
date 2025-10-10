#define IS_SHADER
#define IS_HLSL_SHADER
#include <../Include/Fluorescence/Shared/CommonStructures.h>
// TODO - these two includes are not actually glsl-specific, change file name?
#include <Misc/Input.glsl> 
#include <Misc/Constants.glsl>
// #include <Bindless/GlobalHeap.glsl>


[[vk::binding(0, 1)]] cbuffer _FlrUniforms {
  FlrUniforms uniforms;
};

[[vk::push_constant]] cbuffer _PushConstants {
  uint push0;
  uint push1;
  uint push2;
  uint push3;
};

#if 0
// TODO...
#ifdef IS_VERTEX_SHADER

vec2 VS_FullScreen() {
  vec2 screenPos = vec2(gl_VertexIndex & 2, (gl_VertexIndex << 1) & 2);
  gl_Position = vec4(screenPos * 2.0f - 1.0f, 0.0f, 1.0f);
  return screenPos;
}

vec2 VS_Square(uint vertexIdx, vec2 center, vec2 halfDims) {
  vec2 pos;
  if (vertexIdx == 0)
    pos = vec2(-1.0, -1.0);
  else if (vertexIdx == 1) 
    pos = vec2(1.0, 1.0);
  else if (vertexIdx == 2)
    pos = vec2(-1.0, 1.0);
  else if (vertexIdx == 3) 
    pos = vec2(-1.0, -1.0);
  else if (vertexIdx == 4)
    pos = vec2(1.0, -1.0);
  else
    pos = vec2(1.0, 1.0);

  return center + pos * halfDims;
}

vec2 VS_Circle(uint vertexIdx, vec2 pos, float radius, uint circleVerts) {
  float dtheta = 2.0 * PI * 3.0 / circleVerts;

  if ((vertexIdx % 3) < 2) {
    uint tidx = vertexIdx / 3;
    float theta = (tidx + (vertexIdx % 3)) * dtheta;
    float c = cos(theta);
    float s = -sin(theta);
    pos += radius * vec2(c, s);
  }

  return pos;
}

#endif // IS_VERTEX_SHADER
#endif // ...

float wave(float a, float b) {
  return 0.5 * sin(a * uniforms.time + b) + 0.5;
}

float wave(float a, float b, float bottom, float top) {
  float center = 0.5 * (bottom + top);
  return 0.5 * (top - bottom) * sin(a * uniforms.time + b) + center;
}

double wave(double a, double b) {
  return wave(float(a), float(b));
}

double wave(double a, double b, double bottom, double top) {
  return wave(float(a), float(b), float(bottom), float(top));
}
