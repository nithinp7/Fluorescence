
#ifndef _IMDRAW_GLSL_
#define _IMDRAW_GLSL_

#include <Misc/Sampling.glsl>

// 2D IMMEDIATE MODE DRAWING
vec4 g_currentColor = vec4(0.0, 1.0, 0.0, 1.0);
uint g_lineVertexCount = 0;
uint g_triangleVertexCount = 0;

void addLine(vec2 a, vec2 b) {
  lineVertexBuffer[g_lineVertexCount++] = Vertex(g_currentColor, a, 0.0.xx);
  lineVertexBuffer[g_lineVertexCount++] = Vertex(g_currentColor, b, 0.0.xx);
}

void addTriangle(vec2 a, vec2 b, vec2 c) {
  triangleVertexBuffer[g_triangleVertexCount++] = Vertex(g_currentColor, a, 0.0.xx);
  triangleVertexBuffer[g_triangleVertexCount++] = Vertex(g_currentColor, b, 0.0.xx);
  triangleVertexBuffer[g_triangleVertexCount++] = Vertex(g_currentColor, c, 0.0.xx);
}

void setColor(vec4 color) { g_currentColor = color; }

void finishLines() {
  IndirectArgs args;
  args.firstInstance = 0;
  args.instanceCount = 1;
  args.firstVertex = 0;
  args.vertexCount = g_lineVertexCount;
  linesIndirect[0] = args;
}

void finishTriangles() {
  IndirectArgs args;
  args.firstInstance = 0;
  args.instanceCount = 1;
  args.firstVertex = 0;
  args.vertexCount = g_triangleVertexCount;
  trianglesIndirect[0] = args;
}

void drawRay(vec2 o, vec2 d) {
  setColor(vec4(0.45, 0.01, 0.05, 1.0));
  addLine(o, o + d);
}

void drawGrid() {
  setColor(vec4(0.2, 0.1, 0.8, 1.0));
  for (int i = 0; i < 100; i++) {
    float t = (i + 1);
    addLine(vec2(t, 0.0), vec2(t, 100.0)); 
    addLine(vec2(0.0, t), vec2(100.0, t));
  }
}

#define HIGHLIGHT_MODE_FULL_CELL 0
#define HIGHLIGHT_MODE_CURRENT_COORD 1
void highlightGridCell(ivec2 coord, uint level, uint mode) {
  uint len = (mode == HIGHLIGHT_MODE_FULL_CELL) ? (1 << level) : 1;
  vec2 v00 = floor(vec2(coord)/len) * len;
  vec2 v10 = v00 + len * vec2(1.0, 0.0);
  vec2 v11 = v00 + len * vec2(1.0, 1.0);
  vec2 v01 = v00 + len * vec2(0.0, 1.0);

  uvec2 seed = uvec2(level, level+1);
  float tint = (mode == HIGHLIGHT_MODE_FULL_CELL) ? 0.5 : 1.0;
  vec4 color = tint * 2.0 * vec4(randVec3(seed), 1.0);
  setColor(color);

  addTriangle(v00, v10, v11);
  addTriangle(v00, v11, v01);
}

void markPrevCellRed() {
  triangleVertexBuffer[g_triangleVertexCount-6].color = vec4(1.0, 0.0, 0.0, 1.0);
  triangleVertexBuffer[g_triangleVertexCount-5].color = vec4(1.0, 0.0, 0.0, 1.0);
  triangleVertexBuffer[g_triangleVertexCount-4].color = vec4(1.0, 0.0, 0.0, 1.0);
  triangleVertexBuffer[g_triangleVertexCount-3].color = vec4(1.0, 0.0, 0.0, 1.0);
  triangleVertexBuffer[g_triangleVertexCount-2].color = vec4(1.0, 0.0, 0.0, 1.0);
  triangleVertexBuffer[g_triangleVertexCount-1].color = vec4(1.0, 0.0, 0.0, 1.0);
}

#endif // _IMDRAW_GLSL_