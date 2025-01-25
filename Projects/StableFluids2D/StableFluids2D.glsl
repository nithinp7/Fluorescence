
#include <Misc/Constants.glsl>
#include <Misc/Sampling.glsl>

#include "Simulation.glsl"

////////////////////////// COMPUTE SHADERS //////////////////////////

#ifdef IS_COMP_SHADER
void CS_HandleInput() {
  GlobalState state = globalStateBuffer[0];

  if ((uniforms.inputMask & INPUT_BIT_W) != 0) {
    state.pan.y -= 0.01 / state.zoom;
  }
  
  if ((uniforms.inputMask & INPUT_BIT_A) != 0) {
    state.pan.x -= 0.01 / state.zoom;
  }
  
  if ((uniforms.inputMask & INPUT_BIT_S) != 0) {
    state.pan.y += 0.01 / state.zoom;
  }
  
  if ((uniforms.inputMask & INPUT_BIT_D) != 0) {
    state.pan.x += 0.01 / state.zoom;
  }
  
  // TODO: zoom acceleration
  if ((uniforms.inputMask & INPUT_BIT_Q) != 0) {
    state.zoom /= 1.05;
  }

  if ((uniforms.inputMask & INPUT_BIT_E) != 0) {
    state.zoom *= 1.05;
  }

  if (state.zoom < 0.25) {
    state.zoom = 0.25;
  }

  state.initialized = state.initialized + 1;

  globalStateBuffer[0] = state;
}

void CS_InitVelocity() {
  uint flatIdx = gl_GlobalInvocationID.x; 
  if (flatIdx >= CELLS_COUNT) {
    return;
  }

  initVelocity(flatIdx);
}

void CS_AdvectVelocity() {
  uint flatIdx = gl_GlobalInvocationID.x; 
  if (flatIdx >= CELLS_COUNT) {
    return;
  }

  advectVelocity(flatIdx);
}
#endif // IS_COMP_SHADER

////////////////////////// VERTEX SHADERS //////////////////////////

#ifdef IS_VERTEX_SHADER
layout(location = 0) out vec2 outScreenUv;

void VS_Display() {
  vec2 pos = VS_FullScreen();
  gl_Position = vec4(pos * 2.0 - 1.0, 0.0, 1.0);
  outScreenUv = pos;
}

#endif // IS_VERTEX_SHADER

////////////////////////// PIXEL SHADERS //////////////////////////

#ifdef IS_PIXEL_SHADER
layout(location = 0) in vec2 inScreenUv;

layout(location = 0) out vec4 outColor;

void PS_Display() {
  uvec2 coord = uvec2(inScreenUv * vec2(CELLS_X, CELLS_Y) - 0.05.xx);
  uint flatIdx = coordToFlatIdx(coord);
  if (RENDER_MODE == 0) {
    outColor = extraFields[flatIdx].color;
  } else {
    vec2 v = readVelocity(flatIdx);
    // vec2 v = 500.0 * (vec2(coord) / vec2(CELLS_X, CELLS_Y) - 0.5.xx);//(2.0 * randVec2(seed) - 1.0.xx);// + 0.01 * jitter;
    // v = dequantizeVelocity(quantizeVelocity(v));
    outColor = vec4(0.5 * v / MAX_VELOCITY + 0.5.xx, 0.0, 1.0);
  }
}
#endif // IS_PIXEL_SHADER

