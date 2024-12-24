
#define LINE_WIDTH 0.005

float f(float x) {
  uint segment = uint(x * 511.5);
  return audio.packedSamples[segment>>2][segment&3];
}

////////////////////////// COMPUTE SHADERS //////////////////////////

#ifdef IS_COMP_SHADER
#endif // IS_COMP_SHADER

////////////////////////// VERTEX SHADERS //////////////////////////

#ifdef IS_VERTEX_SHADER
layout(location = 0) out vec2 outScreenUv;

void VS_Test() {
  vec2 uv = VS_FullScreen();
  gl_Position = vec4(uv * 2.0 - 1.0, 0.0, 1.0);
  outScreenUv = uv;
}


void VS_SamplePlot() {
  uint sampleIdx = gl_InstanceIndex;

  vec2 samplePos;
  samplePos.x = sampleIdx / 512.0 / 4.0;
  samplePos.y = 0.5 + 2.0 * audio.packedSamples[sampleIdx>>2][sampleIdx&3];

  const float radius = LINE_WIDTH;

  vec2 vertPos = VS_Circle(gl_VertexIndex, samplePos, radius, SAMPLE_CIRCLE_VERTS);
  gl_Position = vec4(vertPos * 2.0f - 1.0f, 0.0f, 1.0f);
  outScreenUv = vertPos;
}

#endif // IS_VERTEX_SHADER

////////////////////////// PIXEL SHADERS //////////////////////////

#ifdef IS_PIXEL_SHADER
layout(location = 0) in vec2 inScreenUv;

layout(location = 0) out vec4 outColor;

void PS_Test() {
  outColor = 1.0.xxxx;

  // float y = 0.5 - inScreenUv.y;
  // float f_x = f(inScreenUv.x);
  // if (abs(y - f_x) < LINE_WIDTH)
  //   outColor.xyz = vec3(1.0, 0.0, 0.0);
}

void PS_SamplePlot() {
  outColor = vec4(1.0, 0.0, 0.0, 1.0);
}

#endif // IS_PIXEL_SHADER

