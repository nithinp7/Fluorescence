#include "Util.glsl"

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

void checkIntersection() {
  vec3 a = vertexBuffer[1].position.xyz;
  vec3 b = vertexBuffer[2].position.xyz;
  vec3 c = vertexBuffer[3].position.xyz;
  vec3 d = vertexBuffer[4].position.xyz;

  mat3 bcMat;
  bcMat[0] = b-a;
  bcMat[1] = c-a;
  bcMat[2] = d-a;

  vec3 bc = inverse(bcMat) * -a;
  float bcSum = bc.x + bc.y + bc.z;

  if (bcSum < 1.0 && all(greaterThanEqual(bc, 0.0.xxx)) && all(lessThanEqual(bc, 1.0.xxx))) {
    vertexBuffer[0].color = vec4(0.0, 1.0, 0.0, 1.0);
  } else {
    vertexBuffer[0].color = vec4(1.0 , 0.0, 0.0, 1.0);
  }

  finishLines();
}

float projectionSquared(vec3 v, vec3 n) {
  float n2 = dot(n, n);
  float p = dot(v, n);
  return p * p / n2;
}

struct FaceProjection {
  vec4 dbgColor;
  vec3 projPos;
  float dist2;
};

FaceProjection projectToFace(vec3 a, vec3 b, vec3 c) {
  vec3 ab = b-a;
  vec3 ac = c-a;
  vec3 bc = c-b;
  vec3 n = cross(ab, ac);

  vec3 perpAB = cross(ab, n);
  vec3 perpAC = cross(n, ac);
  vec3 perpBC = cross(bc, n);

  vec3 t = vec3(
      dot(perpAB, -a),
      dot(perpAC, -a),
      dot(perpBC, -b));

  FaceProjection p;

  bvec3 lt0 = lessThan(t, 0.0.xxx);
  vec3 planeProj = dot(n, a) / dot(n, n) * n;
  if (all(lt0)) {
    // inside triangle
    p.dbgColor = vec4(0.0, 1.0, 0.0, 1.0);
    p.projPos = planeProj;
  } else if (!any(lt0.xy)) {
    p.dbgColor = vec4(1.0, 0.0, 0.0, 1.0);
    p.projPos = a;
  } else if (!any(lt0.xz)) {
    p.dbgColor = vec4(1.0, 0.0, 0.0, 1.0);
    p.projPos = b;
  } else if (!any(lt0.yz)) {
    p.dbgColor = vec4(1.0, 0.0, 0.0, 1.0);
    p.projPos = c;
  } else if (!lt0.x) {
    p.dbgColor = vec4(1.0, 0.0, 1.0, 1.0);
    if (dot(ab, -a) < 0.0)
      p.projPos = a;
    else if (dot(ab, b) < 0.0)
      p.projPos = b;
    else
      p.projPos = planeProj - t.x / dot(perpAB, perpAB) * perpAB;
  } else if (!lt0.y) {
    p.dbgColor = vec4(0.0, 1.0, 1.0, 1.0);
    if (dot(ac, -a) < 0.0)
      p.projPos = a;
    else if (dot(ac, c) < 0.0)
      p.projPos = c;
    else
      p.projPos = planeProj - t.y / dot(perpAC, perpAC) * perpAC;
  } else if (!lt0.z) {
    p.dbgColor = vec4(0.0, 0.0, 1.0, 1.0);
    if (dot(bc, -b) < 0.0)
      p.projPos = b;
    else if (dot(bc, c) < 0.0)
      p.projPos = c;
    else
      p.projPos = planeProj - t.z / dot(perpBC, perpBC) * perpBC;
  }

  p.dist2 = dot(p.projPos, p.projPos);

  return p;
}

void drawNearest(FaceProjection p) {
  setLineColor(p.dbgColor);
  addLine(p.projPos, 0.0.xxx);
}

void nearestSimplex() {
  vec3 a = vertexBuffer[1].position.xyz;
  vec3 b = vertexBuffer[2].position.xyz;
  vec3 c = vertexBuffer[3].position.xyz;
  vec3 d = vertexBuffer[4].position.xyz;

  FaceProjection abc = projectToFace(a, b, c);
  FaceProjection acd = projectToFace(a, c, d);
  FaceProjection adb = projectToFace(a, d, b);

  // not needed in gjk
  FaceProjection cdb = projectToFace(c, d, b);

  if (IS_PRESSED(SPACE)) {
    drawNearest(abc);
    drawNearest(acd);
    drawNearest(adb);
    drawNearest(cdb);
  } else if (all(lessThanEqual(abc.dist2.xxx, vec3(acd.dist2, adb.dist2, cdb.dist2)))) {
    drawNearest(abc);
  } else if (all(lessThanEqual(acd.dist2.xx, vec2(adb.dist2, cdb.dist2)))) {
    drawNearest(acd);
  } else if (adb.dist2 <= cdb.dist2) {
    drawNearest(adb);
  } else {
    drawNearest(cdb);
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
  checkIntersection();
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
  // OUT.color = vec4(0.5 * n + 0.5.xxx, 1.0);
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
