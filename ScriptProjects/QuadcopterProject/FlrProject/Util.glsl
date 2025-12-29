
bool isZoomEnabled() {
  return (uniforms.inputMask & (INPUT_BIT_RIGHT_MOUSE | INPUT_BIT_SPACE)) != 0;
}

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

mat4 getInverseView() {
  mat4 inverseView = camera.inverseView;
  vec4 camPos = inverseView[3];
  if (isZoomEnabled()) {
    vec3 focusPos = getPos(0);//shadowCamera[0][3].xyz;
    vec3 worldUp = vec3(0.0, 1.0, 0.0);
    vec3 front = normalize(focusPos - camPos.xyz);
    vec3 right = normalize(cross(front, worldUp));
    vec3 up = normalize(cross(right, front));
    inverseView[0] = vec4(right, 0.0);
    inverseView[1] = vec4(up, 0.0);
    inverseView[2] = vec4(-front, 0.0);
    inverseView[3] = camPos;
  }
  return inverseView; 
}

mat4 getView() {
  if (isZoomEnabled()) {
    return inverse(getInverseView());
  }
  return camera.view;
}

mat4 getProjection() {
  mat4 projection = camera.projection;
  if (isZoomEnabled()) {
    vec3 focusPos = getPos(0);//shadowCamera[0][3].xyz;
    vec3 diff = focusPos - camera.inverseView[3].xyz;
    float dist = length(diff);
    float zoom = ZOOM_MULT * dist;
    projection[0] *= zoom;
    projection[1] *= zoom;
  }
  return projection;
}

mat4 getInverseProjection() {
  if (isZoomEnabled()) {
    return inverse(getProjection());
  }
  return camera.inverseProjection;
}

vec3 computeDir(vec2 uv) {
	vec2 d = uv * 2.0 - 1.0;

	vec4 target = getInverseProjection() * vec4(d, 1.0.xx);
	return (getInverseView() * vec4(normalize(target.xyz), 0)).xyz;
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