
#include <Misc/Constants.glsl>
#include <Misc/Sampling.glsl>
#include <Misc/ReconstructPosition.glsl>

#include <FlrLib/Scene/Intersection.glsl>
#include <FlrLib/Scene/Scene.glsl>
#include <FlrLib/PBR/BRDF.glsl>
#include <FlrLib/Deferred/Deferred.glsl>

vec3 computeDir(vec2 uv) {
	vec2 d = uv * 2.0 - 1.0;

	vec4 target = camera.inverseProjection * vec4(d, 1.0.xx);
	return (camera.inverseView * vec4(normalize(target.xyz), 0)).xyz;
}

vec3 sampleEnv(vec3 dir) {
  return 1.0.xxx;
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

void applyOverrides(inout Material mat) {
  if (OVERRIDE_ROUGHNESS)
    mat.roughness = ROUGHNESS;
  if (OVERRIDE_DIFFUSE)
    mat.diffuse = DIFFUSE.xyz;
  if (OVERRIDE_SPECULAR)
    mat.specular = SPECULAR.xyz;
}

#define TRACE_MODE_DIFFUSE 0
#define TRACE_MODE_SPEC 1
vec4 samplePath(inout uvec2 seed, Ray ray, HitResult hit, Material mat, uint traceMode) {
  vec4 color = vec4(0.0.xxx, 1.0);

  vec3 throughput = 1.0.xxx;
  for (int bounce = 0; bounce < BOUNCES+1; bounce++) {
    bool bResult = true;
    if (bounce > 0) {
      bResult = traceScene(ray, hit);
      mat = materialBuffer[hit.matID];
      applyOverrides(mat);
    } 
    
    if (!bResult) {
      color.rgb += throughput * sampleEnv(ray.d);
      break;
    }

    if (length(mat.emissive) > 0.0)
    {
      color.rgb += throughput * mat.emissive;
      break;
    }

    if (length(mat.emissive) > 0.0) {
      color.rgb += throughput * mat.emissive;
      break;
    }

    uint brdfMode = BRDF_MODE;
    if (traceMode == TRACE_MODE_SPEC && bounce == 0) {
      brdfMode = 0;
      mat.diffuse = 0.0.xxx;
    } 
    
    vec3 reflDir;
    float pdf;
    vec3 f;
    if (brdfMode == 0) {
      f = sampleMicrofacetBrdf(
        randVec2(seed), -ray.d, hit.n,
        mat,
        reflDir, pdf);
      float pdf2;
      // f = evaluateMicrofacetBrdf(-ray.d, reflDir, hit.n, mat, pdf2);
    } 
    else if (brdfMode == 1) {
      float samplePdf;
      reflDir = LocalToWorld(hit.n) * sampleHemisphereCosine(seed, samplePdf);
      f = evaluateMicrofacetBrdf(-ray.d, reflDir, hit.n, mat, pdf);
      pdf = samplePdf;
    } else if (brdfMode == 2) {
      float samplePdf;
      reflDir = LocalToWorld(hit.n) * sampleHemisphereCosine(seed, samplePdf);
      f = mat.diffuse;
      pdf = 1.0;
    }

    // if (pdf < 0.005) {
    //   f = 0.0.xxx;
    //   pdf = 1.0;
    // }

    ray.d = normalize(reflDir);
    ray.o = hit.p + BOUNCE_BIAS * ray.d;

    throughput *= f / pdf;
  }

  return color;
}

////////////////////////// COMPUTE SHADERS //////////////////////////

#ifdef IS_COMP_SHADER
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

void CS_TraceDiffuse() {
  uvec2 pixelId = uvec2(gl_GlobalInvocationID.xy);
  if (pixelId.x >= DIFFUSE_BUF_WIDTH || pixelId.y >= DIFFUSE_BUF_HEIGHT) return;
  
  vec2 uv = vec2(pixelId + 0.5.xx) / vec2(DIFFUSE_BUF_WIDTH, DIFFUSE_BUF_HEIGHT);
  uvec2 seed = pixelId * uvec2(uniforms.frameCount, uniforms.frameCount+1);

  float dRaw = texture(depthTexture, uv).r;
  vec3 pos = reconstructPosition(uv, dRaw, camera.inverseProjection, camera.inverseView);

  PackedGBuffer packed = PackedGBuffer(
      texture(gbuffer0Texture, uv),
      texture(gbuffer1Texture, uv),
      texture(gbuffer2Texture, uv));
  
  HitResult initHit;
  Material mat;
  unpackGBuffer(packed, mat, initHit.n);
  applyOverrides(mat);
  
  initHit.p = pos;
  initHit.t = 1.0;
  initHit.matID = 0;

  Ray ray;
  ray.o = camera.inverseView[3].xyz;
  ray.d = normalize(pos - ray.o);

  vec4 diffuse = samplePath(seed, ray, initHit, mat, TRACE_MODE_DIFFUSE);
  vec4 prevDiffuse = imageLoad(diffuseBuffer, ivec2(pixelId));
  if (ACCUMULATE && (uniforms.inputMask & INPUT_BIT_SPACE) == 0) {
    diffuse.rgb = mix(prevDiffuse.rgb, diffuse.rgb, 1.0 / globalStateBuffer[0].accumulationFrames);
  }
  
  imageStore(diffuseBuffer, ivec2(pixelId), diffuse);
}

void CS_TraceSpec() {
  uvec2 pixelId = uvec2(gl_GlobalInvocationID.xy);
  if (pixelId.x >= SPEC_BUF_WIDTH || pixelId.y >= SPEC_BUF_HEIGHT) return;
  
  vec2 uv = vec2(pixelId + 0.5.xx) / vec2(SPEC_BUF_WIDTH, SPEC_BUF_HEIGHT);
  uvec2 seed = pixelId * uvec2(uniforms.frameCount, uniforms.frameCount+1);

  float dRaw = texture(depthTexture, uv).r;
  vec3 pos = reconstructPosition(uv, dRaw, camera.inverseProjection, camera.inverseView);

  PackedGBuffer packed = PackedGBuffer(
      texture(gbuffer0Texture, uv),
      texture(gbuffer1Texture, uv),
      texture(gbuffer2Texture, uv));
  
  HitResult initHit;
  Material mat;
  unpackGBuffer(packed, mat, initHit.n);
  applyOverrides(mat);
  
  initHit.p = pos;
  initHit.t = 1.0;
  initHit.matID = 0;

  Ray ray;
  ray.o = camera.inverseView[3].xyz;
  ray.d = normalize(pos - ray.o);

  vec4 spec = samplePath(seed, ray, initHit, mat, TRACE_MODE_SPEC);
  vec4 prevSpec = imageLoad(specularBuffer, ivec2(pixelId));
  if (ACCUMULATE && (uniforms.inputMask & INPUT_BIT_SPACE) == 0) {
    spec.rgb = mix(prevSpec.rgb, spec.rgb, 1.0 / globalStateBuffer[0].accumulationFrames);
  }
  
  imageStore(specularBuffer, ivec2(pixelId), spec);
}
#endif // IS_COMP_SHADER

////////////////////////// VERTEX SHADERS //////////////////////////

#ifdef IS_VERTEX_SHADER
DisplayVertex VS_Display() {
  return DisplayVertex(VS_FullScreen());
}
#endif // IS_VERTEX_SHADER

////////////////////////// PIXEL SHADERS //////////////////////////

#ifdef IS_PIXEL_SHADER
#ifdef SCENE_PASS
void PS_Scene(SceneVertexOutput IN) {
  // this fixes interpolated smooth normals that end up facing away from the camera at glancing angles
  // specifically noticed this issue on triangulated spheres with smooth normals 
  vec3 dir = normalize(IN.pos - camera.inverseView[3].xyz);
  float dirDotN = dot(dir, IN.normal);
  if (dirDotN >= 0.0)
    IN.normal -= 2.0 * dirDotN * dir;

  PackedGBuffer p = packGBuffer(IN.mat, normalize(IN.normal));
  outGBuffer0 = p.gbuffer0;
  outGBuffer1 = p.gbuffer1;
  outGBuffer2 = p.gbuffer2;
}
#endif

#ifdef DISPLAY_PASS
void PS_Display(DisplayVertex IN) {
  vec3 diffuse = texture(diffuseTexture, IN.uv).rgb;
  vec3 spec = texture(specularTexture, IN.uv).rgb;
  if (RENDER_MODE == 0)
    outColor = vec4(0.5 * (diffuse + spec), 1.0);
  else if (RENDER_MODE == 1)
    outColor = vec4(diffuse, 1.0);
  else 
    outColor = vec4(spec, 1.0);
  outColor.rgb = vec3(1.0) - exp(-outColor.rgb * EXPOSURE);
  
  if (GBUFFER_DBG_MODE == 1) {
    outColor = texture(gbuffer0Texture, IN.uv);
  } else if (GBUFFER_DBG_MODE == 2) {
    outColor = texture(gbuffer1Texture, IN.uv);
  } else if (GBUFFER_DBG_MODE == 3) {
    float dRaw = texture(depthTexture, IN.uv).r;
    vec3 pos = reconstructPosition(IN.uv, dRaw, camera.inverseProjection, camera.inverseView);
    outColor = vec4(fract(pos+0.1.xxx), 1.0);
  } else if (GBUFFER_DBG_MODE == 4) {
    outColor = texture(gbuffer2Texture, IN.uv);
  }
}
#endif
#endif // IS_PIXEL_SHADER

