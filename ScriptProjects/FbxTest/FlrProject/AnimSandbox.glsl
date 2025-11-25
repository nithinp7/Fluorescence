#include "Util.glsl"
#include "Lighting.glsl"

vec3 getPos(int idx) {
  return 
      MESH_SCALE * vec3(
          positions[3*idx + 0], 
          positions[3*idx + 1],
          positions[3*idx + 2]);
}

vec3 getNormal(int idx) {
  return 
      vec3(
          normals[3*idx + 0], 
          normals[3*idx + 1],
          normals[3*idx + 2]);
}

#ifdef IS_COMP_SHADER
void CS_Init() {
  initSphereVerts();
  initLights();
}
#endif // IS_COMP_SHADER

#ifdef IS_VERTEX_SHADER
VertexOutput VS_Test() {
  return VertexOutput(0.0.xxx, 0.0.xxx, VS_FullScreen());
}

VertexOutput VS_Sphere() {
  const float R = 0.1;
  vec3 particlePos = getPos(gl_InstanceIndex);
  vec3 vpos = sphereVertexBuffer[gl_VertexIndex].xyz;
  vec3 worldPos = particlePos + R * vpos;
  gl_Position = camera.projection * camera.view * vec4(worldPos, 1.0);
  vec3 normal = normalize(vpos);
  return VertexOutput(worldPos, normal, 0.0.xx);
}

VertexOutput VS_Tris() {
  vec3 worldPos = getPos(gl_VertexIndex);
  gl_Position = camera.projection * camera.view * vec4(worldPos, 1.0);
  vec3 normal = getNormal(gl_VertexIndex);
  return VertexOutput(worldPos, normal, 0.0.xx);
}
#endif // IS_VERTEX_SHADER

#ifdef IS_PIXEL_SHADER
void PS_Test(VertexOutput IN) {
  outColor = vec4(sampleEnv(computeDir(IN.uv)), 1.0);
}

void PS_Sphere(VertexOutput IN) {
  outColor = vec4(1.0, 0.0, 0.0, 1.0);
}

void PS_Tris(VertexOutput IN) {
  vec3 normal = normalize(IN.normal);
  uvec2 seed = uvec2(0);
  vec3 color = computeSurfaceLighting(seed, IN.pos, normal, computeDir(IN.uv));
  color = linearToSdr(color);
  outColor = vec4(color, 1.0);
}
#endif // IS_PIXEL_SHADER