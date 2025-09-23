
#include "Bitfield.glsl"
#include "ImDraw.glsl"

#define GRID_SCALE 0.0625

void mark(vec2 v) {
  setColor(vec4(0.0.xxx, 1.0));
  float r = 0.005 * globalState[0].zoom / GRID_SCALE; 
  addLine(v - r.xx, v + r.xx);
  addLine(v + vec2(-r, r), v + vec2(r, -r));
}

#include "HDDA.glsl"

vec2 gridToScreen(vec2 gridPos) {
  vec2 uv = (gridPos + globalState[0].pan) / globalState[0].zoom * GRID_SCALE + 0.5.xx;
  uv.y = 1.0 - uv.y;
  return uv;
}

vec2 screenToGrid(vec2 uv) {
  uv.y = 1.0 - uv.y;
  return (uv - 0.5.xx) / GRID_SCALE * globalState[0].zoom - globalState[0].pan;
}

#define IS_PRESSED(KEY) ((uniforms.inputMask & INPUT_BIT_##KEY) != 0)

void processInput() {
  vec2 pan = globalState[0].pan;
  float zoom = globalState[0].zoom;

  vec2 rayOrigin = globalState[0].rayOrigin;
  float rayAngle = globalState[0].rayAngle;

  if (zoom == 0.0) zoom = 1.0;

  float dx = 0.05 * zoom;

  if (IS_PRESSED(W)) pan.y -= dx;
  if (IS_PRESSED(S)) pan.y += dx;
  if (IS_PRESSED(A)) pan.x += dx;
  if (IS_PRESSED(D)) pan.x -= dx;
  
  if (IS_PRESSED(Q)) zoom /= 1.05;
  if (IS_PRESSED(E)) zoom *= 1.05;
  
  if (IS_PRESSED(I)) rayOrigin.y += dx;
  if (IS_PRESSED(K)) rayOrigin.y -= dx;
  if (IS_PRESSED(J)) rayOrigin.x -= dx;
  if (IS_PRESSED(L)) rayOrigin.x += dx;

  if (IS_PRESSED(U)) rayAngle += 0.01;
  if (IS_PRESSED(O)) rayAngle -= 0.01;

  float MIN_ZOOM = 0.5;
  float MAX_ZOOM = 10000.0;
  if (zoom < MIN_ZOOM) zoom = MIN_ZOOM;
  if (zoom > MAX_ZOOM) zoom = MAX_ZOOM;

  globalState[0].pan = pan;
  globalState[0].zoom = zoom;

  globalState[0].rayOrigin = rayOrigin;
  globalState[0].rayAngle = rayAngle;

  vec2 mousePos = screenToGrid(uniforms.mouseUv);
  mark(mousePos);
  if (IS_PRESSED(LEFT_MOUSE)) {
    setBitAtomicOr(int(mousePos.x), int(mousePos.y));
  }
}

#ifdef IS_COMP_SHADER
void CS_Update() {
  processInput();
  raymarch();
  finishLines();
  finishTriangles();
}

void CS_ClearBlocks() {
  uint blockIdx = uint(gl_GlobalInvocationID.x);
  uvec4 v[2] = {uvec4(0), uvec4(0)};
  setBlock(blockIdx, v);
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
  
  VertexOutput OUT;
  OUT.color = v.color;
  OUT.uv = gridToScreen(v.pos);
  gl_Position = vec4(OUT.uv * 2.0 - 1.0.xx, 0.0, 1.0);
  
  return OUT;
}

VertexOutput VS_Triangles() {
  Vertex v = triangleVertexBuffer[gl_VertexIndex];
  
  VertexOutput OUT;
  OUT.color = v.color;
  OUT.uv = gridToScreen(v.pos);
  gl_Position = vec4(OUT.uv * 2.0 - 1.0.xx, 0.0, 1.0);
  
  return OUT;
}
#endif // IS_VERTEX_SHADER


#ifdef IS_PIXEL_SHADER
void PS_Background(VertexOutput IN) {
  vec2 gridPos = screenToGrid(IN.uv);
  ivec2 gridPosi = ivec2(gridPos);
  vec3 color = 0.025.xxx;
  for (uint level = 0; level < NUM_LEVELS; level++) {
    uvec2 seed = uvec2(level, level+1);
    if (getBit(level, gridPosi.x, gridPosi.y)) {
      color = randVec3(seed);
      break;
    }
    gridPosi >>= BR_FACTOR_LOG2;
  }

  outColor = vec4(color, 1.0);
}

void PS_Triangles(VertexOutput IN) {
  outColor = IN.color;
}

void PS_Lines(VertexOutput IN) {
  outColor = IN.color;
}
#endif // IS_PIXEL_SHADER