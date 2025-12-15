
#include "Lighting.glsl"
#include <Misc/Constants.glsl>
#include <Misc/Sampling.glsl>

vec3 computeDir(vec2 uv) {
	vec2 d = uv * 2.0 - 1.0;

	vec4 target = camera.inverseProjection * vec4(d, 1.0.xx);
	return (camera.inverseView * vec4(normalize(target.xyz), 0)).xyz;
}

uint gridToFlat(uint i, uint j) {
  return i * GRID_WIDTH + j;
}

vec2 gridToUv(uvec2 g) {
  return (vec2(g) + 0.5.xx) / vec2(GRID_WIDTH);
}

bool isInlet(vec2 uv) {
  float srcY = 0.5;
  float srcW = 0.025;
  return 
      uv.x < srcW && 
      uv.y < (srcY + srcW) && 
      uv.y > (srcY - srcW);
}

#ifdef IS_COMP_SHADER

void CS_Init() {
  uint indexIdx = 0;
  for (uint i = 0; i < GRID_WIDTH - 1; i++) {
    for (uint j = 0; j < GRID_WIDTH - 1; j++) {
      gridIndices[indexIdx++] = gridToFlat(i, j);
      gridIndices[indexIdx++] = gridToFlat(i+1, j+1);
      gridIndices[indexIdx++] = gridToFlat(i+1, j);

      gridIndices[indexIdx++] = gridToFlat(i, j);
      gridIndices[indexIdx++] = gridToFlat(i, j+1);
      gridIndices[indexIdx++] = gridToFlat(i+1, j+1);
    }
  }
}

void CS_InitHeight() {
  uvec2 g = uvec2(gl_GlobalInvocationID.xy);
  vec2 uv = gridToUv(g);
  float h = 2.0 / float(GRID_WIDTH);
  if (g.x >= GRID_WIDTH || g.y >= GRID_WIDTH) {
    return;
  }

  float height = -0.2 * uv.x;
  height += - 0.1 * sin(PI * uv.y);
  height += 0.005 * cos(53.0 * uv.x) * cos(23 * uv.y + 21.3);
  imageStore(HeightImage, ivec2(g), vec4(height, 0.0, 0.0, 1.0));
  imageStore(FlowFieldImage, ivec2(g), vec4(0.0.xxx, 1.0));
  imageStore(PrevFlowFieldImage, ivec2(g), vec4(0.0.xxx, 1.0));
}

void CS_UpdateFlow() {
  uvec2 g = uvec2(gl_GlobalInvocationID.xy);
  vec2 uv = gridToUv(g);
  float h = 2.0 / float(GRID_WIDTH);
  if (g.x >= GRID_WIDTH || g.y >= GRID_WIDTH) {
    return;
  }

  float DT = 1.0 / 30.0;

  // xy - velocity, z - river depth 
  vec3 prevFlow = texture(PrevFlowFieldTexture, uv).rgb;

  vec2 dv = 0.0.xx;
  if (!isInlet(uv)) {
    // dv += 0.9 * prevFlow.rg;
  }

  // compute height gradient
  vec2 hgrad;
  {
    vec2 hL = texture(HeightTexture, uv + vec2(-h, 0.0)).rg;
    vec2 hR = texture(HeightTexture, uv + vec2(h, 0.0)).rg;
    vec2 hD = texture(HeightTexture, uv + vec2(0.0, -h)).rg;
    vec2 hU = texture(HeightTexture, uv + vec2(0.0, h)).rg;

    vec3 pfL = texture(PrevFlowFieldTexture, uv + vec2(-h, 0.0)).rgb;
    vec3 pfR = texture(PrevFlowFieldTexture, uv + vec2(h, 0.0)).rgb;
    vec3 pfD = texture(PrevFlowFieldTexture, uv + vec2(0.0, -h)).rgb;
    vec3 pfU = texture(PrevFlowFieldTexture, uv + vec2(0.0, h)).rgb;
    // TODO decide what the 2nd comp in the heighttex represents

    hgrad = vec2(hR.x - hL.x, hU.x - hD.x);
    hgrad += vec2(pfR.z - pfL.z, pfU.z - pfD.z);
  }

  // TODO ...
  dv += - 10.0 * (VISC_MAX - VISC) * hgrad;
  vec2 backwardAdvectUv = uv - dv * DT;
  vec3 backwardFlow = texture(PrevFlowFieldTexture, backwardAdvectUv).rgb;
  
  float srcY = 0.5;
  float srcW = 0.025;
  if (isInlet(backwardAdvectUv)) {
    backwardFlow = vec3(INLET_SPEED, 0.0, INLET_HEIGHT);
  }

  vec3 flow = backwardFlow * vec3(0.9, 0.9, 0.999);
  if (flow.rgb != 0.0.xxx) 
    flow += vec3(dv, 0.0);
  
  imageStore(FlowFieldImage, ivec2(g), vec4(flow, 1.0));
}

