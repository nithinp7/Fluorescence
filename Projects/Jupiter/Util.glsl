
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

#endif // _UTILGLSL_