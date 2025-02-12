
////////////////////////// COMPUTE SHADERS //////////////////////////

#ifdef IS_COMP_SHADER
#endif // IS_COMP_SHADER

////////////////////////// VERTEX SHADERS //////////////////////////

#ifdef IS_VERTEX_SHADER
layout(location = 0) out vec2 outUv;
layout(location = 1) out vec3 outPos;

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
  outPos = worldPos.xyz;
  outUv = inUv;
}
#endif // _ENTRY_POINT_VS_Obj
#endif // IS_VERTEX_SHADER

////////////////////////// PIXEL SHADERS //////////////////////////

#ifdef IS_PIXEL_SHADER
layout(location = 0) in vec2 inUv;
layout(location = 1) in vec3 inPos;

layout(location = 0) out vec4 outColor;

void PS_Background() {
  outColor = vec4(inUv, 0.0, 1.0);
}

void PS_Obj() {
  outColor = vec4(inUv, 0.0, 1.0);
}
#endif // IS_PIXEL_SHADER

