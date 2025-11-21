#ifndef _SCENE_GLSL_
#define _SCENE_GLSL_

#include <Misc/Constants.glsl>
#include <Misc/Sampling.glsl>
#include <FlrLib/Scene/Intersection.glsl>

struct SceneBuilder {
  vec3 translation;
  uint matID;
  uint vertCount;
  uint triCount;
  uint sphereCount;
  uint lightCount;
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
  g_sceneBuilder.lightCount = 0;
  g_sceneBuilder.bFlipNormal = false;

  Material defaultMat;
  defaultMat.diffuse = 0.0.xxx;
  defaultMat.roughness = 0.0;
  defaultMat.emissive = 0.0.xxx;
  defaultMat.specular = 0.0.xxx;
  defaultMat.metallic = 0.0;
  defaultMat.transmission = 0.0;
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

  Material mat = materialBuffer[g_sceneBuilder.matID-1];
  if (mat.emissive != 0.0.xxx) {
    lightBuffer[g_sceneBuilder.lightCount++] = Light(g_sceneBuilder.triCount-1, LIGHT_TYPE_TRI);
  }
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

  Material mat = materialBuffer[g_sceneBuilder.matID-1];
  if (mat.emissive != 0.0.xxx) {
    lightBuffer[g_sceneBuilder.lightCount++] = Light(g_sceneBuilder.sphereCount-1, LIGHT_TYPE_SPHERE);
  }
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

vec3 calcSphereVert(float theta, float phi) {
  return vec3(cos(theta) * cos(phi), sin(phi), -sin(theta) * cos(phi));
}

void finishSceneBuild() {
  globalSceneBuffer[0].triCount = g_sceneBuilder.triCount;
  globalSceneBuffer[0].sphereCount = g_sceneBuilder.sphereCount;
  globalSceneBuffer[0].lightCount = g_sceneBuilder.lightCount;

  uint RES = 12;
  uint sphereVertCount = RES * RES * 2 * 3;
  float DTHETA = 2.0 * PI / RES;
  float PHI_LIM = 0.95 * PI / 2.0;
  float DPHI = 2.0 * PHI_LIM / RES;
  for(uint i=0;i<RES;i++) for(uint j=0;j<RES;j++) {
    uint i1=i+1, j1=j+1;
    float theta0=DTHETA*i, theta1=DTHETA*i1;
    float phi0=DPHI*j-PHI_LIM, phi1=DPHI*j1-PHI_LIM;
    
    sceneVertexBuffer[g_sceneBuilder.vertCount++] = SceneVertex(calcSphereVert(theta0,phi0));
    sceneVertexBuffer[g_sceneBuilder.vertCount++] = SceneVertex(calcSphereVert(theta1,phi0));
    sceneVertexBuffer[g_sceneBuilder.vertCount++] = SceneVertex(calcSphereVert(theta1,phi1));
    
    sceneVertexBuffer[g_sceneBuilder.vertCount++] = SceneVertex(calcSphereVert(theta0,phi0));
    sceneVertexBuffer[g_sceneBuilder.vertCount++] = SceneVertex(calcSphereVert(theta1,phi1));
    sceneVertexBuffer[g_sceneBuilder.vertCount++] = SceneVertex(calcSphereVert(theta0,phi1));
  }

  trianglesIndirectArgs[0].vertexCount = g_sceneBuilder.triCount*3;
  trianglesIndirectArgs[0].instanceCount = 1;
  trianglesIndirectArgs[0].firstVertex = 0; 
  trianglesIndirectArgs[0].firstInstance = 0; 
  
  spheresIndirectArgs[0].vertexCount = sphereVertCount;
  spheresIndirectArgs[0].instanceCount = g_sceneBuilder.sphereCount;
  spheresIndirectArgs[0].firstVertex = g_sceneBuilder.triCount*3;
  spheresIndirectArgs[0].firstInstance = 0;
}

bool traceScene(Ray ray, out HitResult hit) {
  bool bHit = false;
  uint triCount = globalSceneBuffer[0].triCount;
  for (int i = 0; i < triCount && i < MAX_SCENE_TRIS; i++) {
    HitResult h;
    if (traceTri(triBuffer[i], ray, h)) {
      if (!bHit || h.t < hit.t) {
        hit = h;
      }
      bHit = true;
    }
  }

  uint sphereCount = globalSceneBuffer[0].sphereCount;
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

vec3 sampleRandomLight(inout uvec2 seed, vec3 o, out vec3 dir, out float pdf) {
  uint lightCount = globalSceneBuffer[0].lightCount;
  pdf = 1.0 / float(lightCount); // TODO not quite right...
  uint lightIdx = uint(rng(seed) * lightCount) % lightCount;
  Light light = lightBuffer[lightIdx];
  if (light.type == LIGHT_TYPE_TRI) {
    Tri t = triBuffer[light.idx];
    Material mat = materialBuffer[t.matID];

    vec3 a = sceneVertexBuffer[t.i0].pos;
    vec3 ab = sceneVertexBuffer[t.i1].pos - a;
    vec3 ac = sceneVertexBuffer[t.i2].pos - a;

    vec3 uvw = randVec3(seed);
    uvw /= uvw.x + uvw.y + uvw.z;

    vec3 lightPos = a + uvw.x * ab + uvw.y * ac;
    vec3 lightDiff = lightPos - o;
    float lightDist = length(lightDiff);

    Ray ray;
    ray.d = lightDiff / lightDist;
    ray.o = o;
    
    vec3 lightNormal = normalize(cross(ab, ac));
    float LdotNl = dot(ray.d, lightNormal);
    if (LdotNl >= 0.0)
      return 0.0.xxx;
    
    HitResult hit;
    if (!traceScene(ray, hit) || hit.t < (lightDist - BOUNCE_BIAS))
      return 0.0.xxx;

    dir = ray.d;
    return -LdotNl * mat.emissive; // TODO: any other attenuation needed here?
  }
  // TODO support sphere lights..

  return 0.0.xxx;
}


#ifdef IS_VERTEX_SHADER
SceneVertexOutput VS_SceneTriangles() {
  uint triIdx = gl_VertexIndex / 3;
  vec3 v[3] = {
    sceneVertexBuffer[3*triIdx].pos,
    sceneVertexBuffer[3*triIdx+1].pos,
    sceneVertexBuffer[3*triIdx+2].pos};
  SceneVertexOutput OUT;
  OUT.pos = v[gl_VertexIndex % 3];
  OUT.normal = normalize(cross(v[1] - v[0], v[2] - v[0])); 
  OUT.mat = materialBuffer[triBuffer[triIdx].matID];
  gl_Position = camera.projection * camera.view * vec4(OUT.pos, 1.0);
  
  return OUT;
}

SceneVertexOutput VS_SceneSpheres() {
  vec3 v = sceneVertexBuffer[gl_VertexIndex].pos;
  Sphere s = sphereBuffer[gl_InstanceIndex];

  SceneVertexOutput OUT;
  OUT.pos = v * s.r + s.c;
  OUT.normal = v;
  OUT.mat = materialBuffer[s.matID];
  gl_Position = camera.projection * camera.view * vec4(OUT.pos, 1.0);
  
  return OUT;
}
#endif // IS_VERTEX_SHADER

// EXAMPLE SCENES
#ifdef IS_COMP_SHADER
void CS_InitCornellBox() {
  startSceneBuild();
  
  float cornellBoxScale = 15.0;
  g_sceneBuilder.translation = vec3(10.0, 5.0, -1.0);
  {
    Material mat;
    mat.diffuse = 1.0.xxx;
    mat.roughness = 0.4;
    mat.emissive = 0.0.xxx;
    mat.metallic = 0.0;
    mat.specular = 0.04.xxx;
    mat.transmission = 0.0;
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
    
    mat.diffuse = 0.8.xxx;
    
    pushMaterial(mat);

    // main room
    g_sceneBuilder.bFlipNormal = true;
    pushBox(0.0.xxx, mat3(cornellBoxScale));
    // popQuad(); // remove front face
    g_sceneBuilder.bFlipNormal = false;
    
    // color side-walls
    mat.diffuse = vec3(0.4, 0.0, 0.0);
    mat.specular = 0.1.xxx;
    triBuffer[g_sceneBuilder.triCount-8].matID = g_sceneBuilder.matID;
    triBuffer[g_sceneBuilder.triCount-7].matID = g_sceneBuilder.matID;
    pushMaterial(mat);

    mat.diffuse = vec3(0.0, 0.4, 0.0);
    triBuffer[g_sceneBuilder.triCount-6].matID = g_sceneBuilder.matID;
    triBuffer[g_sceneBuilder.triCount-5].matID = g_sceneBuilder.matID;
    pushMaterial(mat);

    // glossy back wall
    mat.diffuse = 0.05.xxx;
    mat.specular = 0.45.xxx;
    mat.roughness = 0.025;
    triBuffer[g_sceneBuilder.triCount-4].matID = g_sceneBuilder.matID;
    triBuffer[g_sceneBuilder.triCount-3].matID = g_sceneBuilder.matID;
    pushMaterial(mat);

    // add light
    mat.emissive = vec3(15.0, 20.0, 10.0);
    pushMaterial(mat);
    float lightSize = 6.0;
    float lightHeight = cornellBoxScale - 0.5;
    pushQuad(
      vec3(-lightSize, lightHeight, -lightSize),
      vec3(-lightSize, lightHeight, lightSize),
      vec3(lightSize, lightHeight, lightSize),
      vec3(lightSize, lightHeight, -lightSize));
  }

  {
    Material mat;
    mat.diffuse = vec3(0.0, 1.0, 1.0);// * 0.1;
    mat.roughness = 0.1;
    mat.specular = 0.2.xxx;
    mat.emissive = 0.0.xxx;
    mat.metallic = 0.0;
    mat.transmission = 0.0;
    pushMaterial(mat);

    pushSphere(vec3(-0.45, 0.35, -0.25) * cornellBoxScale, 0.35 * cornellBoxScale);
  }

  {
    Material mat;
    mat.diffuse = vec3(0.5, 0.5, 1.0);
    mat.roughness = 0.04;
    mat.specular = 0.02.xxx;
    mat.emissive = 0.0.xxx;
    mat.metallic = 0.0;
    mat.transmission = 1.0;
    pushMaterial(mat);

    pushSphere(vec3(0.45, 0.2 + 0.25, 0.15) * cornellBoxScale, 0.25 * cornellBoxScale);
  }

  finishSceneBuild();
}
#endif // IS_COMP_SHADER

#endif // _SCENE_GLSL_