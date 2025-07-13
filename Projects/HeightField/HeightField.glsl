#include <Misc/Sampling.glsl>

uint getCellIdx(uint i, uint j) {
  return j * GRID_LEN + i;
}

uvec2 getCellCoord(uint idx) {
  return uvec2(idx % GRID_LEN, idx / GRID_LEN);
}

vec3 getCellPos(uint i, uint j) {
  uint idx = getCellIdx(i, j);
  float spacing = 0.1;
  return vec3(spacing * i, cellBuffer[idx].height, spacing * j);
}

vec3 computeDir(vec2 uv) {
	vec2 d = uv * 2.0 - 1.0;

	vec4 target = camera.inverseProjection * vec4(d, 1.0.xx);
	return (camera.inverseView * vec4(normalize(target.xyz), 0)).xyz;
}

vec3 sampleEnv(vec3 dir) {
  float c = 5.0;
  vec3 n = 0.5 * normalize(dir) + 0.5.xxx;
  return 0.1 * round(n * c) / c;
}

#ifdef IS_COMP_SHADER
void CS_Init() {
  uint threadId = uint(gl_GlobalInvocationID.x);
  if (threadId >= GRID_CELLS)
    return;

  uvec2 seed = uvec2(threadId, threadId+1);
  cellBuffer[threadId].height = rng(seed);
}
#endif // IS_COMP_SHADER

#ifdef IS_VERTEX_SHADER
VertexOutput VS_Background() {
  VertexOutput OUT;
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
  gl_Position = camera.projection * camera.view * vec4(pos, 1.0);

  VertexOutput OUT;
  OUT.vertColor = vec4(fract(pos), 1.0);
  return OUT;
}
#endif // IS_VERTEX_SHADER

#ifdef IS_PIXEL_SHADER
void PS_Background(VertexOutput IN) {
  outColor = vec4(sampleEnv(computeDir(IN.uv)), 1.0);
}

void PS_HeightField(VertexOutput IN) {
  outColor = IN.vertColor;
}
#endif // IS_PIXEL_SHADER
