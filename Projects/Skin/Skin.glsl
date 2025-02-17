#include <PathTracing/BRDF.glsl>

#include <Misc/Sampling.glsl>

vec3 computeDir(vec2 uv) {
	vec2 d = uv * 2.0 - 1.0;

	vec4 target = camera.inverseProjection * vec4(d, 1.0.xx);
	return (camera.inverseView * vec4(normalize(target.xyz), 0)).xyz;
}

vec3 sampleEnv(vec3 dir) {
  float c = 5.0;
  vec3 n = 0.5 * normalize(dir) + 0.5.xxx;
  if (BACKGROUND == 0) {
    float cosphi = cos(LIGHT_PHI); float sinphi = sin(LIGHT_PHI);
    float costheta = cos(LIGHT_THETA); float sintheta = sin(LIGHT_THETA);
    float x = 0.5 + 0.5 * dot(dir, normalize(vec3(costheta * cosphi, sinphi, sintheta * cosphi)));
    x = LIGHT_STRENGTH * pow(x, LIGHT_STRENGTH * 10.0) + 0.01;
    return x.xxx;
  } else if (BACKGROUND == 1) {
    return round(fract(n * c));
  } else if (BACKGROUND == 2) {
    return round(n);
  } else if (BACKGROUND == 3) {
    float f = n.x + n.y + n.z;
    return max(round(fract(f * c)), 0.2).xxx;
  } else {
    float cosphi = cos(LIGHT_PHI); float sinphi = sin(LIGHT_PHI);
    float costheta = cos(LIGHT_THETA); float sintheta = sin(LIGHT_THETA);
    float x = 0.5 + 0.5 * dot(dir, normalize(vec3(costheta * cosphi, sinphi, sintheta * cosphi)));
    x = pow(x, LIGHT_STRENGTH) + 0.01;
    return LIGHT_STRENGTH * x * round(n * c) / c;
  }
}

////////////////////////// COMPUTE SHADERS //////////////////////////

#ifdef IS_COMP_SHADER
#endif // IS_COMP_SHADER

////////////////////////// VERTEX SHADERS //////////////////////////

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
  OUT.position = projPos.xyw;
  OUT.normal = inNormal;
  OUT.uv = vec2(inUv.x, 1.0 - inUv.y);

  return OUT;
}
#endif // _ENTRY_POINT_VS_Obj
#endif // IS_VERTEX_SHADER

////////////////////////// PIXEL SHADERS //////////////////////////

#ifdef IS_PIXEL_SHADER

// TODO 
layout(location = 0) out vec4 outColor;

void PS_Background(VertexOutput IN) {
  vec3 dir = computeDir(IN.uv);
  outColor = vec4(sampleEnv(dir), 1.0);
}

void PS_Obj(VertexOutput IN) {
  vec3 dir = normalize(computeDir(IN.uv));
  mat3 tangentSpace = LocalToWorld(IN.normal);

  float bump = texture(HeadBumpTexture, IN.uv).x;
  vec2 bumpGrad = vec2(dFdx(bump), dFdy(bump)); 
  vec3 bumpNormal = vec3(BUMP_STRENGTH * bumpGrad, 1.0);
  vec3 normal = normalize(tangentSpace * bumpNormal);

  vec3 diffuse = texture(HeadLambertianTexture, IN.uv).rgb;

  uvec2 seed = uvec2((0.5 * IN.position.xy / IN.position.z + 0.5.xx) * vec2(SCREEN_WIDTH, SCREEN_HEIGHT));
  seed *= uvec2(uniforms.frameCount, uniforms.frameCount + 1);

  vec3 Lo = 0.0.xxx;
  for (int sampleIdx = 0; sampleIdx < SAMPLE_COUNT; sampleIdx++) {
    float W = 0.0;
    if (ENABLE_SSS)
      W += 1.0;
    if (ENABLE_REFL)
      W += 1.0;

    if (ENABLE_SSS && (!ENABLE_REFL || (rng(seed) < 0.5))) {
      vec3 refrDir = refract(dir, normal, 1.0/IOR_EPI);

      float cosRefrDirNormal = -dot(normal, refrDir);
      float epidermisPathLength = EPI_DEPTH / cosRefrDirNormal;

      vec3 epiAbs = vec3(EPI_ABS_RED, EPI_ABS_GREEN, EPI_ABS_BLUE);
      vec3 sssThroughput = exp(-epiAbs * epidermisPathLength);

      vec3 HEMOGLOBIN_DIFFUSE = vec3(0.8, 0.3, 0.4) * HEMOGLOBIN_SCALE;
      vec3 refrReflDir;
      if (BRDF_MODE == 0) {
        float pdf;
        vec3 refrReflDirLocal = sampleHemisphereCosine(seed, pdf);
        refrReflDir = LocalToWorld(normal) * refrReflDirLocal;
        sssThroughput *= HEMOGLOBIN_DIFFUSE /* refrReflDirLocal.z / refrReflDirLocal.z */;
        // the pdf cancels out with part of the brdf, in the lambertian brdf
      } else {
        float pdfRefrRefl;
        vec3 fRefrRefl = sampleMicrofacetBrdf(
          randVec2(seed), -refrDir, normal,
          HEMOGLOBIN_DIFFUSE, METALLIC, ROUGHNESS, 
          refrReflDir, pdfRefrRefl);
        sssThroughput *= fRefrRefl / pdfRefrRefl;
      }

      float cosRefrReflDirNormal = dot(normal, refrReflDir);
      epidermisPathLength = EPI_DEPTH / cosRefrReflDirNormal;
      sssThroughput *= exp(-epiAbs * epidermisPathLength);

      Lo += W * sssThroughput * sampleEnv(refrReflDir) / SAMPLE_COUNT;
    } else {
      vec3 reflDir;
      vec3 f;
      float pdf;
      if (BRDF_MODE == 0) {
        vec3 reflDirLocal = sampleHemisphereCosine(seed, pdf);
        reflDir = LocalToWorld(normal) * reflDirLocal;
        f = diffuse * reflDirLocal.z;
        pdf = reflDirLocal.z;
      } else {
        f = sampleMicrofacetBrdf(
          randVec2(seed), -dir, normal,
          diffuse, METALLIC, ROUGHNESS, 
          reflDir, pdf);
      }

      vec3 throughput = f / pdf;
      Lo += W * sampleEnv(reflDir) * throughput / SAMPLE_COUNT;
    }
  }

  if (RENDER_MODE == 0) {
    outColor = vec4(Lo, 1.0);
  } else if (RENDER_MODE == 1) {
    outColor = vec4(diffuse, 1.0);
  } else if (RENDER_MODE == 2) {
    outColor = vec4(0.5 * normal + 0.5.xxx, 1.0);
  } else {
    outColor = vec4(bump.xxx, 1.0);
  }

}
#endif // IS_PIXEL_SHADER

