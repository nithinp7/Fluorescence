
vec3 sampleDiffusionProfile(float d) {
  vec3 c0 = vec3(RED_0, GREEN_0, BLUE_0);
  vec3 c1 = vec3(RED_1, GREEN_1, BLUE_1);

  vec3 t = d.xxx / c1;
  return c0 * exp(-0.5 * t * t);
}

#ifdef IS_VERTEX_SHADER
VertexOutput VS_DrawProfile() {
  VertexOutput OUT;
  OUT.uv = VS_FullScreen();
  OUT.uv.y = 1.0 - OUT.uv.y;
  return OUT;
}
#endif // IS_VERTEX_SHADER

#ifdef IS_PIXEL_SHADER
void PS_DrawProfile(VertexOutput IN) {
  vec2 pos = IN.uv * 2.0 - 1.0.xx;

  float LINE_THICKNESS = 0.005;

  vec3 f;
  if (MODE == 0) {
    float d = length(pos);
    f = sampleDiffusionProfile(d);
  } else {
    float d = IN.uv.x;
    vec3 c = sampleDiffusionProfile(pos.x);
    if (abs(IN.uv.y - c.x) < LINE_THICKNESS) {
      f = vec3(1.0, 0.0, 0.0);
    } else if (abs(IN.uv.y - c.y) < LINE_THICKNESS) {
      f = vec3(0.0, 1.0, 0.0);
    } else if (abs(IN.uv.y - c.z) < LINE_THICKNESS) {
      f = vec3(0.0, 0.0, 1.0);
    } else {
      f = c;
    }
  }

  outDisplay = vec4(f, 1.0);
  outSave = vec4(f, 1.0);
}
#endif // IS_PIXEL_SHADER 