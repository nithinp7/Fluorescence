#include "Util.glsl"
#include "Lighting.glsl"
#include <Misc/ReconstructPosition.glsl>

#extension GL_KHR_shader_subgroup_arithmetic: enable

#define FLT_MAX 3.402823466e+38
#define FLT_MIN 1.175494351e-38
#define FLT_LOWEST (-FLT_MAX)

uint getPhase() {
  return uniforms.frameCount & 1;
}

vec3 getPos(uint idx) {
  uint phase = getPhase();
  return 
      vec3(
          positions(phase)[3*idx + 0], 
          positions(phase)[3*idx + 1],
          positions(phase)[3*idx + 2]);
}

mat4 getGizmoTransform(uint instanceIdx) {
  GizmoView view = gizmoView(getPhase())[0];
  uint gizmoIdx = instanceIdx + view.head;
  mat4 modelTransform = mat4(0.0);
  if (gizmoIdx < view.tail) 
    modelTransform = gizmoBuffer[gizmoIdx % MAX_GIZMOS];
  return modelTransform;
}

#ifdef IS_COMP_SHADER
void CS_Init() {
  initSphereVerts();
  initCylinderVerts();
  initMaterials();

  for (int i=0; i<MAX_GIZMOS; i++)
    gizmoBuffer[i] = mat4(0.0);
  gizmoView(0)[0] = GizmoView(0, 0);
  gizmoView(1)[0] = GizmoView(0, 0);
}

void CS_UpdateCamera() {
  // single wave dispatch
  uint tid = uint(gl_LocalInvocationID);
  uint iters = (VERT_COUNT + 31) / 32;
  
  vec3 up = vec3(0.0, 1.0, 0.0);
  
  vec3 viewDir = -getSunDir();
  vec3 refA = normalize(cross(viewDir, up));
  vec3 refB = cross(refA, viewDir);

  vec4 lrbt = vec4(FLT_MAX, FLT_LOWEST, FLT_MAX, FLT_LOWEST);

  for (int iter = 0; iter < iters; iter++) {
    float minProjA = FLT_MAX;
    float maxProjA = FLT_LOWEST;
    float minProjB = FLT_MAX;
    float maxProjB = FLT_LOWEST;
    
    uint nodeIdx = 32 * iter + tid;
    if (nodeIdx < VERT_COUNT) {
      vec3 pos = getPos(nodeIdx);
      minProjA = maxProjA = dot(pos, refA);
      minProjB = maxProjB = dot(pos, refB);
    }

    lrbt.x = min(lrbt.x, subgroupMin(minProjA));
    lrbt.y = max(lrbt.y, subgroupMax(maxProjA));
    lrbt.z = min(lrbt.z, subgroupMin(minProjB));
    lrbt.w = max(lrbt.w, subgroupMax(maxProjB));
  }

  // z coord of focus point doesn't really matter, just pick first node
  vec3 focusPos = getPos(0);
  // ortho proj
  vec2 focusProj = vec2(dot(focusPos, refA), dot(focusPos, refB));
  focusPos += refA * (0.5 * lrbt.x + 0.5 * lrbt.y - focusProj.x);
  focusPos += refB * (0.5 * lrbt.z + 0.5 * lrbt.w - focusProj.y);
  focusPos -= 50.0 * viewDir;

  mat4 orthoProj;
  orthoProj[0] = vec4(refA / (lrbt.y - lrbt.x), 0.0);
  orthoProj[1] = vec4(refB / (lrbt.w - lrbt.z), 0.0);
  orthoProj[2] = vec4(viewDir / 100.0, 0.0);
  orthoProj[3] = vec4(focusPos, 1.0);
  shadowCamera[0] = orthoProj; 
}
#endif // IS_COMP_SHADER

#ifdef IS_VERTEX_SHADER
SimpleVertexOutput VS_Sky() {
  return SimpleVertexOutput(VS_FullScreen());
}

SimpleVertexOutput VS_Overlay() {
  if (SHOW_SHADOWMAP) {
    vec2 width = 0.2.xx;
    vec2 corner = 0.0.xx;
    vec2 uv = VS_Square(gl_VertexIndex, corner + 0.5 * width, 0.5 * width);
    gl_Position = vec4(2.0 * uv - 1.0.xx, 0.0, 1.0);
    return SimpleVertexOutput((uv - corner) / width);
  } else {
    gl_Position = vec4(0.0, 0.0, -1.0, 1.0);
    return SimpleVertexOutput(0.0.xx);
  }
}

VertexOutput VS_Sphere() {
  VertexOutput OUT;
  vec3 particlePos = getPos(gl_InstanceIndex);
  vec3 vpos = sphereVertexBuffer[gl_VertexIndex].xyz;
  vec3 worldPos = particlePos + SPHERE_RADIUS * vpos;
  vec4 spos = camera.projection * camera.view * vec4(worldPos, 1.0);
  gl_Position = spos; 
  OUT.pos = worldPos.xyz;
  OUT.normal = normalize(vpos);
  OUT.uv = spos.xy / spos.w * 0.5 + 0.5.xx;
  OUT.materialIdx = float(MATERIAL_SLOT_NODES);
  return OUT;
}

