#include <PathTracing/BRDF.glsl>

#include <Misc/Sampling.glsl>
#include <Misc/ReconstructPosition.glsl>

vec3 computeDir(vec2 uv) {
	vec2 d = uv * 2.0 - 1.0;

	vec4 target = camera.inverseProjection * vec4(d, 1.0.xx);
	return (camera.inverseView * vec4(normalize(target.xyz), 0)).xyz;
}

vec3 sampleEnv(vec3 dir) {
  float cosphi = cos(LIGHT_PHI); float sinphi = sin(LIGHT_PHI);
  float costheta = cos(LIGHT_THETA); float sintheta = sin(LIGHT_THETA);
  vec3 L = normalize(vec3(costheta * cosphi, sinphi, sintheta * cosphi));

  float c = 5.0;
  vec3 n = 0.5 * normalize(dir) + 0.5.xxx;
  if (BACKGROUND == 0) {
    float x = 0.5 + 0.5 * dot(dir, L);
    // x = LIGHT_STRENGTH * pow(x, LIGHT_STRENGTH * 10.0) + 0.01;
    return LIGHT_STRENGTH * pow(x, 4.0).xxx;
  } else if (BACKGROUND == 1) {
    return round(fract(LocalToWorld(L) * n * c + 0.1 * uniforms.time));
  } else if (BACKGROUND == 2) {
    return round(n);
  } else if (BACKGROUND == 3) {
    float f = n.x + n.y + n.z;
    return max(round(fract(f * c)), 0.2).xxx;
  } else {
    float x = 0.5 + 0.5 * dot(dir,L);
    // x = pow(x, LIGHT_STRENGTH) + 0.01;
    return LIGHT_STRENGTH * x * round(n * c) / c;
  }
}

////////////////////////// COMPUTE SHADERS //////////////////////////

#ifdef IS_COMP_SHADER
void CS_CopyDisplayImage() {
  ivec2 pixelId = ivec2(gl_GlobalInvocationID.xy);
  if (pixelId.x >= SCREEN_WIDTH || pixelId.y >= SCREEN_HEIGHT) {
    return;
  }

  vec4 c = vec4(texelFetch(DisplayTexture, pixelId, 0).rgb, 1.0);
  if ((uniforms.inputMask & INPUT_BIT_SPACE) != 0)
    c = vec4(0.0.xxx, 1.0);
  imageStore(PrevDisplayImage, pixelId, c);

  float d = texelFetch(DepthTexture, pixelId, 0).r;
  if ((uniforms.inputMask & INPUT_BIT_SPACE) != 0)
    d = 0.0;
  imageStore(PrevDepthImage, pixelId, d.xxxx);
}
#endif // IS_COMP_SHADER

////////////////////////// VERTEX SHADERS //////////////////////////

#ifdef DISPLAY_PASS
#ifdef IS_VERTEX_SHADER
VertexOutput VS_Background() {
  VertexOutput OUT;

  OUT.uv = VS_FullScreen();
  gl_Position = vec4(OUT.uv * 2.0 - 1.0, 0.0, 1.0);

  return OUT;
}

#ifdef _ENTRY_POINT_VS_Obj
// TODO automate...
layout(location = 0) in vec3 inPosition;
layout(location = 1) in vec3 inNormal;
layout(location = 2) in vec2 inUv;

VertexOutput VS_Obj() {
  VertexOutput OUT;

  vec4 worldPos = camera.view * vec4(inPosition, 1.0);
  vec4 projPos = camera.projection * worldPos;
  gl_Position = projPos;
  OUT.position = projPos;
  OUT.prevPosition = camera.projection * camera.prevView * vec4(inPosition, 1.0);
  OUT.normal = inNormal;
  OUT.uv = vec2(inUv.x, 1.0 - inUv.y);

  return OUT;
}
#endif // _ENTRY_POINT_VS_Obj
#endif // IS_VERTEX_SHADER
#endif // DISPLAY_PASS

////////////////////////// PIXEL SHADERS //////////////////////////

#ifdef IS_PIXEL_SHADER

void PS_Background(VertexOutput IN) {
  vec3 dir = normalize(computeDir(IN.uv));
  vec4 color = vec4(sampleEnv(dir), 1.0);
  
  outColor = color;
  outDisplay = color;
}

