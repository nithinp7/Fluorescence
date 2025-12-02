
#ifndef _UTILGLSL_
#define _UTILGLSL_

struct Sphere {
  vec3 center;
  float radius;
};

struct Ray {
  vec3 dir;
  vec3 origin;
};

struct Hit {
  vec3 localPos;
  float t_entry;
  float t_exit;
};

bool traceRaySphere(Sphere s, Ray ray, out Hit hit) {
  vec3 co = ray.origin - s.center;

  // Solve quadratic equation (with a = 1)
  float b = 2.0 * dot(ray.dir, co);
  float c = dot(co, co) - s.radius * s.radius;

  float b2_4ac = b * b - 4.0 * c;
  if (b2_4ac < 0.0) {
    // No real roots
    return false;
  }

  float distLimit = 10000000.0; // can replace this with the depth-buffer sample if needed

  float sqrt_b2_4ac = sqrt(b2_4ac);
  hit.t_entry = max(0.5 * (-b - sqrt_b2_4ac), 0.0);
  hit.t_exit = min(0.5 * (-b + sqrt_b2_4ac), distLimit);

  if (hit.t_exit <= 0.0 || hit.t_entry >= distLimit) {
    // The entire sphere is behind the camera or occluded by the
    // depth buffer.
    return false;
  }

  hit.localPos = ray.origin + hit.t_entry * ray.dir - s.center;

  return true;
}

vec3 computeDir(vec2 uv) {
	vec2 d = uv * 2.0 - 1.0;

	vec4 target = camera.inverseProjection * vec4(d, 1.0.xx);
	return (camera.inverseView * vec4(normalize(target.xyz), 0)).xyz;
}

vec3 getCameraPos() {
  return camera.inverseView[3].xyz;
}

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

// The ratio of light that will get reflected vs refracted.
// F0 - The base reflectivity when viewing straight down along the
// surface normal.
vec3 fresnelSchlick(float NdotH, vec3 F0, float roughness) {
  return F0 + (max(vec3(1.0 - roughness), F0) - F0) * pow(1.0 - NdotH, 5.0);
}

vec3 fresnel(vec3 normal, vec3 viewDir) {
  vec3 F0 = 0.01.xxx;  
  float NdotV = dot(viewDir, normal);
  return F0 + (1.0.xxx - F0) * pow(1.0 - NdotV, 5.0);
}

vec3 directLighting(vec3 normal) {
  vec3 dir = getSunDir();
  float rcos = dot(normal, dir);
  if (rcos < 0.0) return 0.0.xxx;
  return SUN_INT * rcos * 1.0.xxx;
}

vec3 normalToColor(vec3 n) {
  return 0.5 * n + 0.5.xxx;
}

float saturate(float f) {
  return max(0, min(f, 1.0));
}

vec3 sampleSky(vec3 dir) {
  vec3 horizonColor = mix(SKY_COLOR.rgb, 1.0.xxx, HORIZON_WHITENESS);
  vec3 color = SKY_INT * mix(horizonColor, SKY_COLOR.rgb, pow(abs(dir.y), HORIZON_WHITENESS_FALLOFF));
  vec3 sunDir = getSunDir();
  float cutoff = 0.001;
  float sunInt = SUN_INT * max((dot(sunDir, dir) - 1.0 + cutoff)/cutoff, 0.0);
  color += sunInt * vec3(0.8, 0.78, 0.3);
  return color;
}

vec3 remapColor(vec3 col) {
  return vec3(1.0) - exp(-col * EXPOSURE);
}
#endif // _UTILGLSL_