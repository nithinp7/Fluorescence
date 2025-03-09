#include <PathTracing/BRDF.glsl>

#include <Misc/Sampling.glsl>
#include <Misc/ReconstructPosition.glsl>


vec3 sampleEnvMap(vec3 dir) {
  float yaw = mod(atan(dir.z, dir.x) + LIGHT_THETA, PI);
  float pitch = -atan(dir.y, length(dir.xz));
  vec2 uv = vec2(0.5 * yaw, pitch) / PI + 0.5;

  return textureLod(EnvironmentMap, uv, 0.0).rgb;
} 

vec3 computeDir(vec2 uv) {
	vec2 d = uv * 2.0 - 1.0;

	vec4 target = camera.inverseProjection * vec4(d, 1.0.xx);
	return (camera.inverseView * vec4(normalize(target.xyz), 0)).xyz;
}

vec3 sampleDiffusionProfile(float d) {
  vec3 c0 = vec3(RED_0, GREEN_0, BLUE_0);
  vec3 c1 = vec3(RED_1, GREEN_1, BLUE_1);

  vec3 t = d.xxx / c1;
  return c0 * exp(-0.5 * t * t);
}

vec3 computePrevDir(vec2 uv) {
	vec2 d = uv * 2.0 - 1.0;

	vec4 target = camera.inverseProjection * vec4(d, 1.0.xx);
	return (camera.prevInverseView * vec4(normalize(target.xyz), 0)).xyz;
}

vec3 sampleEnv(vec3 dir) {
  float cosphi = cos(LIGHT_PHI); float sinphi = sin(LIGHT_PHI);
  float costheta = cos(LIGHT_THETA); float sintheta = sin(LIGHT_THETA);
  vec3 L = normalize(vec3(costheta * cosphi, sinphi, sintheta * cosphi));

  float dirLen2 = dot(dir, dir);
  if (dirLen2 < 0.05)
    return 0.0.xxx;
    
  float c = 5.0;
  vec3 n = 0.5 * normalize(dir) + 0.5.xxx;
  if (BACKGROUND == 0) {
    float x = dot(dir, L);
    if (x < LIGHT_COVERAGE)
      x = 0.0;
    x *= LIGHT_STRENGTH;
    // x = pow(2.0 * LIGHT_STRENGTH * x, 8.0);
    // x = LIGHT_STRENGTH * pow(x, LIGHT_STRENGTH * 10.0) + 0.01;
    return x.xxx;
  } else if (BACKGROUND == 1) {
    float x = 0.5 + 0.5 * dot(dir,L);
    return LIGHT_STRENGTH * x * round(fract(LocalToWorld(L) * n * c + 0.1 * uniforms.time));
  } else if (BACKGROUND == 2) {
    return round(n);
  } else if (BACKGROUND == 3) {
    float f = n.x + n.y + n.z;
    return max(round(fract(f * c)), 0.2).xxx;
  } else if (BACKGROUND == 4) {
    float x = 0.5 + 0.5 * dot(dir,L);
    return LIGHT_STRENGTH * x * round(n * c) / c;
  } else {
    return sampleEnvMap(dir);
  }
}

struct SkinMaterial {
  vec3 diffuse;
  float bump;
};

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
  
  c = vec4(texelFetch(IrradianceTexture, pixelId, 0).rgb, 1.0);
  if ((uniforms.inputMask & INPUT_BIT_SPACE) != 0)
    c = vec4(0.0.xxx, 1.0);
  imageStore(PrevIrradianceImage, pixelId, c);

  float d = texelFetch(DepthTexture, pixelId, 0).r;
  if ((uniforms.inputMask & INPUT_BIT_SPACE) != 0)
    d = 0.0;
  imageStore(PrevDepthImage, pixelId, d.xxxx);
}
#endif // IS_COMP_SHADER

////////////////////////// VERTEX SHADERS //////////////////////////

#ifdef IS_VERTEX_SHADER

#ifdef LIGHTING_PASS
#ifdef _ENTRY_POINT_VS_SkinIrr
// TODO automate...
layout(location = 0) in vec3 inPosition;
layout(location = 1) in vec3 inNormal;
layout(location = 2) in vec2 inUv;

