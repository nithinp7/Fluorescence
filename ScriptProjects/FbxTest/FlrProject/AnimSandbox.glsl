#include "Util.glsl"
#include "Lighting.glsl"

vec3 getPos(int idx) {
  return 
      vec3(
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

uint getPhase() {
  return uniforms.frameCount & 1;
}

mat4 getMatrix(uint idx) {
  return matrices(getPhase())[idx];
}

#ifdef IS_COMP_SHADER
void CS_Init() {
  initSphereVerts();
  initLights();
}
#endif // IS_COMP_SHADER

#ifdef IS_VERTEX_SHADER
SimpleVertexOutput VS_Test() {
  return SimpleVertexOutput(VS_FullScreen());
}

VertexOutput VS_Sphere() {
  VertexOutput OUT;
  const float R = 0.5;
  mat4 mat = getMatrix(gl_InstanceIndex);
  vec3 particlePos = mat[3].xyz;
  particlePos *= MESH_SCALE;
  vec3 vpos = sphereVertexBuffer[gl_VertexIndex].xyz;
  vec3 worldPos = particlePos + R * vpos;
  gl_Position = camera.projection * camera.view * vec4(worldPos, 1.0);
  OUT.pos = worldPos.xyz;
  OUT.normal = normalize(vpos);
  OUT.uv = 0.0.xx;
  return OUT;
}

VertexOutput VS_Tris() {
  VertexOutput OUT;
  OUT.debugColor = vec4(0.0.xxx, 1.0);
  vec3 localPos = getPos(gl_VertexIndex);
  vec3 localNormal = getNormal(gl_VertexIndex);
  vec4 worldPos, worldNormal;
  if (ENABLE_SKINNING) {
    mat4 skinMtx = mat4(0.0);
    for (int i = 0; i < MAX_INFLUENCES; i++) {
      uint matIdx = blendIndices[MAX_INFLUENCES * gl_VertexIndex + i];
      float weight = blendWeights[MAX_INFLUENCES * gl_VertexIndex + i];
      skinMtx += getMatrix(matIdx) * weight;
      if (matIdx == SELECT_BONE_INFLUENCE) {
        OUT.debugColor = vec4(weight.xxx, 1.0);
      }
    }
    worldPos = skinMtx * vec4(localPos, 1.0);
    worldNormal = skinMtx * vec4(localNormal, 0.0);
  } else {
    worldPos = vec4(localPos, 1.0);
    worldNormal = vec4(localNormal, 0.0);
  }

  worldPos.xyz *= MESH_SCALE;

  gl_Position = camera.projection * camera.view * worldPos;
  OUT.pos = worldPos.xyz;
  OUT.normal = worldNormal.xyz;
  OUT.uv = 0.0.xx;

  return OUT;
}
#endif // IS_VERTEX_SHADER

#ifdef IS_PIXEL_SHADER
void PS_Test(SimpleVertexOutput IN) {
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
  if (SHOW_NORMALS)
    color = IN.normal * 0.5 + 0.5.xxx;
  if (SELECT_BONE_INFLUENCE >= 0)
    color = IN.debugColor.rgb;
  outColor = vec4(color, 1.0);
}
#endif // IS_PIXEL_SHADER