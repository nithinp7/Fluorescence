#ifndef _SCENE_GLSL_
#define _SCENE_GLSL_

#include <Misc/Constants.glsl>
#include "Intersection.glsl"

void initScene() {
  uint triCount = 0;
  {
    uint iters = 20;
    float width = 2.0;
    float radius = 10.0;
    float dtheta = 2.0 * PI / 20;
    for (int i = 0; i < iters; i++) {
      float c0=radius*cos(i*dtheta), s0=radius*sin(i*dtheta);
      float c1=radius*cos((i+1)*dtheta), s1=radius*sin((i+1)*dtheta);
      Tri t0, t1;
      t0.v0 = vec3(c0, s0, -width);    
      t0.v1 = vec3(c1, s1, -width);    
      t0.v2 = vec3(c1, s1, width);    
      t1.v0 = vec3(c0, s0, -width);    
      t1.v1 = vec3(c1, s1, width);    
      t1.v2 = vec3(c0, s0, width);  
      triBuffer[triCount++] = t0;
      triBuffer[triCount++] = t1;  
    }
  }
  globalStateBuffer[0].triCount = triCount;

  uint sphereCount = 0;
  for (int i = 0; i < 3; i++) {
    Sphere s;
    s.r = 4.0;
    s.c = vec3(2.0 * s.r * i + 0.1, 0.0, 0.0);
    sphereBuffer[sphereCount++] = s;
  }
  globalStateBuffer[0].sphereCount = sphereCount;
}

bool traceScene(Ray ray, out HitResult hit) {
  bool bHit = false;
  uint triCount = globalStateBuffer[0].triCount;
  for (int i = 0; i < triCount && i < MAX_TRIS; i++) {
    HitResult h;
    if (traceTri(triBuffer[i], ray, h)) {
      if (!bHit || h.t < hit.t) {
        hit = h;
      }
      bHit = true;
    }
  }

  uint sphereCount = globalStateBuffer[0].sphereCount;
  for (int i = 0; i < sphereCount && i < MAX_SPHERES; i++) {
    HitResult h;
    if (traceSphere(sphereBuffer[i], ray, h)) {
      if (!bHit || h.t < hit.t) {
        hit = h;
      }
      bHit = true;
    }
  }

  return bHit;
}
#endif // _SCENE_GLSL_