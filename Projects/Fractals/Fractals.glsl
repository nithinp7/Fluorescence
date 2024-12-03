
#include <Misc/Constants.glsl>
#include <Misc/Sampling.glsl>

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

  if (state.zoom < MIN_ZOOM) {
    state.zoom = MIN_ZOOM;
  }

  globalStateBuffer[0] = state;
}
#endif // IS_COMP_SHADER

////////////////////////// VERTEX SHADERS //////////////////////////

#ifdef IS_VERTEX_SHADER
layout(location = 0) out vec2 outScreenUv;

void VS_FractalDisplay() {
  vec2 pos = VS_FullScreen();
  gl_Position = vec4(pos * 2.0 - 1.0, 0.0, 1.0);
  outScreenUv = pos;
}

#endif // IS_VERTEX_SHADER

////////////////////////// PIXEL SHADERS //////////////////////////

#ifdef IS_PIXEL_SHADER
layout(location = 0) in vec2 inScreenUv;

layout(location = 0) out vec4 outColor;

void PS_FractalDisplay() {
  GlobalState state = globalStateBuffer[0];

  float zoom = 1.0;
  vec2 pan = vec2(-0.25, 0.05);

  const float ASPECT_RATIO = float(SCREEN_HEIGHT) / float(SCREEN_WIDTH);
  
  dvec2 c = inScreenUv * 2.0 - vec2(1.0);
  c /= state.zoom;
  c += state.pan;
  c.y *= ASPECT_RATIO;

  const uint MAX_ITERS = 128;
  vec2 avgItersBeforeJump = vec2(0.0);
  uint lastItersBeforeJump = 0;
  uint iters = 0;
  uint jumps = 0;
  dvec2 z = c;
  for (iters = 0; iters < MAX_ITERS; iters++) {
    z = dvec2(z.x * z.x - z.y * z.y + c.x, 2.0 * z.x * z.y + c.y);

    double zMag2 = dot(z, z);
    if (zMag2 > 1.0 || zMag2 < 0.1) {
      avgItersBeforeJump += vec2(float(iters - lastItersBeforeJump) / MAX_ITERS, 1.0);

      lastItersBeforeJump = iters;
      
      // uvec2 seed = uvec2(jumps - 1, jumps);
      // z += 0.01 * randVec2(seed);
      
      jumps++;
    }{
      // AHH!
      // z *= (0.7  + 0.19 * wave(2.0, iters + z.x));// * length(z);
      
      
      // large swirls
      // z *= (0.7  + 0.29 * wave(2.0, z.y * 2 + z.x));// * length(z);
      //(0.7  + 0.29 * wave(2.0, 0.0));// * length(z);

      
      if (zMag2 < 0.1) {
        uvec2 seed = uvec2(iters, jumps);
        // z *= 5.0 + 0.25 * wave(1.0 + 0.01 * z.y  + 0.01 * z.x, z.y * 2.0 + z.x);
      }
      // else
      // slow gentle wave
      float c = 0.01;
      // z *= 0.7 + 0.01 * wave(3.0  + c * z.y  + c * z.x, z.y * 0.1 + z.x);
      // z *= 0.7 + 0.01 * wave(3.0  + c * z.y  + c * z.x, z.y * 0.1 + z.x);
      z *= 0.7 + 0.01 * wave(TEST_SLIDER  + c * z.y  + c * z.x, z.y * 0.1 + z.x);
      // uvec2 seed = uvec2(jumps - 1, jumps);      
      // z += 0.0001 * (2.0 * randVec2(seed) - vec2(1.0));
      
      // z += 0.01 * randVec2(seed);
      // z *= 0.7 + 0.01 * wave(2.0  + 0.00 * (z.y  + z.x), 0.0 * (z.y * 2.0 + z.x));
      // z /= dot(z, z) + 0.1 * wave(2.0  + 0.00 * (z.y  + z.x), 0.0 * (z.y * 2.0 + z.x));
      // z.x += 0.01 * wave(4.0, z.x * z.x + z.y);
      // z.y += 0.01 * wave(2.0, z.y * z.x + z.x);
      // z *= (0.6  + 0.39 * wave(2.0, z.x + z.y));// * length(z);
      // z = 0.1 * vec2(z.x * z.x - z.y * z.y + c.x, 2.0 * z.x * z.y + c.y);
    }
  }

  float intensity = 0.2 * float(jumps);
  float colorTheta = 0.1 * jumps;
  float cosColor = 0.5 * cos(colorTheta) + 0.5;
  float sinColor = 0.5 * sin(colorTheta) + 0.5;

  // vec3 color = vec3(jumps, jumps, 0.1 * MAX_ITERS);
  vec3 color = 
      // vec3(avgItersBeforeJump.x / avgItersBeforeJump.y);
      vec3(
        intensity * cosColor, 
        colorTheta, 
        intensity * sinColor);
  color *= color;
  // if (iters == 0)
    
  color = vec3(1.0) - exp(-color * 0.05);
  vec3 color2 = color * color;
  vec3 color3 = color2 * color;
  color = -2 * color3 + 3 * color2;
  color *= color;
  // color = color / (vec3(1.0) + color);
  outColor = vec4(color, 1.0);
}
#endif // IS_PIXEL_SHADER

