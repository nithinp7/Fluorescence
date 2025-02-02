
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

void CS_ComputeDivergence() {
  uint flatIdx = gl_GlobalInvocationID.x; 
  if (flatIdx >= CELLS_COUNT) {
    return;
  }

  computeDivergence(flatIdx);
}

void CS_ComputePressureA() {
  uint flatIdx = gl_GlobalInvocationID.x; 
  if (flatIdx >= CELLS_COUNT) {
    return;
  }

  computePressure(0, flatIdx);
}

void CS_ComputePressureB() {
  uint flatIdx = gl_GlobalInvocationID.x; 
  if (flatIdx >= CELLS_COUNT) {
    return;
  }

  computePressure(1, flatIdx);
}

void CS_ResolveVelocity() {
  uint flatIdx = gl_GlobalInvocationID.x; 
  if (flatIdx >= CELLS_COUNT) {
    return;
  }

  resolveVelocity(flatIdx);
}

void CS_AdvectColor() {
  uint flatIdx = gl_GlobalInvocationID.x; 
  if (flatIdx >= CELLS_COUNT) {
    return;
  }

  advectColor(flatIdx);
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
  uint flatIdx = coordToFlatIdx(uvec3(coord, CELLS_Z));
  if (RENDER_MODE == 0) {
    outColor = extraFields[flatIdx].color;
  } else if (RENDER_MODE == 1) {
    vec3 v = readVelocity(flatIdx);
    outColor = vec4(length(v).xxx / MAX_VELOCITY, 1.0);
  } else if (RENDER_MODE == 2) {
    outColor = vec4((100. * readDivergence(flatIdx) * 0.1).xxx, 1.0);
  } else {
    outColor = vec4(abs(readPressure(0, flatIdx)).xxx / MAX_PRESSURE, 1.0);
  }
}
#endif // IS_PIXEL_SHADER

