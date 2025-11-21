#include "Util.glsl"
#include <Misc/Sampling.glsl>

vec3 computeDir(vec2 uv) {
	vec2 d = uv * 2.0 - 1.0;

	vec4 target = camera.inverseProjection * vec4(d, 1.0.xx);
	return (camera.inverseView * vec4(normalize(target.xyz), 0)).xyz;
}

vec2 sampleEnv(vec3 dir) {
    float yaw = atan(dir.z, dir.x) - PI;
    float pitch = -atan(dir.y, length(dir.xz));
    return vec2(0.5 * yaw, pitch) / PI + 0.5;
}

#ifdef IS_VERTEX_SHADER
VertexOutput VS_Jupiter() {
  return VertexOutput(VS_FullScreen());
}
#endif // IS_VERTEX_SHADER

vec2 applyTurbulence(vec2 pos) {
  float freq = TURB_FREQ;
  float amp = TURB_AMP;
  float speed = TURB_SPEED;

  float cosTheta = cos(TURB_ROT);
  float sinTheta = sin(TURB_ROT);
  mat2 drot = mat2(cosTheta, -sinTheta, sinTheta, cosTheta);
  mat2 rot = drot;

  for (int i = 0; i < 10; i++) {
    float phase = freq * (pos * rot).y + speed * uniforms.time + i;
    pos += amp * rot[0] * sin(phase) / freq;

    rot *= drot;
    freq *= TURB_EXP;
  }
  return pos;
}

vec2 applyJitter(vec2 pos, inout uvec2 pixSeed) {
  return pos + 0.001 * (2.0 * randVec2(pixSeed) - 1.0.xx);
}

vec3 sampleField(vec2 pos) {
  vec2 ar = vec2(1.0, float(SCREEN_HEIGHT)/float(SCREEN_WIDTH));
  vec3 col = 0.0.xxx;
  vec2 diff = fract(pos * 10.0) - 0.5.xx;
  if (diff.x < 0.0) {
    col += COLOR0.rgb * COLOR0_INT * exp(COLOR0_FALLOFF * diff.x);
  }
  if (diff.y < 0.0) {
    col += COLOR1.rgb * COLOR1_INT * exp(COLOR1_FALLOFF * diff.y);
  }
  if (diff.x > 0.4) {
    col += COLOR2.rgb * COLOR2_INT * exp(-COLOR2_FALLOFF * diff.x);
  }
  return col;
  // return (min(pos.x, pos.y) < 0.01) ? vec3(1.0, 0.0, 0.0) : 0.0.xxx;
}

#ifdef IS_PIXEL_SHADER
void PS_Jupiter(VertexOutput IN) {
  vec2 ar = vec2(1.0, float(SCREEN_HEIGHT)/float(SCREEN_WIDTH));
  vec2 particlePos = vec2(0.1, 0.5) * ar; 
  uvec2 pixSeed = uvec2(vec2(SCREEN_WIDTH, SCREEN_HEIGHT) * IN.uv) * uvec2(231 + uniforms.frameCount, 73 + uniforms.frameCount);

  // vec2 pos = IN.uv * ar;
  Ray ray = Ray(
    computeDir(IN.uv), 
    camera.inverseView[3].xyz);
  Sphere sphere = Sphere(
    vec3(0.0, 0.0, -5.0),
    2.0);

  // vec2 pos = 2.0 * sampleEnv(ray.dir);
  float z = 1.0;

  vec3 col = 0.0.xxx;
  Hit hit;
  if (traceRaySphere(sphere, ray, hit)) {
    vec2 pos = sampleEnv(normalize(hit.localPos));
    float rm_0 = RM_0;//0.5 + RM_0 * (0.5 + 0.5 * sin(uniforms.time * 1.3 + 23.0) + pow(0.025 + 0.05 * sin(uniforms.time * 23.0 + 0.3), 2.0));
    float throughput = 1.0;
    if (APPLY_TURBULENCE) {
      for (int i = 0; i < 10; i++) {
        vec3 c = sampleField(pos);
        col += throughput * c * float(i) / 20.0;
        vec2 dx = (1.9 * rm_0 - i/5.0 * RM_1) * (applyTurbulence(pos) - pos);
        vec3 dir = vec3(dx, z);
        dir = refract(dir, vec3(0.0, 0.0, -1.0), ETA);
        float dist = length(dir);
        throughput *= exp(-0.001 * COLOR3_FALLOFF * dist);
        // dir /= dist;
        z = dir.z;
        pos += dir.xy;
      }
    }
    // col = sampleField(pos);
  }

  col = vec3(1.0) - exp(-col * EXPOSURE);
  outColor = vec4(col, 1.0);
}
#endif
