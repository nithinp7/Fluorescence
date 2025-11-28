#ifndef _LIGHTING_GLSL_
#define _LIGHTING_GLSL_

struct Material {
  vec3 diffuse;
  float roughness;
  vec3 emissive;
  float metallic;
  vec3 specular;
  float padding;
};

#include <FlrLib/PBR/BRDF.glsl>

vec3 sampleEnv(vec3 dir) {
  float intensity = 1.0;
  float c = 5.0;
  vec3 n = 0.5 * normalize(dir) + 0.5.xxx;
  if (BACKGROUND == 0) {
    return intensity * round(n * c) / c;
  } else if (BACKGROUND == 1) {
    return intensity * round(fract(n * c));
  } else if (BACKGROUND == 2) {
    return intensity * round(n);
  } else {
    float f = n.x + n.y + n.z;
    return intensity * max(round(fract(f * c)), 0.2).xxx;
  }
}

vec3 directLighting(vec3 pos, vec3 normal, int lightIdx) {
  PointLight light = pointLights[lightIdx];

  vec3 diff = light.pos - pos;
  float dist2 = dot(diff, diff);
  float rcos = dot(normal, diff);
  if (rcos < 0.0) return 0.0.xxx;
  float dist = sqrt(dist2);
  float cs = rcos/dist;

  return light.light * cs / light.falloff * dist2;
}

void initLights() {
  uvec2 seed = uvec2(23, 27);
  float dtheta = 2.0 * PI / POINT_LIGHT_COUNT;
  for (int i = 0; i < POINT_LIGHT_COUNT; i++) {
    PointLight light;
    float theta = i*dtheta;
    light.pos = 5.0 * vec3(cos(theta), 1.0, sin(theta));
    light.light = 10.0 * (vec3(1.0, 0.85, 0.9) + 0.1 * (randVec3(seed) - 0.5));
    light.falloff = FALLOFF;
    pointLights[i] = light;
  }
}

vec3 linearToSdr(vec3 color) {
  float EXPOSURE = 0.1;
  return vec3(1.0) - exp(-color * EXPOSURE);
}

vec3 computeSurfaceLighting(
    inout uvec2 seed, vec3 pos, vec3 normal, vec3 dir) {
  Material mat;
  mat.diffuse = vec3(0.8, 0.35, 0.75);
  mat.roughness = 0.1;
  mat.emissive = 0.0.xxx;
  mat.metallic = 0.0;
  mat.specular = 0.03.xxx;

  vec3 outColor = 0.0.xxx;

  for (int i = 0; i < POINT_LIGHT_COUNT; i++) {
    outColor += mat.diffuse * directLighting(pos, normal, i);
  }

  {
    vec3 diffLi = sampleEnv(normal);
    outColor += 0.1 * mat.diffuse * diffLi / PI;
  }

  {
    vec3 specLi = sampleEnv(reflect(dir, normal));
    vec3 F = fresnelSchlick(abs(dot(-dir, normal)), mat.specular, mat.roughness);
    outColor += F * specLi;
  }
  
  return outColor;
}

#endif // _LIGHTING_GLSL_