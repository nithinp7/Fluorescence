
#include "ImDraw.glsl"

void mark(vec2 v) {
  setColor(vec4(0.0.xxx, 1.0));
  float r = 0.1;
  addLine(v - r.xx, v + r.xx);
  addLine(v + vec2(-r, r), v + vec2(r, -r));
}

void dda() {
  drawGrid();

  vec2 o = vec2(POS_X, POS_Y);
  vec2 d = vec2(cos(RAY_ANGLE), sin(RAY_ANGLE));
  drawRay(o, 40.0 * d);

  ivec2 sn = ivec2(sign(d));
  vec2 fr = fract(o);
  vec2 rem = 1.0.xx - fr;
  if (sn[0] < 0) rem[0] = fr[0];
  if (sn[1] < 0) rem[1] = fr[1];
  vec2 t = abs(rem / d);
  vec2 invD = abs(1.0/d);
  ivec2 coord = ivec2(o);
  float globalT = 0.0;
  for (int i = 0; i < 40; i++) {
    highlightGridCell(coord);
    mark(o + globalT * d);

    uint stepAxis = (t.x < t.y) ? 0 : 1;
    coord[stepAxis] += sn[stepAxis];
    globalT += t[stepAxis];
    t -= t[stepAxis].xx;
    t[stepAxis] = invD[stepAxis];
  }
}

#ifdef IS_COMP_SHADER
void CS_Update() {
  dda();
  finishTriangles();
  finishLines();
}
#endif // IS_COMP_SHADER

#ifdef IS_VERTEX_SHADER
VertexOutput VS_Background() {
  VertexOutput OUT;
  OUT.color = vec4(1.0, 0.0, 0.0, 1.0);
  OUT.uv = VS_FullScreen();
  return OUT; 
}

VertexOutput VS_Lines() {
  Vertex v = lineVertexBuffer[gl_VertexIndex];
  v.pos *= GRID_SCALE;
  
  VertexOutput OUT;
  OUT.color = v.color;
  OUT.uv = vec2(v.pos.x, 1.0 - v.pos.y);
  gl_Position = vec4(OUT.uv * 2.0 - 1.0.xx, 0.0, 1.0);
  
  return OUT;
}

VertexOutput VS_Triangles() {
  Vertex v = triangleVertexBuffer[gl_VertexIndex];
  v.pos *= GRID_SCALE;
  
  VertexOutput OUT;
  OUT.color = v.color;
  OUT.uv = vec2(v.pos.x, 1.0 - v.pos.y);
  gl_Position = vec4(OUT.uv * 2.0 - 1.0.xx, 0.0, 1.0);
  
  return OUT;
}
#endif // IS_VERTEX_SHADER


#ifdef IS_PIXEL_SHADER
void PS_Background(VertexOutput IN) {
  outColor = vec4(0.025.xxx, 1.0);
}

void PS_Triangles(VertexOutput IN) {
  outColor = IN.color;
}

void PS_Lines(VertexOutput IN) {
  outColor = IN.color;
}
#endif // IS_PIXEL_SHADER