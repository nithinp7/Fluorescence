
#include <Misc/Constants.glsl>

float getSample(uint segment) {
  return audio.packedSamples[segment>>2][segment&3];
}

float getCoeff(uint segment) {
  return abs(audio.packedCoeffs[segment>>2][segment&3]);
}

float f(float x) {
  uint segment = uint(x * 511.5);
  return getSample(segment);
}

////////////////////////// COMPUTE SHADERS //////////////////////////

#ifdef IS_COMP_SHADER
shared inputsShared[SAMPLE_COUNT];

void CS_DCT_II() {
  uint threadIdx = uint(gl_GlobalInvocationID.x);
  if (threadIdx >= DISPATCH_SIZE) {
    return;
  }

  uint localThreadIdx = uint(gl_SubgroupInvocationID);

  // load inputs to LDS
  for (uint i = localThreadIdx; i < SAMPLE_COUNT; i += DISPATCH_SIZE) {
    inputsShared[localThreadIdx] = getSample(i);
  }

  // flush LDS writes
  subgroupMemoryBarrier();

  for (uint i = 0; i < SAMPLE_COUNT; i += DISPATCH_SIZE) {
    float freqScale = PI / SAMPLE_COUNT * (i + 0.5);
    // for (uint j = 0; j < )
    // float c = cos(freqScale * uniforms.time)sdf
  }
}
#endif // IS_COMP_SHADER

////////////////////////// VERTEX SHADERS //////////////////////////

#ifdef IS_VERTEX_SHADER
layout(location = 0) out vec2 outScreenUv;

void VS_Test() {
  vec2 uv = VS_FullScreen();
  gl_Position = vec4(uv * 2.0 - 1.0, 0.0, 1.0);
  outScreenUv = uv;
}

void VS_FrequencyPlot() {
  uint sampleIdx = gl_InstanceIndex;

  vec2 pos;
  pos.x = float(sampleIdx) / SAMPLE_COUNT;// / 2048.0;//log2(float(sampleIdx)/2048.0);
  pos.y = 0.5;
  float h;
  if (MODE == 0)
    h = getSample(sampleIdx);
  else
    h = getCoeff(sampleIdx);

  h *= SCALE;

  vec2 vertPos = VS_Square(gl_VertexIndex, pos, vec2(1.0 / 512.0, max(h, 1.0 / 512.0)));
  gl_Position = vec4(vertPos * 2.0f - 1.0f, 0.0f, 1.0f);
  outScreenUv = vertPos;
}
#endif // IS_VERTEX_SHADER

////////////////////////// PIXEL SHADERS //////////////////////////

#ifdef IS_PIXEL_SHADER
layout(location = 0) in vec2 inScreenUv;

void PS_Test() {
  outColor = 1.0.xxxx;
}

void PS_SamplePlot() {
  outColor = vec4(1.0, 0.0, 0.0, 1.0);
}

#endif // IS_PIXEL_SHADER

