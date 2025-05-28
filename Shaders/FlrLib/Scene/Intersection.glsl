#ifndef _INTERSECTION_GLSL_
#define _INTERSECTION_GLSL_

struct Ray {
  vec3 o;
  vec3 d;
};

struct HitResult {
  vec3 p;
  float t;
  vec3 n;
  uint matID;
};

bool traceTri(Tri tri, Ray ray, out HitResult hit) {
  vec3 v0 = sceneVertexBuffer[tri.i0].pos;
  vec3 v1 = sceneVertexBuffer[tri.i1].pos;
  vec3 v2 = sceneVertexBuffer[tri.i2].pos;

  mat3 T;
  T[0] = v1 - v0;
  T[1] = v2 - v0;
  T[2] = -ray.d;

  vec3 n = cross(T[0], T[1]);
  float nDotD = dot(n, ray.d);
  // enable optional backface culling...
  if (nDotD > -0.00001) return false;
  // if (abs(nDotD) < 0.00001) return false;

  mat3 Tinv = inverse(T);
  vec3 uvt = Tinv * (ray.o - v0);
  if (uvt.x < 0.0 || uvt.x > 1.0 || 
      uvt.y < 0.0 || uvt.y > 1.0 || 
      (uvt.x + uvt.y) > 1.0 || uvt.z < 0.0) 
    return false;

  hit.p = uvt.x * T[0] + uvt.y * T[1] + v0;
  hit.t = uvt.z;
  hit.n = normalize(n) * -sign(nDotD);
  hit.matID = tri.matID;
  return true;
}

bool traceSphere(Sphere s, Ray ray, out HitResult hit) {
  // ||o + td - c||^2 = r^2
  // || (o-c) + td ||^2
  // || (o-c) || ^2 + 2 (o-c) * td + t^2 = r^2
  // a=1, b=2(o-c)*d, c=||o-c||^2 - r^2

  vec3 diff = ray.o - s.c;
  float c = dot(diff, diff) - s.r * s.r;
  float b = 2.0 * dot(diff, ray.d);
  float b2_4ac = b * b - 4 * c;
  if (b2_4ac < 0.0) return false;

  float sqrt_b2_4ac = sqrt(b2_4ac);
  float t = 0.5 * (-b - sqrt_b2_4ac);
  if (t < 0.0)
    return false;

  hit.p = ray.o + t*ray.d;
  hit.t = t;
  hit.n = normalize(hit.p - s.c);
  hit.matID = s.matID;
  return true;
}
#endif // _INTERSECTION_GLSL_