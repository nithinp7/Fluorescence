/*
vec3 sampleDiffusionProfile(float d) {
  vec3 c0 = vec3(RED_0, GREEN_0, BLUE_0);
  vec3 c1 = vec3(RED_1, GREEN_1, BLUE_1);

  vec3 t = d.xxx / c1;
  return c0 * exp(-0.5 * t * t);
}
*/

float bumpCurvature(vec2 uv) {
  float b = texture(HeadBumpTexture, uv).r;
  float bL = texture(HeadBumpTexture, uv - vec2(CURVATURE_RADIUS, 0.0)).r;
  float bR = texture(HeadBumpTexture, uv + vec2(CURVATURE_RADIUS, 0.0)).r;
  float bD = texture(HeadBumpTexture, uv - vec2(0.0, CURVATURE_RADIUS)).r;
  float bU = texture(HeadBumpTexture, uv + vec2(0.0, CURVATURE_RADIUS)).r;

  return 0.25 * (bL + bR + bD + bU) - b;
}

#ifdef IS_VERTEX_SHADER
VertexOutput VS_DrawMap() {
  VertexOutput OUT;
  OUT.uv = VS_FullScreen();
  return OUT;
}

VertexOutput VS_SaveMap() {
  VertexOutput OUT;
  OUT.uv = VS_FullScreen();
  return OUT;
}
#endif // IS_VERTEX_SHADER

#ifdef IS_PIXEL_SHADER
vec3 drawSkinMap(vec2 uv) {
  const float ASPECT_RATIO = float(SCREEN_HEIGHT) / float(SCREEN_WIDTH);
  
  if (!FIX_UV) {
    uv = uv * 2.0 - 1.0.xx;
    uv /= ZOOM;
    uv += vec2(PAN_X, 1.0 - PAN_Y);
    uv.y *= ASPECT_RATIO;
  }

  vec3 diffuse = texture(HeadLambertianTexture, uv).rgb;
  float bump = texture(HeadBumpTexture, uv).r;
  
  vec2 bumpGrad = vec2(dFdx(bump), dFdy(bump));

  vec3 color;
  if (MODE == 0) {
    color = (abs(bump - SLICE)*SCALE).xxx;
  } else if (MODE == 1) {
    color = vec3(max(bumpGrad, 0.01 * SLICE.xx), 0.0) * SCALE;
  } else if (MODE == 2) {
    color = max(length(bumpGrad), 0.01 * SLICE).xxx * SCALE;
  } else {
    color = bumpCurvature(uv).xxx * SCALE;
  }

  return color;
}

#ifdef _ENTRY_POINT_PS_DrawMap
void PS_DrawMap(VertexOutput IN) {
  vec3 color = drawSkinMap(IN.uv);
  outDisplay = vec4(color, 1.0);
}
#endif // _ENTRY_POINT_PS_DrawMap

#ifdef _ENTRY_POINT_PS_SaveMap
void PS_SaveMap(VertexOutput IN) {
  vec3 color = drawSkinMap(IN.uv);
  outSave = vec4(color, 1.0);
}
#endif // _ENTRY_POINT_PS_SaveMap

#endif // IS_PIXEL_SHADER 