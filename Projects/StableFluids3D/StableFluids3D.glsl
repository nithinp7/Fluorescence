
#include <Misc/Constants.glsl>
#include <Misc/Sampling.glsl>

#include "Simulation.glsl"

float phaseFunction(float cosTheta, float g) {
  float g2 = g * g;
  return  
      3.0 * (1.0 - g2) * (1.0 + cosTheta * cosTheta) / 
      (8 * PI * (2.0 + g2) * pow(1.0 + g2 - 2.0 * g * cosTheta, 1.5));
}


// TODO move into some sort of utilities...
vec3 computeDir(vec2 uv) {
	vec2 d = uv * 2.0 - 1.0;

	vec4 target = camera.inverseProjection * vec4(d, 1.0.xx);
	return (camera.inverseView * vec4(normalize(target.xyz), 0)).xyz;
}

vec3 sampleEnv(vec3 dir) {
  float c = 5.0;
  vec3 n = 0.5 * normalize(dir) + 0.5.xxx;
  if (BACKGROUND == 0) {
    float cosphi = cos(LIGHT_PHI); float sinphi = sin(LIGHT_PHI);
    float costheta = cos(LIGHT_THETA); float sintheta = sin(LIGHT_THETA);
    float x = 0.5 + 0.5 * dot(dir, normalize(vec3(costheta * cosphi, sinphi, sintheta * cosphi)));
    x = pow(x, 10.0) + 0.01;
    return LIGHT_STRENGTH * x * round(n * c) / c;
  } else if (BACKGROUND == 1) {
    return round(fract(n * c));
  } else if (BACKGROUND == 2) {
    return round(n);
  } else {
    float f = n.x + n.y + n.z;
    return max(round(fract(f * c)), 0.2).xxx;
  }
}

vec3 sampleDensityField(vec3 pos) {
  // float d = length(bilerpFields(mod(pos, vec3(CELLS_X, CELLS_Y, CELLS_X))).fields.color.rgb);
  if (pos.x < 0.0 || pos.x > CELLS_X ||
      pos.y < 0.0 || pos.y > CELLS_Y ||
      pos.z < 0.0 || pos.z > CELLS_Z)
    return 0.0.xxx;
  pos.y = CELLS_Y - pos.y;
  vec3 d = (bilerpFields(pos).fields.color.rgb);
  if (length(d) < DENSITY_CUTOFF)
    return 0.0.xxx;
  return 1.0 / d;
}

vec3 raymarch_pathTraceEnv(vec3 pos, vec3 dir, inout uvec2 seed) {
  vec3 lpos = vec3(CELLS_X, CELLS_Y, CELLS_Z) * vec3(cos(LIGHT_THETA), 1.0, sin(LIGHT_THETA));
  vec3 outLight = 0.0.xxx;
  float depth = 0.0;
  vec3 throughput = 1.0.xxx;
  vec3 accumDensity = 0.0.xxx;
  for (uint iter = 0; iter < RAYMARCH_ITERS; iter++) {
    depth += RAYMARCH_STEP_SIZE;
    vec3 samplePos = pos + dir * depth;
    vec3 density = sampleDensityField(samplePos);

    seed += uvec2(iter, iter + 1);
    vec3 lightRayPos = samplePos;
    vec3 lightDir = normalize(randVec3(seed) - 0.5.xxx);
    float lightStepSize = RAYMARCH_STEP_SIZE;//lightDist / LIGHT_ITERS;
    vec3 lightThroughput = 1.0.xxx;

    // jitter
    lightRayPos += lightStepSize * rng(seed) * lightDir;
    for (uint lightIter = 0; lightIter < LIGHT_ITERS; lightIter++) {
      lightRayPos += lightDir * lightStepSize;
      vec3 lightSampleDensity = sampleDensityField(lightRayPos);
      lightThroughput *= exp(-lightSampleDensity * DENSITY_MULT * lightStepSize);
    }
    if (length(density) > 0.0)
      outLight += 
          phaseFunction(dot(lightDir, dir), G) *
          sampleEnv(lightDir) * lightThroughput * throughput;
    throughput *= exp(-density * DENSITY_MULT * RAYMARCH_STEP_SIZE);
  }

  return sampleEnv(dir) * throughput + outLight;
}

