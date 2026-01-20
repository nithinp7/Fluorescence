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

float phaseFunction(float cosTheta, float g) {
  float g2 = g * g;
  return  
      3.0 * (1.0 - g2) * (1.0 + cosTheta * cosTheta) / 
      (8 * PI * (2.0 + g2) * pow(1.0 + g2 - 2.0 * g * cosTheta, 1.5));
}

float phaseFunctionRayleigh(float cosTheta) {
  return 3.0 * (1.0 + cosTheta * cosTheta) / (16.0 * PI);
}

vec3 beersLaw(vec3 depth) { return exp(-depth); }
vec3 powder(vec3 depth) { return 1.0.xxx - exp(-depth * depth); }

vec3 computeDir(vec2 uv) {
	vec2 d = uv * 2.0 - 1.0;

	vec4 target = camera.inverseProjection * vec4(d, 1.0.xx);
	return (camera.inverseView * vec4(normalize(target.xyz), 0)).xyz;
}

vec3 getCameraPos() {
  return camera.inverseView[3].xyz;
}

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

vec4 worldToShadowSpace(vec3 worldPos) {
  vec3 shadowPos = worldPos - shadowCamera[0][3].xyz;
  return vec4(transpose(mat3(shadowCamera[0])) * shadowPos, 1.0);
}

#ifdef IS_COMP_SHADER
void CS_UpdateShadowCamera() {
  float gridWidth = GRID_LEN * GRID_SPACING;
  
  vec3 up = vec3(0.0, 1.0, 0.0);
  
  vec3 viewDir = -getSunDir();
  vec3 refA = normalize(cross(viewDir, up));
  vec3 refB = cross(refA, viewDir);

  float r = 0.7 * gridWidth;
  vec3 focusPos = vec3(0.5 * gridWidth, 0.0, 0.5 * gridWidth) - r * viewDir;

  mat4 orthoProj;
  orthoProj[0] = vec4(refA / r, 0.0);
  orthoProj[1] = vec4(-refB / r, 0.0);
  orthoProj[2] = vec4(0.5 * viewDir / r, 0.0);
  orthoProj[3] = vec4(focusPos, 1.0);
  shadowCamera[0] = orthoProj; 
}
#endif // IS_COMP_SHADER

vec3 linearToSdr(vec3 color) {
  return vec3(1.0) - exp(-color * EXPOSURE);
}

float sampleOcclusionThickness(vec3 p) {
  vec4 shadowPos = worldToShadowSpace(p);
  vec2 shadowUv = shadowPos.xy * 0.5 + 0.5.xx;
  float shadowDepthSample = texture(shadowMapTexture, shadowUv).r;
  bool bValidShadowSample = clamp(shadowUv, 0.0.xx, 1.0.xx) == shadowUv && shadowDepthSample < 1.0;
  if (!bValidShadowSample)
    return 0.0;
  return abs(shadowPos.z - shadowDepthSample);
}

vec3 computeSurfaceLighting(inout uvec2 seed, Material mat, vec3 pos, vec3 normal, vec3 dir) {
  vec3 outColor = 0.0.xxx;

  {
    vec3 wi = getSunDir();
    vec3 Li = sampleSky(wi);
    
    float cs = dot(wi, dir);
    vec3 phasedLight = Li * phaseFunction(cs, G) ;// * mat.diffuse;
    vec3 throughput = 1.0.xxx;
    // hack powder approx, should try to do this during extinction ??
    // throughput *= clamp(1.5 - abs(dot(wi, normal)), 0.0, 1.0);
    vec3 spos = pos;
    vec3 rmdepth = 0.0.xxx;
    float stepSize = GRID_SPACING * STEP_SIZE;
    spos += 2.0 * JITTER * rng(seed) * stepSize * dir;
    for (int i = 0; i<STEP_COUNT; i++) {
      float occlusionThickness = sampleOcclusionThickness(spos);
      float shadowBias = 0.001;
      vec3 lightThroughput = throughput;
      if (occlusionThickness <= shadowBias) {
        // outColor = mat.diffuse * max(dot(wi, normal), 0.0) * Li;
        // throughput = 1.0.xxx;// exp(-SCATTER.rgb * 100.0 * DENSITY * shadowBias);
      } else 
      {
        lightThroughput *= exp(-SCATTER.rgb * 100.0 * DENSITY * occlusionThickness);
      }
      outColor += phasedLight * lightThroughput * mix(1.0.xxx, powder(rmdepth), POWDER);
      vec3 depthStep = SCATTER.rgb * 100.0 * DENSITY * stepSize;
      throughput *= exp(-depthStep);
      rmdepth += depthStep;
      // spos += -normal * STEP_SIZE;
      spos += dir * stepSize;
    }
  }

  {
    vec3 diffLi = sampleSky(normal);
    outColor += 0.1 * mat.diffuse * diffLi / PI;
  }

  {
    vec3 specLi = sampleSky(reflect(dir, normal));
    vec3 F = fresnelSchlick(abs(dot(dir, normal)), mat.specular, mat.roughness);
    outColor += F * specLi;
  }
  
  return outColor;
}
#endif // _LIGHTING_GLSL_