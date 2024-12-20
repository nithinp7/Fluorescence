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