#ifndef _SCENE_GLSL_
#define _SCENE_GLSL_

#include <Misc/Constants.glsl>
#include <FlrLib/Scene/Intersection.glsl>

struct SceneBuilder {
  uint matID;
  uint triCount;
  uint sphereCount;
  bool bFlipNormal;
};

SceneBuilder g_sceneBuilder;

void pushMaterial(Material mat) {
  materialBuffer[g_sceneBuilder.matID++] = mat;
}

void startSceneBuild() {
  g_sceneBuilder.matID = 0;
  g_sceneBuilder.triCount = 0;
  g_sceneBuilder.sphereCount = 0;
  g_sceneBuilder.bFlipNormal = false;

  Material defaultMat;
  defaultMat.diffuse = 0.0.xxx;
  defaultMat.roughness = 0.0;
  defaultMat.emissive = 0.0.xxx;
  defaultMat.metallic = 0.0;
  pushMaterial(defaultMat);
}

void pushTri(vec3 a, vec3 b, vec3 c) {
  triBuffer[g_sceneBuilder.triCount++] = 
      Tri(
        a, 
        g_sceneBuilder.bFlipNormal ? c : b, 
        g_sceneBuilder.bFlipNormal ? b : c, 
        g_sceneBuilder.matID - 1);
}

void popTri() {
  g_sceneBuilder.triCount--;
}

void pushQuad(vec3 a, vec3 b, vec3 c, vec3 d) {
  pushTri(a, b, c);
  pushTri(a, c, d);
}

void popQuad() {
  popTri();
  popTri();
}

void pushSphere(vec3 c, float r) {
  sphereBuffer[g_sceneBuilder.sphereCount++] = Sphere(c, r, g_sceneBuilder.matID - 1);
}

void popSphere() {
  g_sceneBuilder.sphereCount--;
}

void pushBox(vec3 pos, mat3 dims) {
    // FLOOR
    pushQuad(
      pos + dims * vec3(-1.0, -1.0, -1.0),
      pos + dims * vec3(-1.0, -1.0, 1.0),
      pos + dims * vec3(1.0, -1.0, 1.0),
      pos + dims * vec3(1.0, -1.0, -1.0));
    
    // CEILING
    pushQuad(
      pos + dims * vec3(-1.0, 1.0, -1.0),
      pos + dims * vec3(1.0, 1.0, -1.0),
      pos + dims * vec3(1.0, 1.0, 1.0),
      pos + dims * vec3(-1.0, 1.0, 1.0));

    // LEFT
    pushQuad(
      pos + dims * vec3(-1.0, -1.0, -1.0), 
      pos + dims * vec3(-1.0, 1.0, -1.0),
      pos + dims * vec3(-1.0, 1.0, 1.0),
      pos + dims * vec3(-1.0, -1.0, 1.0));
    
    // RIGHT
    pushQuad(
      pos + dims * vec3(1.0, -1.0, -1.0), 
      pos + dims * vec3(1.0, -1.0, 1.0),
      pos + dims * vec3(1.0, 1.0, 1.0),
      pos + dims * vec3(1.0, 1.0, -1.0));

    // BACK WALL
    pushQuad(
      pos + dims * vec3(-1.0, -1.0, -1.0),
      pos + dims * vec3(1.0, -1.0, -1.0),
      pos + dims * vec3(1.0, 1.0, -1.0),
      pos + dims * vec3(-1.0, 1.0, -1.0));
    
    // FRONT WALL
    pushQuad(
      pos + dims * vec3(-1.0, -1.0, 1.0),
      pos + dims * vec3(-1.0, 1.0, 1.0),
      pos + dims * vec3(1.0, 1.0, 1.0),
      pos + dims * vec3(1.0, -1.0, 1.0));
}

void finishSceneBuild() {
  globalStateBuffer[0].triCount = g_sceneBuilder.triCount;
  globalStateBuffer[0].sphereCount = g_sceneBuilder.sphereCount;
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


// EXAMPLE SCENES
void initScene_CornellBox() {
  startSceneBuild();
  
  {
    Material mat;
    mat.diffuse = 1.0.xxx;
    mat.roughness = 0.4;
    mat.emissive = 0.0.xxx;
    mat.metallic = 0.0;
    pushMaterial(mat);

    float cornellBoxScale = 15.0;
    pushBox(0.0.xxx, mat3(cornellBoxScale));
    popQuad(); // remove front face
    
    // color side-walls
    mat.diffuse = vec3(1.0, 0.0, 0.0);
    triBuffer[g_sceneBuilder.triCount-6].matID = g_sceneBuilder.matID;
    triBuffer[g_sceneBuilder.triCount-5].matID = g_sceneBuilder.matID;
    pushMaterial(mat);
    mat.diffuse = vec3(0.0, 1.0, 0.0);
    triBuffer[g_sceneBuilder.triCount-4].matID = g_sceneBuilder.matID;
    triBuffer[g_sceneBuilder.triCount-3].matID = g_sceneBuilder.matID;
    pushMaterial(mat);

    // add light
    mat.emissive = 1000.0.xxx;
    pushMaterial(mat);
    float lightSize = 2.0;
    float lightHeight = cornellBoxScale - 0.5;
    pushQuad(
      vec3(-lightSize, lightHeight, -lightSize),
      vec3(lightSize, lightHeight, -lightSize),
      vec3(lightSize, lightHeight, lightSize),
      vec3(-lightSize, lightHeight, lightSize));
  }

  for (int i = 0; i < 3; i++) {
    Material mat;
    mat.diffuse = vec3(i/2.0, 1.0 - i/2.0, 1.0);
    mat.roughness = 0.1;
    mat.emissive = 0.0.xxx;
    mat.metallic = 0.0;
    pushMaterial(mat);

    pushSphere(vec3(8.0 * i - 6.0, 0.0, 0.0), 4.0);
  }
  
  finishSceneBuild();
}

#endif // _SCENE_GLSL_