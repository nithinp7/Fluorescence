#include "Util.glsl"

#define FLT_MAX 3.402823466e+38

// INPUT
#define IS_PRESSED(K) ((uniforms.inputMask & INPUT_BIT_##K) != 0)
void updateInputs() {
  vec3 disp = 0.0.xxx;
  float v = 0.01;
  if (IS_PRESSED(L)) {
    disp.x += v;
  }
  if (IS_PRESSED(J)) {
    disp.x -= v;
  }
  if (IS_PRESSED(N)) {
    disp.y += v;
  }
  if (IS_PRESSED(M)) {
    disp.y -= v;
  }
  if (IS_PRESSED(I)) {
    disp.z += v;
  }
  if (IS_PRESSED(K)) {
    disp.z -= v;
  }

  float dtheta = 0.0;
  if (IS_PRESSED(O)) {
    dtheta += v;
  }
  if (IS_PRESSED(U)) {
    dtheta -= v;
  }

  if (dtheta != 0.0 || disp != 0.0.xxx) {
    for (uint i=1; i<5; i++) {
      vec4 pos = vertexBuffer[i].position;
      float theta = atan(pos.z, pos.y);
      float l = length(pos.yz);
      theta += dtheta;
      pos.z = sin(theta) * l;
      pos.y = cos(theta) * l;
      pos.xyz += disp;
      vertexBuffer[i].position = pos;
    }
  }
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

void checkFace(inout TetChecker tetCheck, vec3 a, vec3 b, vec3 c, vec3 d) {
  vec3 dbgColor;
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
    dbgColor = vec3(0.0, 1.0, 0.0);
    projPos = planeProj;
  } else if (!any(lt0.xy)) {
    // corner a
    dbgColor = vec3(1.0, 0.0, 0.0);
    projPos = a;
  } else if (!any(lt0.xz)) {
    // corner b
    dbgColor = vec3(1.0, 0.0, 0.0);
    projPos = b;
  } else if (!any(lt0.yz)) {
    // corner c
    dbgColor = vec3(1.0, 0.0, 0.0);
    projPos = c;
  } else if (!lt0.x) {
    // line ab
    dbgColor = vec3(1.0, 0.0, 1.0);
    if (dot(ab, -a) < 0.0)
      projPos = a;
    else if (dot(ab, b) < 0.0)
      projPos = b;
    else
      projPos = planeProj - t.x / dot(perpAB, perpAB) * perpAB;
  } else if (!lt0.y) {
    // line ac
    dbgColor = vec3(0.0, 1.0, 1.0);
    if (dot(ac, -a) < 0.0)
      projPos = a;
    else if (dot(ac, c) < 0.0)
      projPos = c;
    else
      projPos = planeProj - t.y / dot(perpAC, perpAC) * perpAC;
  } else if (!lt0.z) {
    // line bc
    dbgColor = vec3(0.0, 0.0, 1.0);
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
    tetCheck.dbgColor = dbgColor;
  }
}

void nearestSimplex() {
  TetChecker checker = createTetChecker();

  vec3 a = vertexBuffer[1].position.xyz;
  vec3 b = vertexBuffer[2].position.xyz;
  vec3 c = vertexBuffer[3].position.xyz;
  vec3 d = vertexBuffer[4].position.xyz;

  checkFace(checker, a, b, c, d);
  checkFace(checker, a, c, d, b);
  checkFace(checker, a, d, b, c);

  // not needed in gjk
  checkFace(checker, c, d, b, a);

  setLineColor(checker.dbgColor);
  addLine(checker.projPos, 0.0.xxx);

  if (checker.bInside) {
    vertexBuffer[0].color = vec4(0.0, 1.0, 0.0, 1.0);
  } else {
    vertexBuffer[0].color = vec4(1.0 , 0.0, 0.0, 1.0);
  }

  finishLines();
}

#ifdef IS_COMP_SHADER
void CS_Init() {
  uint vertexCount = 0;
  // TETRAHEDRON VERT BUFFER
  {
    uint vertexOffset = vertexCount;
    vec4 red = vec4(1.0, 0.0, 0.0, 1.0);
    vertexBuffer[vertexCount++] = Vertex(vec4(0.0, 0.0, 0.0, 1.0), red);

    vec4 blue = vec4(0.0, 0.0, 1.0, 1.0);
    vertexBuffer[vertexCount++] = Vertex(vec4(0.0, 0.0, 1.0, 1.0), blue);
    vertexBuffer[vertexCount++] = Vertex(vec4(0.0, 1.0, 0.0, 1.0), blue);
    vertexBuffer[vertexCount++] = Vertex(vec4(0.0, 1.0, 1.0, 1.0), blue);
    vertexBuffer[vertexCount++] = Vertex(vec4(1.0, 1.0, 1.0, 1.0), blue);
  }

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
  
  {
    IndirectArgs args;
    args.firstInstance = 0;
    args.instanceCount = vertexCount;
    args.firstVertex = 0;
    args.vertexCount = SPHERE_VERT_COUNT;
    spheresIndirect[0] = args;
  }

  {
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
  nearestSimplex();
}

#endif // IS_COMP_SHADER

#ifdef IS_VERTEX_SHADER
ScreenVertexOutput VS_Background() {
  return ScreenVertexOutput(VS_FullScreen());
}

VertexOutput VS_Points() { 
  Vertex v = vertexBuffer[gl_InstanceIndex];
  float R = 0.01;
  vec3 pos = v.position.xyz + R * sphereVertexBuffer[gl_VertexIndex].position.xyz;
  gl_Position = camera.projection * camera.view * vec4(pos, 1.0);

  VertexOutput OUT;
  OUT.color = v.color;
  return OUT;
}

uint indices[] = {
    0, 2, 1,
    0, 1, 3,
    1, 2, 3,
    0, 3, 2};

vec3 calcNormal() {
  uint triIdx = gl_VertexIndex/3;
  vec3 p0 = vertexBuffer[indices[3*triIdx+0]+1].position.xyz;
  vec3 p1 = vertexBuffer[indices[3*triIdx+1]+1].position.xyz;
  vec3 p2 = vertexBuffer[indices[3*triIdx+2]+1].position.xyz;
  return normalize(cross(p1-p0, p2-p0)); 
}

VertexOutput VS_Triangles() {   
  Vertex v = vertexBuffer[indices[gl_VertexIndex] + 1];
  gl_Position = camera.projection * camera.view * v.position;
  vec3 n = calcNormal();

  VertexOutput OUT;
  OUT.color = v.color;
  return OUT;
}

VertexOutput VS_Lines() {
  Vertex v = lineVertexBuffer[gl_VertexIndex];

  gl_Position = camera.projection * camera.view * v.position;

  VertexOutput OUT;
  OUT.color = v.color;
  return OUT;
}
#endif // IS_VERTEX_SHADER

#ifdef IS_PIXEL_SHADER
void PS_Background(ScreenVertexOutput IN) {
  outColor = vec4(0.1 * sampleEnv(computeDir(IN.uv)), 1.0);
}

void PS_Points(VertexOutput IN) {
  outColor = vec4(IN.color.rgb, 1.0);
}

void PS_Triangles(VertexOutput IN) {
  outColor = vec4(IN.color.rgb, 1.0);
}

void PS_Lines(VertexOutput IN) {
  outColor = vec4(IN.color.rgb, 1.0);
}
#endif // IS_PIXEL_SHADER
