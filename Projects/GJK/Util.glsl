vec3 computeDir(vec2 uv) {
	vec2 d = uv * 2.0 - 1.0;

	vec4 target = camera.inverseProjection * vec4(d, 1.0.xx);
	return (camera.inverseView * vec4(normalize(target.xyz), 0)).xyz;
}

SimpleVertex calcSphereVert(float theta, float phi) {
  return SimpleVertex(vec4(cos(theta) * cos(phi), sin(phi), -sin(theta) * cos(phi), 1.0));
}

void createSphereVertexBuffer() {
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

vec3 sampleEnv(vec3 dir) {
  float c = 5.0;
  vec3 n = 0.5 * normalize(dir) + 0.5.xxx;
  uint BACKGROUND = 0;
  if (BACKGROUND == 0) {
    return 0.5 * round(n * c) / c;
  } else if (BACKGROUND == 1) {
    return round(fract(n * c));
  } else if (BACKGROUND == 2) {
    return round(n);
  } else {
    float f = n.x + n.y + n.z;
    return max(round(fract(f * c)), 0.2).xxx;
  }
}

// DEBUG LINES TOOL
vec4 g_currentLineColor = vec4(0.0, 1.0, 0.0, 1.0);
uint g_lineVertexCount = 0;
void addLine(vec3 a, vec3 b) {
  lineVertexBuffer[g_lineVertexCount++] = Vertex(vec4(a, 1.0), g_currentLineColor);
  lineVertexBuffer[g_lineVertexCount++] = Vertex(vec4(b, 1.0), g_currentLineColor);
}

void setLineColor(vec3 color) { g_currentLineColor = vec4(color, 1.0); }

void finishLines() {
  IndirectArgs args;
  args.firstInstance = 0;
  args.instanceCount = 1;
  args.firstVertex = 0;
  args.vertexCount = g_lineVertexCount;
  linesIndirect[0] = args;
}

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
    uint vertCount = spheresIndirect(0)[0].instanceCount;
    for (uint i=0; i<vertCount; i++) {
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

void resetColors() {
  uint vertexCount = spheresIndirect(0)[0].instanceCount;
  for (uint i=0; i<vertexCount; i++) {
    vertexBuffer[i].color = vec4(0.0, 0.0, 1.0, 1.0);
  }
}

uint indices[12] = {
  0, 2, 1,
  0, 1, 3,
  1, 2, 3,
  0, 3, 2
};
Vertex getTetVertex(uint i) {
  i = indices[i];
  if (i == 0)
    i = currentTet[0].a;
  else if (i == 1)
    i = currentTet[0].b;
  else if (i == 2)
    i = currentTet[0].c;
  else 
    i = currentTet[0].d;
  return vertexBuffer[i];
}

void selectVertex(uint a) {
  vertexBuffer[a].color = vec4(100.0, 100.0, 0.0, 1.0);
}

void selectTet(uint a, uint b, uint c, uint d) {
  currentTet[0] = Tetrahedron(a, b, c, d);
  selectVertex(a);
  selectVertex(b);
  selectVertex(c);
  selectVertex(d);
}

void sortTet_swap(inout uint a, inout uint b, inout float da, inout float db) {
  uint tmp = a;
  a = b;
  b = tmp;

  float tmpf = da;
  da = db;
  db = tmpf;
}

void sortTet(vec3 dir) {
  Tetrahedron t = currentTet[0];
  uvec4 indices = uvec4(t.a, t.b, t.c, t.d);
  vec4 d = vec4(
          dot(vertexBuffer[t.a].position.xyz, dir),
          dot(vertexBuffer[t.b].position.xyz, dir),
          dot(vertexBuffer[t.c].position.xyz, dir),
          dot(vertexBuffer[t.d].position.xyz, dir));
  for (int i=0; i<4; i++) {
    int minJ = i;
    for (int j=i+1; j<4; j++) {
      if (d[j] < d[minJ])
        minJ = j;
    }
    sortTet_swap(indices[i], indices[minJ], d[i], d[minJ]);
  }
  currentTet[0] = Tetrahedron(indices[0], indices[1], indices[2], indices[3]);
}
