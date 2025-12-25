vec3 computeDir(vec2 uv) {
	vec2 d = uv * 2.0 - 1.0;

	vec4 target = camera.inverseProjection * vec4(d, 1.0.xx);
	return (camera.inverseView * vec4(normalize(target.xyz), 0)).xyz;
}

vec4 calcSphereVert(float theta, float phi) {
  return vec4(cos(theta) * cos(phi), sin(phi), -sin(theta) * cos(phi), 1.0);
}

// TODO still missing caps
void initSphereVerts() {
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

vec4 calcCylinderVert(float theta, float h) {
  return vec4(cos(theta), h, -sin(theta), 1.0);
}

// TODO still missing caps
void initCylinderVerts() {
  uint vertIdx = 0;
  float DTHETA = 2.0 * PI / SPHERE_RES;
  float DH = 1.0 / SPHERE_RES;
  for(uint i=0;i<SPHERE_RES;i++) for(uint j=0;j<SPHERE_RES;j++) {
    uint i1=i+1, j1=j+1;
    float theta0=DTHETA*i, theta1=DTHETA*i1;
    float h0=DH*j, h1=DH*j1;
    
    cylinderVertexBuffer[vertIdx++] = calcCylinderVert(theta0,h0);
    cylinderVertexBuffer[vertIdx++] = calcCylinderVert(theta1,h0);
    cylinderVertexBuffer[vertIdx++] = calcCylinderVert(theta1,h1);
    
    cylinderVertexBuffer[vertIdx++] = calcCylinderVert(theta0,h0);
    cylinderVertexBuffer[vertIdx++] = calcCylinderVert(theta1,h1);
    cylinderVertexBuffer[vertIdx++] = calcCylinderVert(theta0,h1);
  }
}