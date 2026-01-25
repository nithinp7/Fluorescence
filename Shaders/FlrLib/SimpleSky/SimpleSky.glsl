#ifndef _FLR_SIMPLESKY_
#define _FLR_SIMPLESKY_

// NOTE depends on including SimpleSky.flrh in flr file

vec2 dirToPolar(vec3 dir) {
    float yaw = atan(dir.z, dir.x) - PI;
    float pitch = -atan(dir.y, length(dir.xz));
    return vec2(0.5 * yaw, pitch) / PI + 0.5;
}

vec3 polarToDir(vec2 p) {
  p -= 0.5.xx;
  p *= PI * vec2(2.0, -1.0);
  p.x += PI;
  vec3 dir;
  dir.y = sin(p.y);
  float dirxzmag = cos(p.y);
  dir.x = cos(p.x) * dirxzmag;
  dir.z = sin(p.x) * dirxzmag;
  return dir;
}

vec3 getSunDir() {
  return normalize(polarToDir(vec2(SUN_ROT, SUN_ELEV)));
}

vec3 sampleSky(vec3 dir) {
  vec3 horizonColor = mix(SKY_COLOR.rgb, 1.0.xxx, HORIZON_WHITENESS);
  vec3 color = SKY_INT * mix(horizonColor, SKY_COLOR.rgb, pow(abs(dir.y), HORIZON_WHITENESS_FALLOFF));
  vec3 sunDir = getSunDir();
  float cutoff = 0.001;
  float sunInt = SUN_INT * max((dot(sunDir, dir) - 1.0 + cutoff)/cutoff, 0.0);
  color += sunInt * vec3(0.8, 0.78, 0.3);
  color *= pow(min(1.0 + dir.y, 1.0), 8.0);
  return color;
}

#endif // _FLR_SIMPLESKY_