#include "Lighting.glsl"

uint getCellIdx(uint i, uint j) {
  return j * GRID_LEN + i;
}

uvec2 getCellCoord(uint idx) {
  return uvec2(idx % GRID_LEN, idx / GRID_LEN);
}

vec3 getCellPos(uint i, uint j) {
  uint idx = getCellIdx(i, j);
  return vec3(GRID_SPACING * i, cellBuffer[idx], GRID_SPACING * j);
}

vec3 getCellNormal(uint i, uint j) {
  return cellNormals[getCellIdx(i, j)].xyz;
}

#ifdef IS_COMP_SHADER
void CS_Update() {
  uvec2 g = uvec2(gl_GlobalInvocationID.xy);
  if (g.x >= GRID_LEN || g.y >= GRID_LEN)
    return;

  // vec2 uv = (vec2(g) + 0.5.xx) / vec2(GRID_LEN.xx);
  vec2 pstart = 2.0 * (vec2(g) + 0.5.xx) / vec2(GRID_LEN.xx) - 1.0.xx; 
  float height = 0.0;
  mat2 m[3];
  mat2 dm[3];
  vec2 p[3];
  float theta = TURB_ROT;
  for (int i=0; i<3; i++) {
    p[i] = pstart;
    float c = cos(theta), s = sin(theta);
    dm[i] = mat2(c, s, -s, c);
    m[i] = dm[i];
    theta *= 1.3;
  }
  float freq = TURB_FREQ;
  for (int i=0; i<10; i++) {
    vec2 uv[3];
    for (int j=0; j<3; j++) {
      float phase = freq * (p[j] * m[j]).y + globalState[0].phaseOffset ;//+ i;
      p[j] += TURB_AMP * m[j][0] * sin(phase) / freq;
      uv[j] = fract(0.5 * p[j] + 0.5.xx + globalState[0].uvOffset);
      m[j] *= dm[j];
    }
    height += NOISE_SCALE * NOISE_LEVEL0 * texture(Worley8x8, uv[0]).r;
    height += NOISE_SCALE * NOISE_LEVEL1 * texture(Worley16x16, uv[1]).r;
    height += NOISE_SCALE * NOISE_LEVEL2 * texture(Worley32x32, uv[2]).r;
    freq *= TURB_EXP;
  }
  // height = NOISE_SCALE * (uv.x + 5.5 * uv.y * uv.y);
  cellBuffer[getCellIdx(g.x, g.y)] = height;
}

void CS_GenNormals() {
  // TODO should be able to infer normals directly from 
  // complementary noise normals texture...
  uvec2 g = uvec2(gl_GlobalInvocationID.xy);
  if (g.x >= GRID_LEN || g.y >= GRID_LEN)
    return;
  
  if (g.x == 0 && g.y == 0) {
    float dt = uniforms.time - globalState[0].lastTime;
    globalState[0].uvOffset += vec2(MEAN_FLOW_X, MEAN_FLOW_Y) * dt;
    globalState[0].phaseOffset += TURB_SPEED * dt;
    globalState[0].lastTime = uniforms.time;
  }

  vec3 normal = 0.0.xxx;
  for (uint i = 0; i <= 1; i++) for (uint j = 0; j <= 1; j++) {
    uvec2 c = g + uvec2(i, j);
    if (c.x > 0 && c.x < GRID_LEN && c.y > 0 && c.y < GRID_LEN) {
      vec3 v00 = getCellPos(c.x - 1, c.y - 1);
      vec3 v10 = getCellPos(c.x, c.y - 1);
      vec3 v01 = getCellPos(c.x - 1, c.y);
      vec3 v11 = getCellPos(c.x, c.y);
      normal += cross(v10 - v00, v11 - v00);
      normal += cross(v11 - v00, v01 - v00);      
    }
  }
  float n2 = dot(normal, normal);
  // if (n2 < 0.01)
  //   normal += vec3(0.0, 0.1, 0.0);
  cellNormals[getCellIdx(g.x, g.y)] = vec4(normalize(normal), 0.0);
}
#endif // IS_COMP_SHADER

#ifdef IS_VERTEX_SHADER
PostFxVertex VS_PostFX() {
  return PostFxVertex(VS_FullScreen());
}

VertexOutput VS_Background() {
  VertexOutput OUT;
  OUT.pos = 0.0.xxx;
  OUT.normal = 0.0.xxx;
  OUT.uv = VS_FullScreen();
  return OUT;
}

VertexOutput VS_HeightField() {
  uint cellIdx = gl_VertexIndex / 6;
  uint cellX = cellIdx % (GRID_LEN - 1);
  uint cellY = cellIdx / (GRID_LEN - 1);
  uint localIdx = gl_VertexIndex % 6;
  if (localIdx == 1 || localIdx == 2 || localIdx == 4)
    cellY++;
  if (localIdx == 2 || localIdx == 4 || localIdx == 5)
    cellX++;
  
  vec3 pos = getCellPos(cellX, cellY);
  vec4 screenPos = camera.projection * camera.view * vec4(pos, 1.0);
  gl_Position = screenPos;

  VertexOutput OUT;
  OUT.pos = pos;
  OUT.normal = getCellNormal(cellX, cellY);
  OUT.uv = screenPos.xy / screenPos.w * 0.5 + 0.5.xx;
  return OUT;
}

