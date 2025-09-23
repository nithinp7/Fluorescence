
#include "ImDraw.glsl"

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

int computeSubdivs(uint level) {
  return 1 << (BR_FACTOR_LOG2 * level);
}

void switchLevelsDDA(inout DDA dda, uint level) {
  dda.level = level;
  uint subdivs = computeSubdivs(dda.level);
  // TODO - probably need rounding here somewhere
  vec2 p = dda.o + dda.globalT * dda.d;
  vec2 fr = fract(p/subdivs);
  vec2 rm = subdivs * mix(fr, max(1.0.xx - fr, 0.0.xx), greaterThan(dda.sn, ivec2(0)));
  dda.t = rm * dda.invD;
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
  int subdivs = computeSubdivs(dda.level);
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
  vec2 o = globalState[0].rayOrigin;
  float theta = globalState[0].rayAngle;
  vec2 d = vec2(cos(theta), sin(theta));

  bool bPrevHit = false;

  DDA dda = createDDA(o, d, NUM_LEVELS-1);
  uint stepAxis = 0;
  vec2 prevPos = o;
  for (int i = 0; i < 1000; i++) {
    bool bHit = false;

    int subdivs = computeSubdivs(dda.level);
    if (RAY_DBG == 1) 
      drawRay(prevPos, vec2(dda.coord/subdivs*subdivs)+(0.5.xx)*subdivs-prevPos);
    ivec2 coord = dda.coord / subdivs;
    if (getBit(dda.level, coord.x, coord.y)) {
      if (dda.level == 0) {
        bHit = true;
      } else {
        vec2 dx = 0.0.xx;
        dx[stepAxis] = dda.sn[stepAxis] * 0.0001;
        dda = createDDA(getCurrentPos(dda) + dx, d, dda.level-1);
      }
    } else if (
        dda.level < (NUM_LEVELS - 1) &&
        !getBit(dda.level+1, coord.x  >> BR_FACTOR_LOG2, coord.y >> BR_FACTOR_LOG2)) {
          
      vec2 dx = 0.0.xx;
      dx[stepAxis] = dda.sn[stepAxis] * 0.0001;
      dda = createDDA(getCurrentPos(dda) + dx, d, dda.level+1);
    } else {
      stepDDA(dda, stepAxis);
    }
    
    vec2 pos = getCurrentPos(dda);
    mark(pos);
    setColor(vec4(0.45, 0.01, 0.05, 1.0));
    addLine(prevPos, pos);
    prevPos = pos;

    if (bHit)
      break;
  }
}