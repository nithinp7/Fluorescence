#include <Misc/Sampling.glsl>
#include "Util.glsl"
#include "Draw.glsl"

#define FLT_MAX 3.402823466e+38

uint support(vec3 dir) {
  uint vertexCount = spheresIndirect(0)[0].instanceCount;
  float maxDot = dot(vertexBuffer[0].position.xyz, dir);
  uint candidateIdx = 0;
  for (uint i = 1; i < vertexCount; i++) {
    float d = dot(vertexBuffer[i].position.xyz, dir);
    if (d > maxDot) {
      candidateIdx = i;
      maxDot = d;
    }
  }
  return candidateIdx;
}

struct TetChecker {
  vec3 projPos;
  float closestDist2;
  vec3 dbgColor;
  bool bInside;
};
TetChecker createTetChecker() {
  return TetChecker(0.0.xxx, FLT_MAX, 0.0.xxx, true);
}

// Helper function for finding closest point on tet + checking inside / outside
// - Finds closest point on this particular face from the origin
// - Updates the tetChecker, if this is closer than previously checked faces
// - Checks whether the origin is behind the face normal, updates inside / outside determination
void checkFace(inout TetChecker tetCheck, vec3 a, vec3 b, vec3 c, vec3 d) {
  vec3 projPos;

  vec3 ab = b-a;
  vec3 ac = c-a;
  vec3 bc = c-b;
  vec3 n = cross(ab, ac);
  
  tetCheck.bInside = bool(tetCheck.bInside) && (dot(n, -a) * dot(n, d-a) >= 0.0);

  vec3 perpAB = cross(ab, n);
  vec3 perpAC = cross(n, ac);
  vec3 perpBC = cross(bc, n);

  vec3 t = vec3(
      dot(perpAB, -a),
      dot(perpAC, -a),
      dot(perpBC, -b));

  bvec3 lt0 = lessThan(t, 0.0.xxx);
  vec3 planeProj = dot(n, a) / dot(n, n) * n;
  if (all(lt0)) {
    // inside triangle
    projPos = planeProj;
  } else if (!any(lt0.xy)) {
    // corner a
    projPos = a;
  } else if (!any(lt0.xz)) {
    // corner b
    projPos = b;
  } else if (!any(lt0.yz)) {
    // corner c
    projPos = c;
  } else if (!lt0.x) {
    // line ab
    if (dot(ab, -a) < 0.0)
      projPos = a;
    else if (dot(ab, b) < 0.0)
      projPos = b;
    else
      projPos = planeProj - t.x / dot(perpAB, perpAB) * perpAB;
  } else if (!lt0.y) {
    // line ac
    if (dot(ac, -a) < 0.0)
      projPos = a;
    else if (dot(ac, c) < 0.0)
      projPos = c;
    else
      projPos = planeProj - t.y / dot(perpAC, perpAC) * perpAC;
  } else if (!lt0.z) {
    // line bc
    if (dot(bc, -b) < 0.0)
      projPos = b;
    else if (dot(bc, c) < 0.0)
      projPos = c;
    else
      projPos = planeProj - t.z / dot(perpBC, perpBC) * perpBC;
  }

  float dist2 = dot(projPos, projPos);
  if (dist2 < tetCheck.closestDist2) {
    tetCheck.projPos = projPos;
    tetCheck.closestDist2 = dist2;
    tetCheck.dbgColor = vec3(0.0, 1.0, 0.0);
  }
}

void checkTet() {
  Tetrahedron tet = currentTet[0];
  TetChecker checker = createTetChecker();

  vec3 a = vertexBuffer[tet.a].position.xyz;
  vec3 b = vertexBuffer[tet.b].position.xyz;
  vec3 c = vertexBuffer[tet.c].position.xyz;
  vec3 d = vertexBuffer[tet.d].position.xyz;

  checkFace(checker, a, b, c, d);
  checkFace(checker, a, c, d, b);
  checkFace(checker, a, d, b, c);

  // not needed in gjk
  // TODO still need to do a half plane check here... to determine whether inside / outside
  checkFace(checker, c, d, b, a);

  setLineColor(checker.dbgColor);
  addLine(checker.projPos, 0.0.xxx);

  if (checker.bInside) {
    globalState[0].dbgColor = vec4(0.0, 1.0, 0.0, 1.0);
  } else {
    sortTet(-checker.projPos);
    uint supportIdx = support(-checker.projPos);
    vec3 supportPos = vertexBuffer[supportIdx].position.xyz;
    setLineColor(vec3(1.0, 1.0, 0.0));
    addLine(checker.projPos, supportPos);
    selectVertex(supportIdx);
    globalState[0].dbgColor = vec4(1.0 , 0.0, 0.0, 1.0);
  }

  selectTet(tet.a, tet.b, tet.c, tet.d);

  finishLines();
}

#ifdef IS_COMP_SHADER
void CS_Init() {
  uint vertexCount = 0;
  // TETRAHEDRON VERT BUFFER
  {
    uint vertexOffset = vertexCount;
    vec4 blue = vec4(0.0, 0.0, 1.0, 1.0);

    uvec2 seed = uvec2(INIT_SEED, INIT_SEED+4);
    for (int i=0; i<15; i++) {
      float r = 2.5;
      vertexBuffer[vertexCount++] = Vertex(vec4(r * randVec3(seed), 1.0), blue);
    }

    selectTet(0, 1, 2, 3);
  }

  // SPHERE VERT BUFFER
  createSphereVertexBuffer();
  
  {
    // points
    IndirectArgs args;
    args.firstInstance = 0;
    args.instanceCount = vertexCount;
    args.firstVertex = 0;
    args.vertexCount = SPHERE_VERT_COUNT;
    spheresIndirect(0)[0] = args;
  }

  {
    // origin
    IndirectArgs args;
    args.firstInstance = 0;
    args.instanceCount = 1;
    args.firstVertex = 0;
    args.vertexCount = SPHERE_VERT_COUNT;
    spheresIndirect(1)[0] = args;
  }

  {
    // selected tet
    IndirectArgs args;
    args.firstInstance = 0;
    args.instanceCount = 1;
    args.firstVertex = 0;
    args.vertexCount = 12;
    trianglesIndirect[0] = args;
  }
}

void CS_Update() { 
  updateInputs();
  resetColors();
  checkTet();
}

void CS_GjkStep() {
  Tetrahedron tet = currentTet[0];
  TetChecker checker = createTetChecker();

  vec3 a = vertexBuffer[tet.a].position.xyz;
  vec3 b = vertexBuffer[tet.b].position.xyz;
  vec3 c = vertexBuffer[tet.c].position.xyz;
  vec3 d = vertexBuffer[tet.d].position.xyz;

  checkFace(checker, a, b, c, d);
  checkFace(checker, a, c, d, b);
  checkFace(checker, a, d, b, c);

  // // not needed in gjk
  checkFace(checker, c, d, b, a);

  if (!checker.bInside) {
    uint supportIdx = support(-checker.projPos);
    if (!any(equal(supportIdx.xxxx, uvec4(tet.a, tet.b, tet.c, tet.d))))
      selectTet(supportIdx, tet.a, tet.b, tet.c);
  }
}

#endif // IS_COMP_SHADER
