#include <Misc/Sampling.glsl>

uint getGridIdx(uvec2 c) {
  return c.y * GRID_LEN + c.x;
}

vec2 getGradient(uvec2 c) {
  return gradients[getGridIdx(c)].dir;
}

void setGradient(uvec2 c, vec2 g) {
  gradients[getGridIdx(c)].dir = g;
}

float smoothBilerp(vec4 values, vec2 t) {
  t = t * t * (3.0 - 2.0 * t);
  vec2 v = mix(values.xz, values.yw, t.xx);
  return mix(v.x, v.y, t.y);
}

float noise(vec2 uv) {
  vec2 p = uv * vec2(SCREEN_WIDTH, SCREEN_HEIGHT) + 0.5;

  vec2 scaledUv = uv * GRID_LEN;
  vec2 t = fract(scaledUv);
  uvec2 c00 = uvec2(scaledUv);

  vec4 d;
  for (int i=0; i<4; i++) {
    uvec2 dc = uvec2(i&1, (i>>1)&1);
    vec2 offs = t - vec2(dc);
    vec2 g = getGradient(c00 + dc);
    d[i] = dot(g, offs);
  }

  return smoothBilerp(d, t);
}

#ifdef IS_COMP_SHADER
void CS_InitGradients() {
  uvec2 c = uvec2(gl_GlobalInvocationID.xy);
  if (c.x >= GRID_LEN || c.y >= GRID_LEN)
    return;
  
  uvec2 seed = uvec2(12032 + SEED, 151927 + SEED) * c;
  setGradient(c, randVec2(seed) * 2.0 - 1.0.xx);
}
#endif

#ifdef IS_VERTEX_SHADER
VertexOutput VS_DrawNoise() {
  VertexOutput OUT;
  OUT.uv = VS_FullScreen();
  return OUT;
}
#endif // IS_VERTEX_SHADER

#ifdef IS_PIXEL_SHADER
void PS_DrawNoise(VertexOutput IN) {
  vec3 color = noise(IN.uv).xxx;
  outDisplay = vec4(color, 1.0);
}
#endif // IS_PIXEL_SHADER 