void PS_Obj(VertexOutput IN) {
  // TODO - wrap this TAA part into a helper
  vec2 screenUv = 0.5 * IN.position.xy / IN.position.w + 0.5.xx;
  uvec2 seed = uvec2(screenUv * vec2(SCREEN_WIDTH, SCREEN_HEIGHT));
  seed *= uvec2(uniforms.frameCount, uniforms.frameCount + 1);

  float tsrSpeed = TSR_SPEED;
  vec2 prevScreenUv = IN.prevPosition.xy / IN.prevPosition.w * 0.5 + 0.5.xx;
  if (clamp(prevScreenUv, 0.0.xx, 1.0.xx) != prevScreenUv)
    tsrSpeed = 1.0;

  float dPrevRaw = texture(PrevDepthTexture, prevScreenUv).x;
  float dPrev = reconstructLinearDepth(dPrevRaw);
  float dPrev_expected = reconstructLinearDepth(IN.prevPosition.z / IN.prevPosition.w);

  // TODO smooth out the effect of depth-rejection on the TSR speed
  if (abs(dPrev_expected - dPrev) > REPROJ_TOLERANCE)
    tsrSpeed = 1.0;
  
  vec3 dir = normalize(computeDir(screenUv));
  mat3 tangentSpace = LocalToWorld(normalize(IN.normal));

  float bump = texture(HeadBumpTexture, IN.uv).x;
  vec2 bumpGrad = vec2(dFdx(bump), dFdy(bump)); 
  vec3 bumpNormal = vec3(BUMP_STRENGTH * bumpGrad, 1.0);
  vec3 normal = normalize(tangentSpace * bumpNormal);

  float spec = texture(HeadSpecTexture, IN.uv).x;
  float roughness = ROUGHNESS * (0.5 - spec);
  
  vec3 diffuse = texture(HeadLambertianTexture, IN.uv).rgb;

  vec3 Lo = 0.0.xxx;
  for (int sampleIdx = 0; sampleIdx < SAMPLE_COUNT; sampleIdx++) {
    float F0 = (IOR - 1.0) / (IOR + 1.0);
    F0 *= F0;
    vec3 F = vec3(0.0);
    vec3 H = normal;

    {
      vec3 reflDir;
      vec3 f;
      float pdf;
      {
        f = sampleMicrofacetBrdf(
          randVec2(seed), -dir, normal,
          diffuse, METALLIC, roughness, 
          reflDir, pdf);
        if (pdf < 0.1) {
          f = 0.0.xxx;
          pdf = 1.0;
        } else {
          H = (normalize(reflDir + -dir));
          float NdotH = abs(dot(normal, H));
          F = fresnelSchlick(NdotH, F0.xxx, roughness);
        }
      }

      vec3 throughput = f * max(dot(reflDir, -dir), 0.0) / pdf;
      if (ENABLE_REFL) 
        Lo += sampleEnv(reflDir) * throughput / SAMPLE_COUNT;
    }

    vec3 refrDir = refract(dir, H, 1.0/IOR);
    float refrDotH = dot(refrDir, H);
    if (refrDotH < 0.0) {
      if (ENABLE_SSS_EPI) {
        float cosRefrDirNormal = -dot(H, refrDir);
        float epidermisPathLength = EPI_DEPTH / cosRefrDirNormal;

        vec3 epiAbs = EPI_ABS_COLOR.rgb;
        vec3 sssThroughput = exp(-epiAbs * epidermisPathLength);

        vec3 HEMOGLOBIN_DIFFUSE = HEMOGLOBIN_COLOR.rgb * HEMOGLOBIN_SCALE;
        vec3 refrReflDir;
        {
          float pdf;
          vec3 refrReflDirLocal = sampleHemisphereCosine(seed, pdf);
          refrReflDir = normalize(LocalToWorld(H) * refrReflDirLocal);
          if (pdf > 0.01) {
            sssThroughput *= HEMOGLOBIN_DIFFUSE / PI * max(dot(refrDir, -refrReflDir), 0.0) / pdf;
          } else {
            sssThroughput = 0.0.xxx;
          }
        }

        float cosRefrReflDirNormal = abs(dot(H, refrReflDir));
        epidermisPathLength = EPI_DEPTH / cosRefrReflDirNormal;
        sssThroughput *= exp(-epiAbs * epidermisPathLength);

        Lo += max(1.0.xxx - F, 0.0.xxx) * sssThroughput * sampleEnv(refrReflDir) / SAMPLE_COUNT;
      } else if (ENABLE_SEE_THROUGH) {
        Lo += max(1.0.xxx - F, 0.0.xxx) * sampleEnv(refrDir) / SAMPLE_COUNT;
      }  
    }
  }

  vec4 color;
  if (RENDER_MODE == 0) {
    color = vec4(Lo, 1.0);
  } else if (RENDER_MODE == 1) {
    color = vec4(diffuse, 1.0);
  } else if (RENDER_MODE == 2) {
    color = vec4(0.5 * normal + 0.5.xxx, 1.0);
  } else if (RENDER_MODE == 3) {
    color = vec4(bump * bump.xxx, 1.0);//ec4(10.0 * bumpGrad, 0.0, 1.0);
  } else {
    color = vec4(roughness.xxx, 1.0);
  }
  
  vec3 prevColor = texture(PrevDisplayTexture, prevScreenUv).rgb;
  if (tsrSpeed != 1.0)
    color.rgb = mix(prevColor, vec3(color.rgb), tsrSpeed);
  outColor = vec4(color.rgb, 1.0);
  outDisplay = vec4(vec3(1.0) - exp(-color.rgb * 0.5), 1.0);
}
#endif // IS_PIXEL_SHADER

