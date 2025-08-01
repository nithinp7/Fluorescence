
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

vec4 samplePath(inout uvec2 seed, Ray ray, HitResult hit, Material mat, bool dbgViz) {
  uint dbgLineCount = 0;
  uvec2 colSeed = uvec2(0, 0);
  if (dbgViz) {
    uint s = globalStateBuffer[0].dbgGen;
    colSeed = uvec2(s, s+1);
    dbgLineCount = rayDbgIndirectArgs[0].vertexCount/2;
  }
  
  if (dbgLineCount > MAX_LINE_VERTS/2)
    dbgLineCount %= MAX_LINE_VERTS/2;
  
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

    if (dbgViz && bounce > 0) {
      vec3 c = randVec3(colSeed) * 100.0 / pow(bounce + 1, 2.0);
      rayDbgLines[2*dbgLineCount].pos = vec4(ray.o, 1.0);
      rayDbgLines[2*dbgLineCount].color = vec4(c, 1.0);
      rayDbgLines[2*dbgLineCount+1].pos = vec4(hit.p, 1.0);
      rayDbgLines[2*dbgLineCount+1].color = vec4(c, 1.0);

      if (any(isnan(ray.o)) || any(isnan(hit.p)) || any(isnan(c))) 
      {
        globalStateBuffer[0].errColor = vec4(1.0, 0.0, 0.0, 1.0);
      }
      dbgLineCount++;
    }

    if (length(mat.emissive) > 0.0) {
      if (dbgViz && bounce == 0)
        globalStateBuffer[0].errColor = vec4(1.0, 1.0, 0.0, 1.0);
      color.rgb += throughput * mat.emissive;
      break;
    }

    vec3 reflDir;
    float pdf;
    vec3 f;

    uint brdfMode = BRDF_MODE;
    // TODO - this is the new "direct light + indirect continuation" impl
    // might want to consolidate with the old code below or cleanup in general
    if (brdfMode == 3) {
      // TODO the light pdf is definitely not correct,
      // test with more complicated lighting setups
      float pdfLight;
      vec3 Li = sampleRandomLight(seed, hit.p, reflDir, pdfLight);
      float pdf2;
      vec3 fLight = evaluateMicrofacetBrdf(-ray.d, reflDir, hit.n, mat, pdf2);
      color.rgb += throughput * fLight * Li / pdfLight;

      // float wsum = length(10.0 * BRDF_MIX * mat.specular) + length(mat.diffuse);
      // float p = length(10.0 * BRDF_MIX * mat.specular) / wsum ;//* 
      // float p = (1.0 - mat.roughness * mat.roughness);
      // float p = 1.0 - mat.roughness * length(mat.diffuse);
      // float p = pow(1.0 - mat.roughness, BRDF_MIX * 10.0);
      float p = 1.0 - mat.roughness;

      if (rng(seed) < p || mat.diffuse == 0.0.xxx) {
        // choose spec lobe for continuation
        mat.diffuse = 0.0.xxx;
        f = sampleMicrofacetBrdf(
          randVec2(seed), -ray.d, hit.n,
          mat,
          reflDir, pdf);// * p;
      } else {
        // choose diffuse lobe for continuation
        float samplePdf;
        reflDir = LocalToWorld(hit.n) * sampleHemisphereCosine(seed, samplePdf);
        f = mat.diffuse;// * (1.0 - p);// / (1.0 - p);
        pdf = 1.0;
      }
    }

    // TODO - old paths... single lobe sampling, no direct light sampling...
    if (brdfMode == 0) {
      f = sampleMicrofacetBrdf(
        randVec2(seed), -ray.d, hit.n,
        mat,
        reflDir, pdf);
    } else if (brdfMode == 1) {
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

    // if (pdf < 0.001) {
    //   f = 0.0.xxx;
    //   pdf = 1.0;
    // }

    ray.d = normalize(reflDir);
    ray.o = hit.p + BOUNCE_BIAS * ray.d;

    throughput *= f / pdf;
  }

  if (dbgViz) {
    IndirectArgs args;
    args.vertexCount = 2*dbgLineCount;
    args.instanceCount = 1;
    args.firstVertex = 0;
    args.firstInstance = 0;
    rayDbgIndirectArgs[0] = args;
  }

  return color;
}

////////////////////////// COMPUTE SHADERS //////////////////////////

#ifdef IS_COMP_SHADER
void CS_Tick() {
  if ((uniforms.inputMask & INPUT_BIT_C) != 0) {
    rayDbgIndirectArgs[0].vertexCount = 0;
    globalStateBuffer[0].errColor = 0.0.xxxx;
    globalStateBuffer[0].accumulationFrames = 1;
  }

  if ((uniforms.inputMask & INPUT_BIT_LEFT_MOUSE) != 0) {
    if ((uniforms.prevInputMask & INPUT_BIT_LEFT_MOUSE) == 0) {
      globalStateBuffer[0].dbgGen++;
      globalStateBuffer[0].dbgPixelId = uvec2(uniforms.mouseUv * vec2(SCREEN_WIDTH, SCREEN_HEIGHT));
    }
  }

  if (!ACCUMULATE || (uniforms.inputMask & INPUT_BIT_SPACE) != 0) 
  {
    globalStateBuffer[0].accumulationFrames = 1;
  } 
  else 
  {
    globalStateBuffer[0].accumulationFrames++;
  }
}

