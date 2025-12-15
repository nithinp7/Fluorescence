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

vec2 dirToPolar(vec3 dir) {
    float yaw = atan(dir.z, dir.x) - PI;
    float pitch = -atan(dir.y, length(dir.xz));
    return vec2(0.5 * yaw, pitch) / PI + 0.5;
}

vec3 polarToDir(vec2 p) {
  p -= 0.5.xx;
  p *= PI * vec2(2.0, -1.0);
  p.x += PI;
  vec3 dir;
  dir.y = sin(p.y);
  float dirxzmag = cos(p.y);
  dir.x = cos(p.x) * dirxzmag;
  dir.z = sin(p.x) * dirxzmag;
  return dir;
}

vec3 getSunDir() {
  return normalize(polarToDir(vec2(SUN_ROT, SUN_ELEV)));
}

vec3 sampleSky(vec3 dir) {
  vec3 horizonColor = mix(SKY_COLOR.rgb, 1.0.xxx, HORIZON_WHITENESS);
  vec3 color = SKY_INT * mix(horizonColor, SKY_COLOR.rgb, pow(abs(dir.y), HORIZON_WHITENESS_FALLOFF));
  vec3 sunDir = getSunDir();
  float cutoff = 0.001;
  float sunInt = SUN_INT * max((dot(sunDir, dir) - 1.0 + cutoff)/cutoff, 0.0);
  color += sunInt * vec3(0.8, 0.78, 0.3);
  color *= pow(min(1.0 + dir.y, 1.0), 8.0);
  return color;
}

vec3 linearToSdr(vec3 color) {
  return vec3(1.0) - exp(-color * EXPOSURE);
}

vec3 computeSurfaceLighting(Material mat, vec3 pos, vec3 normal, vec3 dir) {
  vec3 outColor = 0.0.xxx;

  {
    vec3 wi = getSunDir();
    vec3 Li = sampleSky(wi);
    outColor = mat.diffuse * max(dot(wi, normal), 0.0) * Li;
  }

  {
    vec3 diffLi = sampleSky(normal);
    outColor += 0.1 * mat.diffuse * diffLi / PI;
  }

  {
    vec3 specLi = sampleSky(reflect(dir, normal));
    vec3 F = fresnelSchlick(abs(dot(-dir, normal)), mat.specular, mat.roughness);
    outColor += F * specLi;
  }
  
  return outColor;
}

#endif // _LIGHTING_GLSL_