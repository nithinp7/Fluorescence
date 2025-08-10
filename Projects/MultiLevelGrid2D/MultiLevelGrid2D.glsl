
#include "Bitfield.glsl"

#define GRID_SCALE 0.0625

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

  if (zoom == 0.0) zoom = 1.0;

  float dx = 0.5 * zoom;

  if (IS_PRESSED(W)) pan.y -= dx;
  if (IS_PRESSED(S)) pan.y += dx;
  if (IS_PRESSED(A)) pan.x += dx;
  if (IS_PRESSED(D)) pan.x -= dx;

  if (IS_PRESSED(Q)) zoom /= 1.05;
  if (IS_PRESSED(E)) zoom *= 1.05;
  
  float MIN_ZOOM = 0.5;
  float MAX_ZOOM = 10000.0;
  if (zoom < MIN_ZOOM) zoom = MIN_ZOOM;
  if (zoom > MAX_ZOOM) zoom = MAX_ZOOM;

  globalState[0].pan = pan;
  globalState[0].zoom = zoom;

  if (IS_PRESSED(LEFT_MOUSE)) {
    vec2 mousePos = screenToGrid(uniforms.mouseUv);
    setBitAtomicOr(int(mousePos.x), int(mousePos.y));
  }
}

#ifdef IS_COMP_SHADER
void CS_Update() {
  processInput();
}

void CS_ClearBlocks() {
  uint blockIdx = uint(gl_GlobalInvocationID.x);
  uvec4 v[2] = {uvec4(0), uvec4(0)};
  setBlock(0, blockIdx, v);
  setBlock(1, blockIdx, v);
  setBlock(2, blockIdx, v);
  setBlock(3, blockIdx, v);
}
#endif // IS_COMP_SHADER

#ifdef IS_VERTEX_SHADER
VertexOutput VS_Background() {
  VertexOutput OUT;
  OUT.color = vec4(1.0, 0.0, 0.0, 1.0);
  OUT.uv = VS_FullScreen();
  return OUT; 
}
#endif // IS_VERTEX_SHADER


#ifdef IS_PIXEL_SHADER
void PS_Background(VertexOutput IN) {
  vec2 gridPos = screenToGrid(IN.uv);
  ivec2 gridPosi = ivec2(gridPos);
  vec3 color = 0.025.xxx;
  if (getBit(0, gridPosi.x, gridPosi.y))
    color = vec3(0.85, 0.05, 0.05);
  else if (getBit(1, gridPosi.x >> 4, gridPosi.y >> 4))
    color = vec3(0.55, 0.85, 0.1);
  else if (getBit(2, gridPosi.x >> 8, gridPosi.y >> 8))
    color = vec3(0.15, 0.45, 0.35);

  outColor = vec4(color, 1.0);
}
#endif // IS_PIXEL_SHADER