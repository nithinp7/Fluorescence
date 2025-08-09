
#include "ImDraw.glsl"

#define IS_PRESSED(KEY) ((uniforms.inputMask & INPUT_BIT_##KEY) != 0)

void processInput() {
  vec2 pan = globalState[0].pan;
  float zoom = globalState[0].zoom;

  if (zoom == 0.0) zoom = 1.0;

  float dx = 0.5;

  if (IS_PRESSED(W)) pan.y -= dx;
  if (IS_PRESSED(S)) pan.y += dx;
  if (IS_PRESSED(A)) pan.x += dx;
  if (IS_PRESSED(D)) pan.x -= dx;

  if (IS_PRESSED(Q)) zoom /= 1.05;
  if (IS_PRESSED(E)) zoom *= 1.05;
  
  float MIN_ZOOM = 0.5;
  float MAX_ZOOM = 10.0;
  if (zoom < MIN_ZOOM) zoom = MIN_ZOOM;
  if (zoom > MAX_ZOOM) zoom = MAX_ZOOM;

  globalState[0].pan = pan;
  globalState[0].zoom = zoom;
}

vec2 gridToScreen(vec2 gridPos) {
  return (gridPos + globalState[0].pan) / globalState[0].zoom * GRID_SCALE + 0.5.xx;
}

void mark(vec2 v) {
  setColor(vec4(0.0.xxx, 1.0));
  float r = 0.005 * globalState[0].zoom / GRID_SCALE; // todo - probably need to fix after panning/zoom change
  addLine(v - r.xx, v + r.xx);
  addLine(v + vec2(-r, r), v + vec2(r, -r));
}

struct DDA {
  // input
  vec2 o; // ray origin
  vec2 d; // ray dir
  
  // precomputed
  ivec2 sn;
  vec2 invD;

  // state
  vec2 t; // time till next closest collision on each axis
  ivec2 coord; // current grid coord
  float globalT; // total time marched along ray
  uint level;
};

vec2 getCurrentPos(DDA dda) {
  return dda.o + dda.globalT * dda.d;
}

void switchLevelsDDA(inout DDA dda, uint level) {
  dda.level = level;
  uint subdivs = 1 << dda.level;
  // TODO - probably need rounding here somewhere
  vec2 p = dda.o + dda.globalT * dda.d;
  vec2 fr = fract(p/subdivs);
  vec2 rm = subdivs * mix(fr, max(1.0.xx - fr, 0.0.xx), greaterThan(dda.sn, ivec2(0)));
  dda.t = rm * dda.invD;
}

void trySwitchLevelsDDA(inout DDA dda, uint lastStepAxis, uint level) {
  if (dda.level == level)
    return;
  uint subdivs = 1 << level;
  int edgeCoord = dda.coord[lastStepAxis] - (dda.sn[lastStepAxis] - 1)/2;
  if ((edgeCoord & int(subdivs-1)) == 0) 
  {
    // kinda hacky - find a better way to track / handle this...
    // - basic problem is avoiding double intersection on line crossing during
    //   level switches...
    // - a regular DDA step picks the axis w smallest time-of-impact, subtracts the
    //   time from all candidate TOIs, and adds invD to the current axis's TOI
    // - after a level-switch, we have to not end up with t[axis] == 0, causing us
    //   to reprocess an intersection we already hit...

    // second problem - coord becomes incorrect after a down-step
    // local coord changes are not tracked on the  non-stepped axes during large steps
    // - 
    switchLevelsDDA(dda, level);
    dda.t[lastStepAxis] = subdivs * dda.invD[lastStepAxis];
    vec2 tmp = 0.0.xx;
    tmp[lastStepAxis] = dda.sn[lastStepAxis] * 0.00001;
    dda.coord = ivec2(getCurrentPos(dda) + tmp);
  }
}

DDA createDDA(vec2 o, vec2 d, uint initLevel) {
  DDA dda;
  dda.o = o;
  dda.d = d;
  
  dda.coord = ivec2(o);
  dda.sn = ivec2(sign(d));
  dda.invD = abs(1.0/d);
  dda.globalT = 0.0;
  switchLevelsDDA(dda, initLevel);

  return dda;
}

void stepDDA(inout DDA dda, inout uint stepAxis) {
  int subdivs = 1 << dda.level;
  stepAxis = (dda.t.x < dda.t.y) ? 0 : 1;
  // these steps are not accurate in the lower levels, but this is
  // rectified during the level-switch
  // would be nice to not have to retrace the last step...
  dda.coord[stepAxis] += subdivs * dda.sn[stepAxis];
  dda.globalT += dda.t[stepAxis];
  dda.t -= dda.t[stepAxis].xx;
  dda.t[stepAxis] = subdivs * dda.invD[stepAxis];
}

void raymarch() {
  drawGrid();

  vec2 o = vec2(POS_X, POS_Y);
  vec2 d = vec2(cos(RAY_ANGLE), sin(RAY_ANGLE));
  if (RAY_DBG == 0) drawRay(o, 400.0 * d);

  DDA dda = createDDA(o, d, LEVEL);
  for (int i = 0; i < 100; i++) {
    vec2 pos = getCurrentPos(dda);
    highlightGridCell(dda.coord, dda.level, HIGHLIGHT_MODE_FULL_CELL);
    // highlightGridCell(dda.coord, dda.level, HIGHLIGHT_MODE_CURRENT_COORD);
    mark(pos);
    uint subdivs = 1 << dda.level;
    if (RAY_DBG == 1) drawRay(pos, vec2(dda.coord/subdivs*subdivs)+(0.5.xx)*subdivs-pos);
    uint stepAxis;
    stepDDA(dda, stepAxis);
    if (i < 10)
      trySwitchLevelsDDA(dda, stepAxis, 0);
    else if (i < 20)
      trySwitchLevelsDDA(dda, stepAxis, 1);
    else if (i < 30)
      trySwitchLevelsDDA(dda, stepAxis, 2);
    else if (i < 45)
      trySwitchLevelsDDA(dda, stepAxis, 1);
    else if (i < 60)
      trySwitchLevelsDDA(dda, stepAxis, 0);
  }
}

#ifdef IS_COMP_SHADER
void CS_Update() {
  processInput();
  raymarch();
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
  v.pos = gridToScreen(v.pos);
  
  VertexOutput OUT;
  OUT.color = v.color;
  OUT.uv = vec2(v.pos.x, 1.0 - v.pos.y);
  gl_Position = vec4(OUT.uv * 2.0 - 1.0.xx, 0.0, 1.0);
  
  return OUT;
}

VertexOutput VS_Triangles() {
  Vertex v = triangleVertexBuffer[gl_VertexIndex];
  v.pos = gridToScreen(v.pos);
  
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