VertexOutput VS_Gizmo() {
  
  VertexOutput OUT;
  uint axisIdx = gl_VertexIndex / SPHERE_VERT_COUNT;
  uint cylinderVertIdx = gl_VertexIndex % SPHERE_VERT_COUNT;
  vec3 vpos = GIZMO_SCALE * vec3(GIZMO_THICKNESS, 4.0, GIZMO_THICKNESS) * cylinderVertexBuffer[cylinderVertIdx].xyz;
  vec3 normal = normalize(vec3(vpos.x, 0.0, vpos.z));
  if (axisIdx == 0) {
    vpos = vpos.yzx;
    normal = normal.yzx;
  } else if (axisIdx == 2) {
    vpos = vpos.zxy;
    normal = normal.zxy;
  }

  mat4 gizmoTransform = getGizmoTransform(gl_InstanceIndex);
  vec3 worldPos = SPHERE_RADIUS * vpos;
  vec4 spos = camera.projection * camera.view * gizmoTransform * vec4(worldPos, 1.0);
  gl_Position = spos; 
  OUT.pos = worldPos.xyz;
  OUT.normal = normal;
  OUT.uv = spos.xy / spos.w * 0.5 + 0.5.xx;
  OUT.materialIdx = float(MATERIAL_SLOT_GIZMO_RED + axisIdx);
  return OUT;
}

void VS_ShadowSphere() {
  vec3 particlePos = getPos(gl_InstanceIndex);
  vec3 vpos = sphereVertexBuffer[gl_VertexIndex].xyz;
  vec3 worldPos = particlePos + SPHERE_RADIUS * vpos;
  gl_Position = worldToShadowSpace(worldPos);
}

void VS_ShadowGizmo() {
  uint axisIdx = gl_VertexIndex / SPHERE_VERT_COUNT;
  uint cylinderVertIdx = gl_VertexIndex % SPHERE_VERT_COUNT;
  vec3 vpos = GIZMO_SCALE * vec3(GIZMO_THICKNESS, 4.0, GIZMO_THICKNESS) * cylinderVertexBuffer[cylinderVertIdx].xyz;
  if (axisIdx == 0) {
    vpos = vpos.yzx;
  } else if (axisIdx == 2) {
    vpos = vpos.zxy;
  }

  mat4 gizmoTransform = getGizmoTransform(gl_InstanceIndex);
  vec4 worldPos = gizmoTransform * vec4(SPHERE_RADIUS * vpos, 1.0);
  gl_Position = worldToShadowSpace(worldPos.xyz);
}

VertexOutput VS_Floor() {
  // quad with 2 triangles
  uint v;
  if (gl_VertexIndex <= 2)
    v = gl_VertexIndex;
  else if (gl_VertexIndex == 3)
    v = 2;
  else if (gl_VertexIndex == 4)
    v = 1;
  else // if (gl_VertexIndex == 5)
    v = 3;

  vec2 floorXZ = vec2(v & 1, v >> 1);
  vec2 uv = floorXZ;

  floorXZ *= 2.0;
  floorXZ -= vec2(1.0);

  // half width
  floorXZ *= 1000.0;

  // kind of a hack, offset by sphere radius to avoid clipping...
  vec4 pos = vec4(floorXZ[0], FLOOR_HEIGHT - SPHERE_RADIUS, floorXZ[1], 1.0);
  // vec4 pos = vec4(floorXZ[0], 0.0, floorXZ[1], 0.0);

  vec4 screenPos = camera.projection * camera.view * pos;
  gl_Position = screenPos;

  VertexOutput OUT;
  OUT.pos = pos.xyz;
  OUT.normal = vec3(0.0, 1.0, 0.0);
  OUT.uv = uv;
  OUT.materialIdx = float(MATERIAL_SLOT_GROUND);
  return OUT;
}
#endif // IS_VERTEX_SHADER

#ifdef IS_PIXEL_SHADER
// kinda hacky
#if defined(_ENTRY_POINT_PS_Shadow)
void PS_Shadow() {}
#else
void PS_Sky(SimpleVertexOutput IN) {
  vec3 color = sampleSky(computeDir(IN.uv));
  color = linearToSdr(color);
  outColor = vec4(color, 1.0);
}

void PS_Shaded(VertexOutput IN) {
  Material mat = materialBuffer[uint(round(IN.materialIdx))];
  vec3 viewDir = normalize(IN.pos - camera.inverseView[3].xyz);
  vec3 color = computeSurfaceLighting(mat, IN.pos, IN.normal, viewDir);
  color = linearToSdr(color);
  if (SHOW_NORMALS)
    color = IN.normal * 0.5 + 0.5.xxx;
  outColor = vec4(color, 1.0);
}

void PS_Overlay(SimpleVertexOutput IN) {
  float draw = texture(shadowMapTexture, IN.uv).r;
  outColor = vec4(1000.0 * abs(1.0.xxx - draw.xxx), 1.0);
}
#endif // not shadow
#endif // IS_PIXEL_SHADER