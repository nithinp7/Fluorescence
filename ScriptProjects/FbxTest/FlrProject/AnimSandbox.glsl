#include "Util.glsl"

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
  // SPHERE VERT BUFFER
  {
    uint sphereVertIdx = 0;
    vec4 color = vec4(1.0, 0.0, 0.0, 1.0);
    float DTHETA = 2.0 * PI / SPHERE_RES;
    float PHI_LIM = 0.95 * PI / 2.0;
    float DPHI = 2.0 * PHI_LIM / SPHERE_RES;
    for(uint i=0;i<SPHERE_RES;i++) for(uint j=0;j<SPHERE_RES;j++) {
      uint i1=i+1, j1=j+1;
      float theta0=DTHETA*i, theta1=DTHETA*i1;
      float phi0=DPHI*j-PHI_LIM, phi1=DPHI*j1-PHI_LIM;
      
      sphereVertexBuffer[sphereVertIdx++] = calcSphereVert(theta0,phi0);
      sphereVertexBuffer[sphereVertIdx++] = calcSphereVert(theta1,phi0);
      sphereVertexBuffer[sphereVertIdx++] = calcSphereVert(theta1,phi1);
      
      sphereVertexBuffer[sphereVertIdx++] = calcSphereVert(theta0,phi0);
      sphereVertexBuffer[sphereVertIdx++] = calcSphereVert(theta1,phi1);
      sphereVertexBuffer[sphereVertIdx++] = calcSphereVert(theta0,phi1);
    }
  }
}
#endif // IS_COMP_SHADER

#ifdef IS_VERTEX_SHADER
VertexOutput VS_Test() {
  return VertexOutput(0.0.xxx, VS_FullScreen());
}

VertexOutput VS_Sphere() {
  const float R = 0.1;
  vec3 particlePos = getPos(gl_InstanceIndex);
  vec3 vpos = sphereVertexBuffer[gl_VertexIndex].xyz;
  vec3 worldPos = particlePos + R * vpos;
  gl_Position = camera.projection * camera.view * vec4(worldPos, 1.0);
  vec3 normal = normalize(vpos);
  return VertexOutput(vpos, 0.0.xx);
}

VertexOutput VS_Tris() {
  vec3 worldPos = getPos(gl_VertexIndex);
  gl_Position = camera.projection * camera.view * vec4(worldPos, 1.0);
  vec3 normal = getNormal(gl_VertexIndex);
  return VertexOutput(normal, 0.0.xx);
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
  outColor = vec4(IN.normal * 0.5 + 0.5.xxx, 1.0);
}
#endif // IS_PIXEL_SHADER