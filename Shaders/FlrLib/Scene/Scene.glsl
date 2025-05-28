#ifndef _SCENE_GLSL_
#define _SCENE_GLSL_

#include <Misc/Constants.glsl>
#include <FlrLib/Scene/Intersection.glsl>

struct SceneBuilder {
  vec3 translation;
  uint matID;
  uint vertCount;
  uint triCount;
  uint sphereCount;
  bool bFlipNormal;
};

SceneBuilder g_sceneBuilder;

void pushMaterial(Material mat) {
  materialBuffer[g_sceneBuilder.matID++] = mat;
}

void startSceneBuild() {
  g_sceneBuilder.translation = 0.0.xxx;
  g_sceneBuilder.matID = 0;
  g_sceneBuilder.vertCount = 0;
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

void pushVert(vec3 pos) {
  sceneVertexBuffer[g_sceneBuilder.vertCount++] = 
      SceneVertex(pos + g_sceneBuilder.translation);
}

void pushTri(vec3 a, vec3 b, vec3 c) {
  uint i0 = g_sceneBuilder.vertCount;
  pushVert(a);
  pushVert(g_sceneBuilder.bFlipNormal ? b : c);
  pushVert(g_sceneBuilder.bFlipNormal ? c : b);
  triBuffer[g_sceneBuilder.triCount++] = Tri(i0, i0+1, i0+2, g_sceneBuilder.matID - 1);
}

void popTri() {
  // this will break if the triangles are indexed to re-use verts...
  g_sceneBuilder.vertCount -= 3;
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
  c += g_sceneBuilder.translation;
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
  for (int i = 0; i < triCount && i < MAX_SCENE_TRIS; i++) {
    HitResult h;
    if (traceTri(triBuffer[i], ray, h)) {
      if (!bHit || h.t < hit.t) {
        hit = h;
      }
      bHit = true;
    }
  }

  uint sphereCount = globalStateBuffer[0].sphereCount;
  for (int i = 0; i < sphereCount && i < MAX_SCENE_SPHERES; i++) {
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
  
  float cornellBoxScale = 15.0;
  g_sceneBuilder.translation = vec3(10.0, 5.0, -1.0);
  {
    Material mat;
    mat.diffuse = 1.0.xxx;
    mat.roughness = 0.4;
    mat.emissive = 0.0.xxx;
    mat.metallic = 0.0;
    pushMaterial(mat);

    {
      float theta = PI / 4.0;
      float c = cos(theta), s = sin(theta);
      mat3 boxT;
      boxT[0] = vec3(c, 0.0, s) * 0.3 * cornellBoxScale;
      boxT[1] = vec3(0.0, 1.0, 0.0) * 0.5 * cornellBoxScale;
      boxT[2] = vec3(-s, 0.0, c) * 0.3 * cornellBoxScale;
      pushBox(vec3(-0.45, -1.0 + 0.5, -0.25) * cornellBoxScale, boxT);
    }

    {
      float theta = -PI / 21.0;
      float c = cos(theta), s = sin(theta);
      mat3 boxT;
      boxT[0] = vec3(c, 0.0, s) * 0.25 * cornellBoxScale;
      boxT[1] = vec3(0.0, 1.0, 0.0) * 0.6 * cornellBoxScale;
      boxT[2] = vec3(-s, 0.0, c) * 0.25 * cornellBoxScale;
      pushBox(vec3(0.45, -1.0 + 0.6, 0.15) * cornellBoxScale, boxT);
    }

    // main room
    g_sceneBuilder.bFlipNormal = true;
    pushBox(0.0.xxx, mat3(cornellBoxScale));
    // popQuad(); // remove front face
    g_sceneBuilder.bFlipNormal = false;
    
    // color side-walls
    mat.diffuse = vec3(1.0, 0.0, 0.0);
    triBuffer[g_sceneBuilder.triCount-8].matID = g_sceneBuilder.matID;
    triBuffer[g_sceneBuilder.triCount-7].matID = g_sceneBuilder.matID;
    pushMaterial(mat);
    mat.diffuse = vec3(0.0, 1.0, 0.0);
    triBuffer[g_sceneBuilder.triCount-6].matID = g_sceneBuilder.matID;
    triBuffer[g_sceneBuilder.triCount-5].matID = g_sceneBuilder.matID;
    pushMaterial(mat);

    // add light
    mat.emissive = 10.0.xxx;
    pushMaterial(mat);
    float lightSize = 6.0;
    float lightHeight = cornellBoxScale - 0.5;
    pushQuad(
      vec3(-lightSize, lightHeight, -lightSize),
      vec3(lightSize, lightHeight, -lightSize),
      vec3(lightSize, lightHeight, lightSize),
      vec3(-lightSize, lightHeight, lightSize));
  }

  {
    Material mat;
    mat.diffuse = vec3(0.0, 1.0, 1.0);
    mat.roughness = 0.4;
    mat.emissive = 0.0.xxx;
    mat.metallic = 0.0;
    pushMaterial(mat);

    pushSphere(vec3(-0.45, 0.35, -0.25) * cornellBoxScale, 0.35 * cornellBoxScale);
  }

  {
    Material mat;
    mat.diffuse = vec3(0.5, 0.5, 1.0);
    mat.roughness = 0.4;
    mat.emissive = 0.0.xxx;
    mat.metallic = 0.0;
    pushMaterial(mat);

    pushSphere(vec3(0.45, 0.2 + 0.25, 0.15) * cornellBoxScale, 0.25 * cornellBoxScale);
  }

  finishSceneBuild();
}

#endif // _SCENE_GLSL_