void CS_UpdateHeight() {
  uvec2 g = uvec2(gl_GlobalInvocationID.xy);
  vec2 uv = gridToUv(g);
  if (g.x >= GRID_WIDTH || g.y >= GRID_WIDTH) {
    return;
  }

  // vec2 H = imageLoad(HeightImage, ivec2(g)).rg;
  // TODO ...
  // imageStore(HeightImage, ivec2(g), vec4(H, 0.0, 1.0));
}

void CS_CopyFlow() {
  uvec2 g = uvec2(gl_GlobalInvocationID.xy);
  if (g.x >= GRID_WIDTH || g.y >= GRID_WIDTH) {
    return;
  }

  vec2 uv = (vec2(g) + 0.5.xx) / vec2(GRID_WIDTH);
  vec3 s = texture(FlowFieldTexture, uv).rgb;
  imageStore(PrevFlowFieldImage, ivec2(g), vec4(s, 1.0));
}
#endif // IS_COMP_SHADER

#ifdef IS_VERTEX_SHADER
VertexOutput VS_Background() {
  VertexOutput OUT;
  OUT.uv = VS_FullScreen();
  return OUT;
}

GridVertex VS_Grid() {
  uvec2 g = uvec2(gl_VertexIndex / GRID_WIDTH, gl_VertexIndex % GRID_WIDTH);
  GridVertex OUT;
  OUT.uv = gridToUv(g);
  vec2 H = texture(HeightTexture, OUT.uv).rg;
  vec3 flow = texture(FlowFieldTexture, OUT.uv).rgb;
  OUT.pos = 50.0 * vec3(OUT.uv.x, H.x + H.y + flow.b, OUT.uv.y);
  gl_Position = camera.projection * camera.view * vec4(OUT.pos, 1.0);

  return OUT;
}
#endif // IS_VERTEX_SHADER

#ifdef IS_PIXEL_SHADER
void PS_Background(VertexOutput IN) {
  vec3 dir = computeDir(IN.uv);
  vec3 Li = sampleSky(dir);
  outColor = vec4(linearToSdr(Li), 1.0);
}

void PS_Grid(GridVertex IN) {
  // TODO smooth normals
  vec3 normal = normalize(cross(dFdy(IN.pos), dFdx(IN.pos)));
  vec3 V = normalize(IN.pos - camera.inverseView[3].xyz);
  vec3 flow = texture(FlowFieldTexture, IN.uv).rgb;
  bool isRiver = flow != 0.0.xxx;
  Material mat;
  mat.diffuse = isRiver ?
      vec3(0.2, 0.3, 0.8) :
      vec3(0.4, 0.55, 0.25);
  mat.roughness = isRiver ? 0.05 : 0.5;
  mat.emissive = 0.0.xxx;
  mat.metallic = 0.0;
  mat.specular = 0.03.xxx;

  vec3 Li = computeSurfaceLighting(mat, IN.pos, normal, V);

  vec3 col = linearToSdr(Li);
  if (SHOW_FLOW || (uniforms.inputMask & INPUT_BIT_F) != 0) {
    col = 0.01 * length(flow.rg).xxx;
  }
  outColor = vec4(col, 1.0);
}
#endif // IS_PIXEL_SHADER