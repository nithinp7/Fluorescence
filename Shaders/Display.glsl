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


float time;

float wave(float a, float b) {
  return 0.5 * sin(a * time + b) + 0.5;
}

float wave(float a, float b, float bottom, float top) {
  float center = 0.5 * (bottom + top);
  return 0.5 * (top - bottom) * sin(a * time + b) + center;
}

void spinnySpiral()
{
  time = uniforms.time + 5000;
  
  vec2 d = 2.0 * (inScreenUV - 0.5.xx);

  float theta = atan(d.y, d.x);// +wave(3.0, 0.0);
  float sides = 9.0;// wave(4.0, 30., 5., 15.);
  d *= wave(1.0, sides * theta, 0.9, 1.25) + wave(5., 10. * theta, -0.1, 0.1);
  //d *= 0.5 * wave(10.0, 10.) + 0.5;
  float s = 0.1 * length(d) * wave(0.25, 0., 0.5, 1.5);// *length(d), 0.);

  float f = wave(0.1 * s, 0.0, -1.0, 1.0);
  
  float k = wave(0.5, 1.0, 0.0, 0.1);
  float g = k;// wave(.05 * k * theta, 1);

  vec3 palette0 = vec3(0.5, 0.2, 0.4); // *wave(1. * s, 2.0);
  vec3 palette1 = vec3(0.8, 0.3, 0.1); // *wave(0.1 * d.y, 3.0);
  vec3 palette2 = vec3(0.3, 0.2, 0.93); // *wave(0.1 * d.x, 15.);
  vec3 baseColor = vec3(0.0);//  vec3(0.005, 0.001, 0.01);

  vec3 color = mix(mix(palette0, palette1, f), palette2, g);
  //color = max(color, baseColor);
  //color = normalize(color);

#if 0
  if (inScreenUV.y < 0.333) {
    color = palette0;
  } else if (inScreenUV.y < 0.666) {
    color = palette1;
  }
  else {
    color = palette2;
  }
#endif

  //color = color / (1.0 + color);
  outColor = vec4(color, 1.0);
}

void PS_Default() {
  spinnySpiral();
}

#endif // IS_PIXEL_SHADER

