
#include <Misc/Constants.glsl>
#include <Misc/Sampling.glsl>
#include <Misc/ReconstructPosition.glsl>

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

vec3 sampleSpec(inout uvec2 seed, HitResult surfaceHit, Material mat, Ray ray, out float pdf) {
  vec3 reflDir;
  vec3 f = sampleMicrofacetBrdf(
    randVec2(seed), -ray.d, surfaceHit.n,
    mat,
    reflDir, pdf);
  Ray specRay;
  specRay.d = normalize(reflDir);
  specRay.o = surfaceHit.p + specRay.d * BOUNCE_BIAS;
  HitResult specHit;
  if (traceScene(specRay, specHit)) {
    Material specMat = materialBuffer[specHit.matID];
    return f * specMat.emissive;
  } else {
    return 0.0.xxx;//sampleEnv(specRay.d) * abs(dot(surfaceHit.n, specRay.d));
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
    
    if (OVERRIDE_ROUGHNESS) {
      mat.roughness = ROUGHNESS;
    }

    if (OVERRIDE_DIFFUSE) {
      mat.diffuse = DIFFUSE.xyz;
    }

    if (OVERRIDE_SPECULAR) {
      mat.specular = SPECULAR.xyz;
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

    if (length(mat.emissive) > 0.0) {
      // if (SPEC_SAMPLE) //TODO - we are probably double counting without this...
      //   break;
      color.rgb += throughput * mat.emissive;
      break;
    }

    uint brdfMode = BRDF_MODE;
    if (brdfMode == 2) 
      brdfMode = (rng(seed) < BRDF_MIX) ? 0 : 1;
    
    vec3 reflDir;
    float pdf;
    vec3 f;
    if (brdfMode == 0) {
      f = sampleMicrofacetBrdf(
        randVec2(seed), -ray.d, hit.n,
        mat,
        reflDir, pdf);
    }
    else {
      if (SPEC_SAMPLE) {
        float specPdf;
        vec3 specLo = sampleSpec(seed, hit, mat, ray, specPdf);
        color.rgb += throughput * specLo / specPdf;
      }

      float samplePdf;
      reflDir = LocalToWorld(hit.n) * sampleHemisphereCosine(seed, samplePdf);
      f = evaluateMicrofacetBrdf(-ray.d, reflDir, hit.n, mat, pdf);
      pdf = samplePdf;
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
  uvec2 seed = uvec2(gl_FragCoord.xy) * uvec2(uniforms.frameCount, uniforms.frameCount+1);
  float emissionIntensity = length(IN.mat.emissive);
  outGBuffer0 = vec4((emissionIntensity > 0.0) ? IN.mat.emissive / emissionIntensity : IN.mat.diffuse,1.0);
  outGBuffer1 = vec4(0.5 * IN.normal + 0.5.xxx, 1.0);
  outGBuffer2 = vec4(IN.mat.roughness, IN.mat.metallic, emissionIntensity, 1.0); // todo should be non-linearly encoded...
}
#endif

#ifdef DISPLAY_PASS
void PS_Display(DisplayVertex IN) {
  uvec2 seed = uvec2(gl_FragCoord.xy) * uvec2(uniforms.frameCount, uniforms.frameCount+1);

  outColor = texture(accumulationTexture, IN.uv);
  float dRaw = texture(depthTexture, IN.uv).r;
  vec3 pos = reconstructPosition(IN.uv, dRaw, camera.inverseProjection, camera.inverseView);

  vec3 roughnessMetallicEmissive = texture(gbuffer2Texture, IN.uv).rgb;

  HitResult initHit;
  initHit.p = pos;
  initHit.n = texture(gbuffer1Texture, IN.uv).rgb * 2.0 - 1.0.xxx;
  initHit.t = 1.0;
  initHit.matID = 0;

  Ray ray;
  ray.o = camera.inverseView[3].xyz;
  ray.d = normalize(pos - ray.o);

  Material mat;
  mat.diffuse = texture(gbuffer0Texture, IN.uv).rgb;
  mat.roughness = roughnessMetallicEmissive.x;
  mat.emissive = roughnessMetallicEmissive.z * mat.diffuse;
  mat.metallic = roughnessMetallicEmissive.y;
  mat.specular = 0.04.xxx;

  outColor = samplePath(seed, ray, initHit, mat);

  if (GBUFFER_DBG_MODE == 1) {
    outColor = texture(gbuffer0Texture, IN.uv);
  } else if (GBUFFER_DBG_MODE == 2) {
    outColor = texture(gbuffer1Texture, IN.uv);
  } else if (GBUFFER_DBG_MODE == 3) {
    outColor = vec4(fract(pos+0.1.xxx), 1.0);
  } else if (GBUFFER_DBG_MODE == 4) {
    outColor = texture(gbuffer2Texture, IN.uv);
  }
}
#endif
#endif // IS_PIXEL_SHADER