VertexOutput VS_SkinIrr() {
  VertexOutput OUT;

  vec4 worldPos = vec4(inPosition, 1.0);
  vec4 projPos = camera.projection * camera.view * worldPos;
  gl_Position = projPos;
  OUT.worldPosition = worldPos;
  OUT.position = projPos;
  OUT.prevPosition = camera.projection * camera.prevView * vec4(inPosition, 1.0);
  OUT.normal = inNormal;
  OUT.uv = vec2(inUv.x, 1.0 - inUv.y);

  return OUT;
}
#endif // _ENTRY_POINT_VS_Skin
#endif // LIGHTING_PASS

#ifdef DISPLAY_PASS

#ifdef _ENTRY_POINT_VS_SkinResolve

VertexOutput VS_SkinResolve() {
  VertexOutput OUT;

  OUT.uv = VS_FullScreen();
  gl_Position = vec4(OUT.uv * 2.0 - 1.0, 0.0, 1.0);

  return OUT;
}
#endif // _ENTRY_POINT_VS_SkinResolve
#endif // DISPLAY_PASS

#endif // IS_VERTEX_SHADER

////////////////////////// PIXEL SHADERS //////////////////////////

#ifdef IS_PIXEL_SHADER

float sampleDepth(vec2 uv) {
  uv = clamp(uv, 0.0.xx, 1.0.xx);
  float draw = texture(PrevDepthTexture, uv).x;
  return reconstructLinearDepth(draw);
}

#ifdef LIGHTING_PASS
float computeScreenSpaceShadows(vec3 worldPos, vec3 L, vec2 startUv) {
  // float SHADOW_STEP_SIZE = min(1.0/SCREEN_WIDTH, 1.0/SCREEN_HEIGHT);
  uint stepCount = SHADOW_STEPS;

  vec4 cstart = camera.view * vec4(worldPos, 1.0);
  vec4 pstart = camera.projection * cstart;
  float invW0 = 1.0 / pstart.w;
  pstart *= invW0;
  vec4 cend = camera.view * vec4(L, 0.0);
  vec4 pend = camera.projection * cend;
  float invW1 = 1.0 / pend.w;
  pend *= invW1;

  float t = 0.0;
  float dt = SHADOW_DT;//SHADOW_STEP_SIZE;
  float startD = reconstructLinearDepth(texture(PrevDepthTexture, 0.5 * pstart.xy + 0.5.xx).r);
  float curD = startD;
  
  outDebug = vec4(startD.xxx, 1.0);
  for (int iter = 0; iter < stepCount; iter++) {
    t += dt;
    vec3 curPos = worldPos + L * t;
    vec4 pt = camera.projection * camera.view * vec4(curPos, 1.0);
    // float invWt = mix(invW0, invW1, t);
    // vec4 pt = mix(pstart, pend, t) / invWt;
    if (t >= 1.0) {
      return 1.0;
    }
    
    vec2 curUv = pt.xy/pt.w * 0.5 + 0.5.xx;

    if (clamp(curUv, 0.0, 1.0) != curUv) {
      return 1.0;
    }

    float dRaw = texture(PrevDepthTexture, curUv).x;
    if (dRaw >= 0.999) {
      return 1.0;
    }
    
    float d = reconstructLinearDepth(dRaw);

    if (length(reconstructPosition(curUv, dRaw, camera.inverseProjection, camera.inverseView) - curPos) < SHADOW_THRESHOLD) {
      return 0.0;
    }

    outDebug = vec4(dRaw.xxx, 1.0);
    curD = dRaw;
  }

  return 1.0; // unshadowed
}

