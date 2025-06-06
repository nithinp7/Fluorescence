
#include <Misc/Constants.glsl>
#include <Misc/Sampling.glsl>

#include <FlrLib/Scene/Intersection.glsl>
#include <FlrLib/Scene/Scene.glsl>
#include <FlrLib/PBR/BRDF.glsl>

vec3 computeDir(vec2 uv) {
	vec2 d = uv * 2.0 - 1.0;

	vec4 target = camera.inverseProjection * vec4(d, 1.0.xx);
	return (camera.inverseView * vec4(normalize(target.xyz), 0)).xyz;
}

vec3 sampleEnv(vec3 dir) {
  float c = 5.0;
  vec3 n = 0.5 * normalize(dir) + 0.5.xxx;
  if (BACKGROUND == 0) {
    return round(n * c) / c;
  } else if (BACKGROUND == 1) {
    return round(fract(n * c));
  } else if (BACKGROUND == 2) {
    return round(n);
  } else {
    float f = n.x + n.y + n.z;
    return max(round(fract(f * c)), 0.2).xxx;
  }
}

vec4 samplePath(inout uvec2 seed, Ray ray, HitResult hit, Material mat) {
  vec4 color = vec4(0.0.xxx, 1.0);

  vec3 throughput = 1.0.xxx;
  for (int bounce = 0; bounce < BOUNCES+1; bounce++) {
    bool bResult = true;
    if (bounce > 0) {
      bResult = traceScene(ray, hit);
      mat = materialBuffer[hit.matID];
    } 

    if (!bResult) {
      color.rgb = throughput * sampleEnv(ray.d);
      break;
    }

    if (length(mat.emissive) > 0.0)
    {
      color.rgb += throughput * mat.emissive;
      break;
    }

    // float F0 = 0.04;
    // vec3 F = fresnelSchlick(abs(dot(hit.N, dir)), F0.xxx, mat.roughness);

    vec3 reflDir;
    float pdf;
    vec3 f;
    if (BRDF_MODE == 0) {
      f = sampleMicrofacetBrdf(
        randVec2(seed), -ray.d, hit.n,
        mat,
        reflDir, pdf);
    }
    else { // if (BRDF_MODE == 1) {
      f = 1.0.xxx; // ??
      reflDir = LocalToWorld(hit.n) * sampleHemisphereCosine(seed, pdf);
      pdf = 1.0; // pdf and f cancel out...
    }
    
    throughput *= f / pdf;

    const float BOUNCE_BIAS = 0.001;
    ray.d = normalize(reflDir);
    ray.o = hit.p + BOUNCE_BIAS * ray.d;
  }

  return color;
}

////////////////////////// COMPUTE SHADERS //////////////////////////

#ifdef IS_COMP_SHADER
void CS_Init() {
  initScene_CornellBox();
  sceneIndirectArgs[0].vertexCount = globalStateBuffer[0].triCount * 3;
  sceneIndirectArgs[0].instanceCount = 1;
  sceneIndirectArgs[0].firstVertex = 0; 
  sceneIndirectArgs[0].firstInstance = 0; 
}

void CS_Tick() {
  if (!ACCUMULATE || (uniforms.inputMask & INPUT_BIT_SPACE) != 0) 
  {
    globalStateBuffer[0].accumulationFrames = 1;
  } 
  else 
  {
    globalStateBuffer[0].accumulationFrames++;
  }
}
#endif // IS_COMP_SHADER

////////////////////////// VERTEX SHADERS //////////////////////////

#ifdef IS_VERTEX_SHADER
VertexOutput VS_Lighting() {
  uint triIdx = gl_VertexIndex / 3;
  vec3 v[3] = {
    sceneVertexBuffer[3*triIdx].pos,
    sceneVertexBuffer[3*triIdx+1].pos,
    sceneVertexBuffer[3*triIdx+2].pos};
  VertexOutput OUT;
  OUT.pos = v[gl_VertexIndex % 3];
  OUT.normal = normalize(cross(v[1] - v[0], v[2] - v[0])); 
  OUT.mat = materialBuffer[triBuffer[triIdx].matID];
  gl_Position = camera.projection * camera.view * vec4(OUT.pos, 1.0);
  
  return OUT;
}

DisplayVertex VS_Display() {
  return DisplayVertex(VS_FullScreen());
}
#endif // IS_VERTEX_SHADER

////////////////////////// PIXEL SHADERS //////////////////////////

#ifdef IS_PIXEL_SHADER
void PS_Lighting(VertexOutput IN) {
  uvec2 seed = uvec2(gl_FragCoord.xy) * uvec2(uniforms.frameCount, uniforms.frameCount+1);
  float d = length(IN.pos - camera.inverseView[3].xyz);
  if (RENDER_MODE == 0)
  {
    outColor = vec4(IN.mat.diffuse,1.0);
    HitResult initHit;
    initHit.p = IN.pos;
    initHit.n = IN.normal;
    initHit.t = 1.0;
    initHit.matID = 0;

    Ray ray;
    ray.o = camera.inverseView[3].xyz;
    ray.d = normalize(IN.pos - ray.o);
    outColor = samplePath(seed, ray, initHit, IN.mat);
  }
  else if (RENDER_MODE == 1) 
    outColor = vec4(0.5 * IN.normal + 0.5.xxx, 1.0);  
  else 
    outColor = vec4(fract(0.1 * d).xxx, 1.0);
}

void PS_Display(DisplayVertex IN) {
  outColor = texture(accumulationTexture, IN.uv);
}
#endif // IS_PIXEL_SHADER

