
#include <Misc/Constants.glsl>

#ifdef IS_VERTEX_SHADER
ScreenVertexOutput VS_Background() {
  return ScreenVertexOutput(VS_FullScreen());
}

VertexOutput VS_Points() { 
  Vertex v = vertexBuffer[gl_InstanceIndex];
  vec3 localPos = sphereVertexBuffer[gl_VertexIndex].position.xyz;
  vec3 pos = v.position.xyz + POINT_RADIUS * localPos;
  VertexOutput OUT;
  OUT.position = vec4(pos, 1.0);
  OUT.color = v.color;
  OUT.normal = normalize(localPos);
  gl_Position = camera.projection * camera.view * OUT.position;
  return OUT;
}

VertexOutput VS_Origin() {
  vec3 pos = POINT_RADIUS * sphereVertexBuffer[gl_VertexIndex].position.xyz;
  VertexOutput OUT;
  OUT.position = vec4(pos, 1.0);
  OUT.color = globalState[0].dbgColor;
  OUT.normal = normalize(pos);
  gl_Position = camera.projection * camera.view * OUT.position;
  return OUT;
}

vec3 calcNormal() {
  uint triIdx = gl_VertexIndex/3;
  vec3 p0 = getTetVertex(3*triIdx+0).position.xyz;
  vec3 p1 = getTetVertex(3*triIdx+1).position.xyz;
  vec3 p2 = getTetVertex(3*triIdx+2).position.xyz;
  return normalize(cross(p1-p0, p2-p0)); 
}

VertexOutput VS_Triangles() {   
  Vertex v = getTetVertex(gl_VertexIndex);
  if (bool(uniforms.inputMask & INPUT_BIT_SPACE))
    v.position = 0.0.xxxx;
  VertexOutput OUT;
  OUT.position = v.position;
  OUT.color = vec4(0.0, 0.0, 1.0, 1.0);
  OUT.normal = calcNormal();
  gl_Position = camera.projection * camera.view * OUT.position;
  return OUT;
}

VertexOutput VS_TriangleLines() {
  Vertex v = getTetVertex(gl_VertexIndex);
  VertexOutput OUT;
  OUT.position = camera.projection * camera.view * v.position;
  OUT.color = vec4(0.0, 0.0, 100.0, 1.0);
  OUT.normal = calcNormal();
  gl_Position = OUT.position;
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
vec3 simpleShading(VertexOutput IN) {
  vec3 n = normalize(IN.normal);
  vec3 pos = IN.position.xyz;// / IN.position.w;
  vec3 wo = normalize(camera.inverseView[3].xyz - pos);
  
  vec3 Li = 1.0.xxx;
  vec3 Lpos = 1.0.xxx;
  vec3 wi = normalize(Lpos - pos);
  vec3 h = normalize(wi+wo);

  float nDotWi = dot(n, wi);
  float nDotWo = dot(n, wo);
  float cull = (nDotWi * nDotWo > 0.0) ? 1.0 : 0.0;
  vec3 diff = cull * IN.color.rgb * abs(nDotWi) / PI;
  vec3 spec = cull * pow(abs(dot(h, n)), 50.0) * Li;
  vec3 amb = 0.1.xxx * IN.color.rgb;

  return spec + diff + amb;
}

void PS_Background(ScreenVertexOutput IN) {
  outColor = vec4(0.1 * sampleEnv(computeDir(IN.uv)), 1.0);
}

void PS_Points(VertexOutput IN) {
  outColor = vec4(simpleShading(IN), 1.0);
}

void PS_Triangles(VertexOutput IN) {
  outColor = vec4(simpleShading(IN), 1.0);
}

void PS_Lines(VertexOutput IN) {
  outColor = vec4(IN.color.rgb, 1.0);
}
#endif // IS_PIXEL_SHADER