vec3 raymarch_directLight(vec3 pos, vec3 dir, inout uvec2 seed) {
  vec3 lpos = vec3(CELLS_X, CELLS_Y, CELLS_Z) * vec3(cos(LIGHT_THETA), 1.0, sin(LIGHT_THETA));
  vec3 outLight = 0.0.xxx;
  float depth = 0.0;
  vec3 throughput = 1.0.xxx;
  vec3 accumDensity = 0.0.xxx;
  for (uint iter = 0; iter < RAYMARCH_ITERS; iter++) {
    depth += RAYMARCH_STEP_SIZE;
    vec3 samplePos = pos + dir * depth;
    vec3 density = sampleDensityField(samplePos);

    vec3 lightRayPos = samplePos;
    vec3 lightDir = lpos - lightRayPos;
    float lightDist2 = dot(lightDir, lightDir);
    float lightDist = sqrt(lightDist2);
    float lightStepSize = RAYMARCH_STEP_SIZE;//lightDist / LIGHT_ITERS;
    lightDir /= lightDist;
    vec3 lightThroughput = 1.0.xxx;

    // jitter
    lightRayPos += lightStepSize * rng(seed) * lightDir;
    for (uint lightIter = 0; lightIter < LIGHT_ITERS; lightIter++) {
      lightRayPos += lightDir * lightStepSize;
      vec3 lightSampleDensity = sampleDensityField(lightRayPos);
      lightThroughput *= exp(-lightSampleDensity * DENSITY_MULT * lightStepSize);
    }
    if (length(density) > 0.0)
      outLight += 
          phaseFunction(dot(lightDir, dir), G) *
          vec3(LIGHT_STRENGTH / lightDist2) * lightThroughput * throughput;
    throughput *= exp(-density * DENSITY_MULT * RAYMARCH_STEP_SIZE);
  }

  return sampleEnv(dir) * throughput + outLight;
}

// without light steps
vec3 raymarch2(vec3 pos, vec3 dir, inout uvec2 seed) {
  float depth = 0.0;
  vec3 throughput = 1.0.xxx;
  vec3 accumDensity = 0.0.xxx;
  for (uint iter = 0; iter < RAYMARCH_ITERS; iter++) {
    depth += RAYMARCH_STEP_SIZE;
    vec3 samplePos = pos + dir * depth;
    vec3 density = sampleDensityField(samplePos);
    throughput *= exp(-density * DENSITY_MULT * RAYMARCH_STEP_SIZE);
  }

  return sampleEnv(dir) * throughput;
}

////////////////////////// COMPUTE SHADERS //////////////////////////

#ifdef IS_COMP_SHADER
void CS_HandleInput() {
  GlobalState state = globalStateBuffer[0];
  state.initialized = state.initialized + 1;
  if ((uniforms.inputMask & INPUT_BIT_SPACE) == 0)
    state.accumulationFrames = 1;
  else
    state.accumulationFrames += 1;
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

void CS_PathTrace() {
  if (RENDER_MODE != 0)
    return;
  
  uvec2 pixelCoord = uvec2(gl_GlobalInvocationID.xy);
  if (pixelCoord.x >= SCREEN_WIDTH || pixelCoord.y >= SCREEN_HEIGHT) {
    return;
  }

  vec4 prevColor = imageLoad(accumulationBuffer, ivec2(pixelCoord));

  uvec2 seed = pixelCoord * uvec2(uniforms.frameCount, uniforms.frameCount + 1);
  
  vec2 uv = vec2(pixelCoord) / vec2(SCREEN_WIDTH, SCREEN_HEIGHT);
  vec3 dir = normalize(computeDir(uv));
  vec3 pos = camera.inverseView[3].xyz;
// RAYMARCH_STEP_SIZE * rng(jitterSeed)
  vec4 color = vec4(raymarch_pathTraceEnv(pos + RAYMARCH_STEP_SIZE * rng(seed) * dir, dir, seed), 1.0);
  if (false)
  {
    color.rgb *= 0.5;
    color.rgb += 0.5 * raymarch_pathTraceEnv(pos + RAYMARCH_STEP_SIZE * rng(seed) * dir, dir, seed);
  }

  color.rgb = mix(prevColor.rgb, color.rgb, 1.0 / globalStateBuffer[0].accumulationFrames);
  imageStore(accumulationBuffer, ivec2(pixelCoord), color);
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
  if (RENDER_MODE == 0) {
    outColor = vec4(texture(accumulationTexture, inScreenUv).rgb, 1.0);
    outColor.rgb = vec3(1.0) - exp(-outColor.rgb * 0.8);
  } else if (RENDER_MODE == 1) {
    vec3 dir = (normalize(computeDir(inScreenUv)));
    vec3 pos = (camera.inverseView[3].xyz);

    uvec2 jitterSeed = uvec2(inScreenUv * vec2(SCREEN_WIDTH, SCREEN_HEIGHT));
    pos += RAYMARCH_STEP_SIZE * rng(jitterSeed) * dir;

    outColor = vec4(raymarch_directLight(pos, dir, jitterSeed), 1.0);
    outColor.rgb = vec3(1.0) - exp(-outColor.rgb * 0.8);
  } else {
    uvec2 coord = uvec2(inScreenUv * vec2(CELLS_X, CELLS_Y) - 0.05.xx);
    uint flatIdx = coordToFlatIdx(uvec3(coord, SLICE_IDX));
    if (RENDER_MODE == 2) {
      outColor = 10.0 * extraFields[flatIdx].color;
    } else if (RENDER_MODE == 3) {
      vec3 v = readVelocity(flatIdx);
      outColor = vec4(length(v).xxx / MAX_VELOCITY, 1.0);
    } else if (RENDER_MODE == 4) {
      outColor = vec4((100. * readDivergence(flatIdx) * 0.1).xxx, 1.0);
    } else {
      outColor = vec4(abs(readPressure(0, flatIdx)).xxx / MAX_PRESSURE, 1.0);
    }
  }
}
#endif // IS_PIXEL_SHADER

