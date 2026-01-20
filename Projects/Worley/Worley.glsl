#include <Misc/Sampling.glsl>

uint gridToFlat(uvec2 g) {
  return g.y * WORLEY_GRID_DIM + g.x;
}

#ifdef IS_COMP_SHADER
void CS_InitSeeds() {
  uvec2 g = uvec2(gl_GlobalInvocationID.xy);
  if (g.x >= WORLEY_GRID_DIM || g.y >= WORLEY_GRID_DIM) {
    return;
  }

  uvec2 seed = g * uvec2(GEN_SEED, GEN_SEED+1);
  vec2 gf = vec2(g) + randVec2(seed);
  worleySeeds[gridToFlat(g)] = gf; 
}

void CS_Worley() {
  uvec2 coord = uvec2(gl_GlobalInvocationID.xy);
  if (coord.x >= OUT_IMAGE_WIDTH || coord.x >= OUT_IMAGE_WIDTH) {
    return;
  }

  float noise = 10000.0;

  vec2 uv = (vec2(coord) + 0.5.xx) / vec2(OUT_IMAGE_WIDTH.xx);
  vec2 gf = uv * WORLEY_GRID_DIM;
  uvec2 g = uvec2(gf);
  // vec2 fr = gf - vec2(g);
  // TODO: optimize to only check 4 instead of 9 cells
  for (int i = -1; i <= 1; i++) for (int j = -1; j <= 1; j++) {
    ivec2 g1 = ivec2(g) + ivec2(i, j);
    ivec2 c = (g1 + ivec2(WORLEY_GRID_DIM)) % ivec2(WORLEY_GRID_DIM);
    if (c.x >= 0 && c.y >= 0 && c.x < WORLEY_GRID_DIM && c.y < WORLEY_GRID_DIM) {
      vec2 seedPos = worleySeeds[gridToFlat(uvec2(c))];
      float r = length(fract(seedPos) + vec2(g1) - gf);
      if (r < noise)
         noise = r;
    }
  }

  imageStore(WorleyImage, ivec2(coord), vec4(noise, 0.0, 0.0, 1.0));
}
#endif // IS_COMP_SHADER

#ifdef IS_VERTEX_SHADER
VertexOutput VS_Worley() {
  return VertexOutput(VS_FullScreen());
}
#endif // IS_VERTEX_SHADER

#ifdef IS_PIXEL_SHADER
void PS_Worley(VertexOutput IN) {
  // test tileable...
  vec2 offs = 0.0.xx; //0.25 * sin(uniforms.time).xx;
  vec2 uv = fract(IN.uv + offs);
  float noise = texture(WorleyTexture, uv).r;
  outColor = vec4(noise.xxx, 1.0);
}
#endif // IS_PIXEL_SHADER