void PS_SkinIrr(VertexOutput IN) {
  outDebug = vec4(0.0.xxx, 1.0);
  // TODO - wrap this TAA part into a helper
  vec2 screenUv = 0.5 * IN.position.xy / IN.position.w + 0.5.xx;
  vec3 dir = normalize(computeDir(screenUv));
  uvec2 seed = uvec2(screenUv * vec2(SCREEN_WIDTH, SCREEN_HEIGHT));
  seed *= uvec2(uniforms.frameCount, uniforms.frameCount + 1);
  // seed *= uvec2(10023, 10024);

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
  
  mat3 tangentSpace = LocalToWorld(normalize(IN.normal));

  float bump = texture(HeadBumpTexture, IN.uv).x;
  vec2 bumpGrad = vec2(dFdx(bump), dFdy(bump)); 
  vec3 bumpNormal = vec3(BUMP_STRENGTH * bumpGrad, 1.0);
  vec3 normal = normalize(tangentSpace * bumpNormal);

  float NdotV = dot(dir, normal);

  float spec = 0.5 * texture(HeadSpecTexture, IN.uv).x;
  float roughness = clamp(ROUGHNESS - spec, 0.1, 1.0);
  
  vec3 diffuse = texture(HeadLambertianTexture, IN.uv).rgb;

  const float PDF_CUTOFF = 0.001;

  vec3 Lo = 0.0.xxx;
  if (NdotV < 0.0) 
  {
    for (int sampleIdx = 0; sampleIdx < SAMPLE_COUNT; sampleIdx++) {
      float F0 = 1.0;//(IOR - 1.0) / (IOR + 1.0);
      F0 *= F0;
      vec3 F = vec3(0.0);
      vec3 H = normal;

      {
        vec3 reflDir;
        vec3 f;
        float pdf;
        {
          for (int i = 0; i < 5; i++) {
            f = sampleMicrofacetBrdf(
              randVec2(seed), -dir, normal,
              diffuse, METALLIC, roughness, 
              reflDir, pdf);
            if (pdf >= PDF_CUTOFF)
              break;
          }
          if (pdf < PDF_CUTOFF) {
            f = 0.0.xxx;
            pdf = 1.0;
            tsrSpeed = 0.0;
          } else  
          {
            H = (normalize(reflDir + -dir));
            float NdotH = abs(dot(normal, H));
            F = fresnelSchlick(NdotH, F0.xxx, roughness);
          }
        }

        float NdotL = dot(reflDir, normal);
        if (NdotL > 0.0) {
          vec3 throughput = f * NdotL / pdf;
          float v = 1.0;
          if (ENABLE_SHADOWS)
            v = computeScreenSpaceShadows(IN.worldPosition.xyz/IN.worldPosition.w - dir * SHADOW_BIAS, reflDir, screenUv);
          Lo += v * F * sampleEnv(reflDir) * throughput / SAMPLE_COUNT;
        }
      }
    }
  }
  
  vec3 prevLo = texture(PrevIrradianceTexture, prevScreenUv).rgb;
  Lo = mix(prevLo, Lo, TSR_SPEED);
  
  outDebug = 1.0.xxxx;
  outIrradiance = vec4(Lo, 1.0);
}
#endif // LIGHTING_PASS

#ifdef DISPLAY_PASS

void PS_SkinResolve(VertexOutput IN) {
  float diffusionProfileWindow = 0.2;

  if (SHOW_PROFILE && IN.uv.x < diffusionProfileWindow && IN.uv.y < diffusionProfileWindow) {
    vec2 uv = IN.uv / diffusionProfileWindow;
    vec3 profile = sampleDiffusionProfile(length(uv - 0.5.xx));
    outColor = vec4(profile, 1.0);
    outDisplay = vec4(profile, 1.0);
    return;
  }

  vec4 irradiance = texture(IrradianceTexture, IN.uv);
  vec2 depth = texture(DepthTexture, IN.uv).ra;
  if (irradiance.a < 1.0) {
    vec3 dir = normalize(computeDir(IN.uv));
    vec4 color = vec4(sampleEnv(dir), 1.0);
    outColor = color;
    outDisplay = color;
    return;
  }

  uvec2 seed = uvec2(IN.uv * vec2(SCREEN_WIDTH, SCREEN_HEIGHT));
  seed *= uvec2(uniforms.frameCount, uniforms.frameCount + 1);
  
  if (ENABLE_SSS_EPI) {
    vec2 xi = randVec2(seed);
    // vec3 profile = texture(DiffusionProfileTexture, xi).rgb;
    vec3 profile = sampleDiffusionProfile(length(xi - 0.5.xx));
    vec2 neighborUv = IN.uv + SSS_RADIUS * (2.0 * xi - 1.0.xx);
    vec4 neighborIrradiance = texture(IrradianceTexture, neighborUv);
    if (neighborIrradiance.a == 1.0) {
      irradiance.rgb += profile * neighborIrradiance.rgb;
    }
  }
  
  outDisplay = irradiance;
  outColor = irradiance;

  if ((uniforms.inputMask & INPUT_BIT_L) != 0) {
    outDisplay = fract(texture(DebugTexture, IN.uv) * 10.0);
  }
  if ((uniforms.inputMask & INPUT_BIT_O) != 0) {
    outDisplay = vec4((texture(DepthTexture, IN.uv).rrr * 10.0), 1.0);
  }
}
#endif // DISPLAY_PASS

#endif // IS_PIXEL_SHADER