void CS_PathTrace() {
  // uint phase = uniforms.frameCount % (TEMPORAL_UPSCALE_RATIO * TEMPORAL_UPSCALE_RATIO);
  // uvec2 localPixelId = uvec2(0, 0);//uvec2(phase/TEMPORAL_UPSCALE_RATIO, phase%TEMPORAL_UPSCALE_RATIO);

  uvec2 pixelId = uvec2(gl_GlobalInvocationID.xy);//uvec2(TEMPORAL_UPSCALE_RATIO * gl_GlobalInvocationID.xy) + localPixelId;
  if (pixelId.x >= SCREEN_WIDTH || pixelId.y >= SCREEN_HEIGHT) return;
  
  vec2 uv = vec2(pixelId + 0.5.xx) / vec2(SCREEN_WIDTH, SCREEN_HEIGHT);
  uint frames = globalStateBuffer[0].accumulationFrames;
  uvec2 seed = pixelId * uvec2(frames, frames+1);

  float dRaw = texture(depthTexture, uv).r;
  vec3 pos = reconstructPosition(uv, dRaw, camera.inverseProjection, camera.inverseView);

  PackedGBuffer packed = PackedGBuffer(
      texture(gbuffer0Texture, uv),
      texture(gbuffer1Texture, uv),
      texture(gbuffer2Texture, uv),
      texture(gbuffer3Texture, uv));

  vec4 color;
  if (dRaw == 1.0) {
    vec3 dir = computeDir(uv);
    color = vec4(sampleEnv(dir), 1.0);
  } else {
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

    bool bRayDbg = 
        (uniforms.inputMask & INPUT_BIT_LEFT_MOUSE) != 0 && 
        (pixelId == globalStateBuffer[0].dbgPixelId);
    color = samplePath(seed, ray, initHit, mat, bRayDbg);
    if (bRayDbg && any(isnan(color))) {
      globalStateBuffer[0].errColor = vec4(1.0, 0.0, 0.0, 1.0);
    }
  }

  vec4 prevColor = imageLoad(accumulationBuffer, ivec2(pixelId));
  float blend = 1.0;
  if (ACCUMULATE && (uniforms.inputMask & INPUT_BIT_SPACE) == 0) 
  {
    blend = 1.0 / frames;
  }
  blend = max(blend, 0.2);
  
  {
    color.rgb = (1.0 - blend) * prevColor.rgb + blend * color.rgb;
    // color.rgb = mix(prevColor.rgb, color.rgb, blend);
  }
  
  imageStore(accumulationBuffer, ivec2(pixelId), color);
}
#endif // IS_COMP_SHADER

////////////////////////// VERTEX SHADERS //////////////////////////

#ifdef IS_VERTEX_SHADER
SceneVertexOutput VS_RayDbgLines() {
  LineVert vert = rayDbgLines[gl_VertexIndex];

  vec3 ldir = normalize(rayDbgLines[gl_VertexIndex|1].pos.xyz - rayDbgLines[gl_VertexIndex&~1].pos.xyz);
  vec3 cdir = normalize(vert.pos.xyz - camera.inverseView[3].xyz);
  vec3 perp = normalize(cross(ldir, cdir));
  vec3 norm = -cross(perp, ldir); // negative ??

  SceneVertexOutput OUT;
  OUT.pos = vert.pos.xyz; 
  OUT.normal = norm;
  OUT.mat.diffuse = 1.0.xxx;
  OUT.mat.roughness = 0.2;
  OUT.mat.emissive = vert.color.rgb;
  OUT.mat.metallic = 0.0;
  OUT.mat.specular = 0.04.xxx;

  gl_Position = camera.projection * camera.view * vert.pos;
  
  return OUT;
}

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
  outGBuffer3 = p.gbuffer3;
}
#endif

#ifdef DISPLAY_PASS
void PS_Display(DisplayVertex IN) {
  // if (IN.uv.x < 0.05 && IN.uv.y < 0.05) {
  //   outColor = globalStateBuffer[0].errColor;
  //   return;
  // }

  outColor = texture(accumulationTexture, IN.uv);
  outColor.rgb = vec3(1.0) - exp(-outColor.rgb * EXPOSURE);
  
  if (GBUFFER_DBG_MODE == 0) {
    outColor = texture(gbuffer0Texture, IN.uv);
  } else if (GBUFFER_DBG_MODE == 1) {
    outColor = texture(gbuffer1Texture, IN.uv);
  } else if (GBUFFER_DBG_MODE == 2) {
    outColor = texture(gbuffer2Texture, IN.uv);
  } else if (GBUFFER_DBG_MODE == 3) {
    outColor = texture(gbuffer3Texture, IN.uv);
  } else if (GBUFFER_DBG_MODE == 4) {
    float dRaw = texture(depthTexture, IN.uv).r;
    vec3 pos = reconstructPosition(IN.uv, dRaw, camera.inverseProjection, camera.inverseView);
    outColor = vec4(fract(pos+0.1.xxx), 1.0);
  }
}

void PS_RayDbgLines(SceneVertexOutput IN) {
  outColor = vec4(0.01 * IN.mat.emissive, 1.0);
}
#endif
#endif // IS_PIXEL_SHADER

