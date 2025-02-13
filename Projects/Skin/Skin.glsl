
#include <Misc/Sampling.glsl>

vec3 computeDir(vec2 uv) {
	vec2 d = uv * 2.0 - 1.0;

	vec4 target = camera.inverseProjection * vec4(d, 1.0.xx);
	return (camera.inverseView * vec4(normalize(target.xyz), 0)).xyz;
}

vec3 sampleEnv(vec3 dir) {
  float c = 5.0;
  vec3 n = 0.5 * normalize(dir) + 0.5.xxx;
  if (BACKGROUND == 0) {
    return round(n * c) / c;
  } else if (BACKGROUND == 1) {
    return round(fract(n * c));
  } else if (BACKGROUND == 2) {
    return round(n);
  } else {
    float f = n.x + n.y + n.z;
    return max(round(fract(f * c)), 0.2).xxx;
  }
}

////////////////////////// COMPUTE SHADERS //////////////////////////

#ifdef IS_COMP_SHADER
#endif // IS_COMP_SHADER

////////////////////////// VERTEX SHADERS //////////////////////////

#ifdef IS_VERTEX_SHADER
layout(location = 0) out vec3 outPosition;
layout(location = 1) out vec3 outNormal;
layout(location = 2) out vec2 outUv;

void VS_Background() {
  vec2 uv = VS_FullScreen();
  gl_Position = vec4(uv * 2.0 - 1.0, 0.0, 1.0);
  outUv = uv;
}

#ifdef _ENTRY_POINT_VS_Obj
layout(location = 0) in vec3 inPosition;
layout(location = 1) in vec3 inNormal;
layout(location = 2) in vec2 inUv;

void VS_Obj() {
  vec4 worldPos = camera.view * vec4(inPosition, 1.0);
  gl_Position = camera.projection * worldPos;
  outPosition = worldPos.xyz;
  outNormal = inNormal;
  outUv = vec2(inUv.x, 1.0 - inUv.y);
}
#endif // _ENTRY_POINT_VS_Obj
#endif // IS_VERTEX_SHADER

////////////////////////// PIXEL SHADERS //////////////////////////

#ifdef IS_PIXEL_SHADER
layout(location = 0) in vec3 inPos;
layout(location = 1) in vec3 inNormal;
layout(location = 2) in vec2 inUv;

layout(location = 0) out vec4 outColor;

void PS_Background() {
  vec3 dir = computeDir(inUv);
  outColor = vec4(sampleEnv(dir), 1.0);
}

void PS_Obj() {
  mat3 tangentSpace = LocalToWorld(inNormal);

  float bump = texture(HeadBumpTexture, inUv).x;
  vec2 bumpGrad = vec2(dFdx(bump), dFdy(bump)); 
  vec3 bumpNormal = vec3(BUMP_STRENGTH * bumpGrad, 1.0);
  vec3 normal = tangentSpace * normalize(bumpNormal);

  if (RENDER_MODE == 0) {
    outColor = vec4(texture(HeadLambertianTexture, inUv).rgb, 1.0);
  } else if (RENDER_MODE == 1) {
    outColor = vec4(0.5 * normal + 0.5.xxx, 1.0);
  } else if (RENDER_MODE == 2) {
    outColor = vec4(bump.xxx, 1.0);
  } else {
    outColor = vec4(0.0.xxx, 1.0);
  }
}
#endif // IS_PIXEL_SHADER

