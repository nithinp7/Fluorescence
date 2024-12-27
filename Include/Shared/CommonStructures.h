#ifndef _FLR_COMMON_STRUCTURES_
#define _FLR_COMMON_STRUCTURES_

#include <../Include/Althea/Common/CommonTranslations.h>

struct FlrUniforms {
  vec2 mouseUv;
  float time;
  uint frameCount;
  uint prevInputMask;
  uint inputMask;
};

struct PerspectiveCamera {
  mat4 view;
  mat4 inverseView;
  mat4 projection;
  mat4 inverseProjection;
};

struct AudioInput {
  vec4 packedSamples[512]; // TODO
  vec4 packedCoeffs[512];
};

struct FlrPush {
  uint push0;
  uint push1;
  uint push2;
  uint push3;
  uint push4;
  uint push5;
  uint push6;
  uint push7;
};
#endif // _FLR_COMMON_STRUCTURES_