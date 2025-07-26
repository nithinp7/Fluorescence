
#ifdef IS_VERTEX_SHADER
ScreenVertexOutput VS_Background() {
  return ScreenVertexOutput(VS_FullScreen());
}

VertexOutput VS_Points() { 
  Vertex v = vertexBuffer[gl_InstanceIndex];
  vec3 pos = v.position.xyz + POINT_RADIUS * sphereVertexBuffer[gl_VertexIndex].position.xyz;
  gl_Position = camera.projection * camera.view * vec4(pos, 1.0);

  VertexOutput OUT;
  OUT.color = v.color;
  return OUT;
}

VertexOutput VS_Origin() {
  vec3 pos = POINT_RADIUS * sphereVertexBuffer[gl_VertexIndex].position.xyz;
  gl_Position = camera.projection * camera.view * vec4(pos, 1.0);

  VertexOutput OUT;
  OUT.color = globalState[0].dbgColor;
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
