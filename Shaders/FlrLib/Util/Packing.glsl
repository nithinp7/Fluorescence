#ifndef _PACKING_GLSL_
#define _PACKING_GLSL_

uint octEncodeNormal(vec3 n) {
  uint mask = (1 << 15) - 1;
  n.z = sign(n.z);
  n = 0.5 * n + 0.5.xxx;
  n *= vec3(mask, mask, 1.0);
  uvec3 a = uvec3(n) << uvec3(0, 15, 30);
  return a.x | a.y | a.z;
}

vec3 octDecodeNormal(uint o) {
  uint mask = (1 << 15) - 1;
  uvec3 a = (uvec3(o) >> uvec3(0, 15, 30)) & uvec3(mask, mask, 1);
  vec3 n = vec3(a) / vec3(mask, mask, 1) * 2.0 - 1.0.xxx;
  n.z *= sqrt(max(0, 1.0 - dot(n.xy, n.xy)));
  return n;
}

uint packUNormR8(float f) {
  return uint(saturate(f) * 255.0);
}

float unpackUNormR8(uint p) {
  return saturate(float(p & 0xFF) / 255.0);
}

uint packUNormRGBA8(vec4 f) {
  uvec4 u = uvec4(saturate(f) * 0xFF) << uvec4(0, 8, 16, 24);
  return u.x | u.y | u.z | u.w;
}

vec4 unpackUNormRGBA8(uint p) {
  uvec4 u = (uvec4(p) >> uvec4(0, 8, 16, 24)) & 0xFF;
  return saturate(vec4(u) / 255.0);
}

uint packSNormRG16(vec2 f) {
  f = 0.5 * f + 0.5.xx;
  f *= vec2(0xFFFF);
  uvec2 a = uvec2(f) << uvec2(0, 16);
  return a.x | a.y;
}

vec2 unpackSNormRG16(uint u) {
  uvec2 a =  (uvec2(u) >> uvec2(0, 16)) & 0xFFFF;
  return vec2(a) / vec2(0xFFFF) * 2.0 - 1.0.xx;
}

uint or(uvec2 u) { return u.x | u.y; }
uint or(uvec3 u) { return u.x | u.y | u.z; }
uint or(uvec4 u) { return u.x | u.y | u.z | u.w; }
#endif // _PACKING_GLSL_