void VS_ShadowHeightField() {
  VertexOutput OUT = VS_HeightField();
  gl_Position = worldToShadowSpace(OUT.pos);
}

VertexOutput VS_Skirts() {
  const uint vertsPerSide = (GRID_LEN - 1) * 6;
  uint side = gl_VertexIndex / vertsPerSide;
  uint segmentIdx = (gl_VertexIndex % vertsPerSide) / 6;
  uint localIdx = gl_VertexIndex % 6;
  uint lockedIdx = (side < 2) ? 0 : (GRID_LEN - 1);
  uvec2 c0 = uvec2(segmentIdx, lockedIdx);
  uvec2 c1 = uvec2(segmentIdx+1, lockedIdx);
  vec3 normal = 0.0.xxx;
  normal[side&1] = (side < 2) ? -1.0 : 1.0;
  if ((side&1) == 1) {
    c0 = c0.yx;
    c1 = c1.yx;
  }
  vec3 p[4];
  p[0] = p[2] = getCellPos(c0.x, c0.y);
  p[1] = p[3] = getCellPos(c1.x, c1.y);
  const float skirtBottomY = -20.0;
  p[2].y = p[3].y = skirtBottomY;

  uint indices[6] = {0, 1, 2, 1, 3, 2};
  vec3 pos = p[indices[localIdx]];
  vec4 screenPos = camera.projection * camera.view * vec4(pos, 1.0);
  gl_Position = screenPos;

  VertexOutput OUT;
  OUT.pos = pos;
  OUT.normal = normal;
  OUT.uv = screenPos.xy / screenPos.w * 0.5 + 0.5.xx;
  return OUT;
}

void VS_ShadowSkirts() {
  VertexOutput OUT = VS_Skirts();
  gl_Position = worldToShadowSpace(OUT.pos);
}
#endif // IS_VERTEX_SHADER

#ifdef IS_PIXEL_SHADER
// kinda hacky
#if defined(_ENTRY_POINT_PS_Shadow)
void PS_Shadow() {}
#else // if !shadow
void PS_Background(VertexOutput IN) {
  vec3 dir = computeDir(IN.uv);
  vec3 col = sampleSky(dir);

  if (DEBUG_MODE == 3)
  {
    float shadowDepthSample = texture(shadowMapTexture, IN.uv).r;
    float shadowBias = 0.001;
    col = fract(shadowDepthSample.xxx);
  }
  outColor = vec4(col, 1.0);
}

void PS_HeightField(VertexOutput IN) {
  vec3 dir = computeDir(IN.uv);
  IN.normal = -normalize(IN.normal);

  Material mat;
  mat.diffuse = vec3(0.4, 0.55, 0.25);
  mat.roughness = 0.2;
  mat.emissive = 0.0.xxx;
  mat.metallic = 0.0;
  mat.specular = 0.03.xxx;

  uvec2 seed = uvec2(IN.uv * vec2(GRID_LEN.xx)) * uvec2(uniforms.frameCount, uniforms.frameCount+1);
  vec3 viewDir = normalize(IN.pos - camera.inverseView[3].xyz);
  vec3 Li = computeSurfaceLighting(seed, mat, IN.pos, IN.normal, viewDir);
  outColor = vec4(Li, 1.0);
  
  if (DEBUG_MODE == 1) {
    outColor = vec4(IN.normal * 0.5 + 0.5.xxx, 1.0);
  } else if (DEBUG_MODE == 2) {
    outColor = vec4(fract(IN.pos), 1.0);
  }
}

void PS_PostFX(PostFxVertex IN) {
  if (!ENABLE_POSTFX) {
    vec3 col = texture(ColorTexture, IN.uv).rgb;
    outColor = vec4(linearToSdr(col), 1.0);
    return;
  }

  vec2 dims = vec2(SCREEN_WIDTH, SCREEN_HEIGHT);
  uvec2 seed = uvec2(IN.uv * dims);
  if (VARY_POSTFX_NOISE) 
    seed *= uvec2(uniforms.frameCount, uniforms.frameCount + 1);
  else
    seed *= uvec2(23, 27);

  uint postFxSampleCount = min(POSTFX_SAMPLES, MAX_POSTFX_SAMPLES);

  vec3 col = 0.0.xxx;
  for (int i=0; i<postFxSampleCount; i++) {
    float R = POSTFX_R;
    vec2 x = randVec2(seed);
    vec2 r = R * (x - 0.5.xx);
    float invStdDev = 1.0 / POSTFX_STDEV;
    float pdf = R * R * invStdDev * exp(-0.5 * dot(r, r) * invStdDev * invStdDev) / sqrt(2.0 * PI); // todo correct ??
    // TODO importance sample...
    vec2 uv = IN.uv + (r + 0.5.xx) / dims;
    col += texture(ColorTexture, uv).rgb / pdf / postFxSampleCount;
  }
  
  outColor = vec4(linearToSdr(col), 1.0);
}
#endif // !shadow
#endif // IS_PIXEL_SHADER
