#ifndef _SCENE_GLSL_
#define _SCENE_GLSL_

#include <Misc/Constants.glsl>
#include "Intersection.glsl"

struct SceneBuilder {
  uint matID;
  uint triCount;
  uint sphereCount;
};

SceneBuilder g_sceneBuilder;

void pushMaterial(Material mat) {
  materialBuffer[g_sceneBuilder.matID++] = mat;
}

void startSceneBuild() {
  g_sceneBuilder.matID = 0;
  g_sceneBuilder.triCount = 0;
  g_sceneBuilder.sphereCount = 0;

  Material defaultMat;
  defaultMat.diffuse = 0.0.xxx;
  defaultMat.roughness = 0.0;
  defaultMat.emissive = 0.0.xxx;
  defaultMat.metallic = 0.0;
  pushMaterial(defaultMat);
}

void pushTri(vec3 a, vec3 b, vec3 c) {
  triBuffer[g_sceneBuilder.triCount++] = Tri(a, b, c, g_sceneBuilder.matID - 1);
}

void pushQuad(vec3 a, vec3 b, vec3 c, vec3 d) {
  pushTri(a, b, c);
  pushTri(a, c, d);
}

void pushSphere(vec3 c, float r) {
  sphereBuffer[g_sceneBuilder.sphereCount++] = Sphere(c, r, g_sceneBuilder.matID - 1);
}

void finishSceneBuild() {
  globalStateBuffer[0].triCount = g_sceneBuilder.triCount;
  globalStateBuffer[0].sphereCount = g_sceneBuilder.sphereCount;
}

void initScene() {
  startSceneBuild();
  
  {
    Material mat;
    mat.diffuse = 1.0.xxx;
    mat.roughness = 0.0;
    mat.emissive = 0.0.xxx;
    mat.metallic = 0.0;
    pushMaterial(mat);

    float cornellBoxScale = 15.0;

    // FLOOR
    pushQuad(
      cornellBoxScale * vec3(-1.0, -1.0, -1.0),
      cornellBoxScale * vec3(1.0, -1.0, -1.0),
      cornellBoxScale * vec3(1.0, -1.0, 1.0),
      cornellBoxScale * vec3(-1.0, -1.0, 1.0));
    
    // CEILING
    pushQuad(
      cornellBoxScale * vec3(-1.0, 1.0, -1.0),
      cornellBoxScale * vec3(-1.0, 1.0, 1.0),
      cornellBoxScale * vec3(1.0, 1.0, 1.0),
      cornellBoxScale * vec3(1.0, 1.0, -1.0));

    // LEFT
    pushQuad(
      cornellBoxScale * vec3(-1.0, -1.0, -1.0), 
      cornellBoxScale * vec3(-1.0, 1.0, -1.0),
      cornellBoxScale * vec3(-1.0, 1.0, 1.0),
      cornellBoxScale * vec3(-1.0, -1.0, 1.0));
    
    // RIGHT
    pushQuad(
      cornellBoxScale * vec3(1.0, -1.0, -1.0), 
      cornellBoxScale * vec3(1.0, -1.0, 1.0),
      cornellBoxScale * vec3(1.0, 1.0, 1.0),
      cornellBoxScale * vec3(1.0, 1.0, -1.0));

    // BACK WALL
    pushQuad(
      cornellBoxScale * vec3(-1.0, -1.0, -1.0),
      cornellBoxScale * vec3(1.0, -1.0, -1.0),
      cornellBoxScale * vec3(1.0, 1.0, -1.0),
      cornellBoxScale * vec3(-1.0, 1.0, -1.0));
  }

  for (int i = 0; i < 3; i++) {
    Material mat;
    mat.diffuse = vec3(i/2.0, 1.0 - i/2.0, 1.0);
    mat.roughness = 0.0;
    mat.emissive = 0.0.xxx;
    mat.metallic = 0.0;
    pushMaterial(mat);

    pushSphere(vec3(8.0 * i + 0.1, 0.0, 0.0), 4.0);
  }
  
  finishSceneBuild();
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