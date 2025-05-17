
#include <PathTracing/BRDF.glsl>

#include <Misc/Constants.glsl>
#include <Misc/Sampling.glsl>

#include <FlrLib/Scene/Intersection.glsl>
#include <FlrLib/Scene/Scene.glsl>

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

vec4 samplePath(inout uvec2 seed, Ray ray) {
  vec4 color = vec4(0.0.xxx, 1.0);

  vec3 throughput = 1.0.xxx;
  for (int bounce = 0; bounce < BOUNCES; bounce++) {
    HitResult hit;
    bool bResult = traceScene(ray, hit);

    if (!bResult) {
      color.rgb = throughput * sampleEnv(ray.d);
      break;
    }

    Material mat = materialBuffer[hit.matID];

    if (length(mat.emissive) > 0.0)
    {
      color.rgb += throughput * mat.emissive;
      break;
    }

    vec3 reflDir;
    float pdf;
    vec3 f = sampleMicrofacetBrdf(
      randVec2(seed), -ray.d, hit.n,
      mat.diffuse, mat.metallic, mat.roughness, 
      reflDir, pdf);
    
    throughput *= f * mat.diffuse / pdf;

    const float BOUNCE_BIAS = 0.001;
    ray.d = normalize(reflDir);
    ray.o = hit.p + BOUNCE_BIAS * ray.d;
  }

  return color;
}

////////////////////////// COMPUTE SHADERS //////////////////////////

#ifdef IS_COMP_SHADER
void CS_Tick() {
  if (globalStateBuffer[0].triCount == 0 || (uniforms.inputMask & INPUT_BIT_R) != 0)
    initScene_CornellBox();
  
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
  uvec2 pixelCoord = uvec2(gl_GlobalInvocationID.xy);
  if (pixelCoord.x >= SCREEN_WIDTH || pixelCoord.y >= SCREEN_HEIGHT) {
    return;
  }

  vec4 prevColor = imageLoad(accumulationBuffer, ivec2(pixelCoord));

  uvec2 seed = pixelCoord * uvec2(uniforms.frameCount, uniforms.frameCount + 1);
  
  vec2 uv = vec2(pixelCoord) / vec2(SCREEN_WIDTH, SCREEN_HEIGHT);
  
  Ray ray;
  ray.o = camera.inverseView[3].xyz;
  ray.d = normalize(computeDir(uv));


  vec4 color = 0.0.xxxx;
  if (RENDER_MODE == 0) {
    color = samplePath(seed, ray);
  } else {
    HitResult hit;
    if (traceScene(ray, hit)) {
      Material mat = materialBuffer[hit.matID];
      if (RENDER_MODE == 1) {
        color = vec4(mat.diffuse, 1.0);
      } else {
        color = vec4(0.5 * hit.n + 0.5.xxx, 1.0);
      }
    }
    else {
      color = vec4(sampleEnv(ray.d), 1.0);
    }
  }

  color.rgb = mix(prevColor.rgb, color.rgb, 1.0 / globalStateBuffer[0].accumulationFrames);
  imageStore(accumulationBuffer, ivec2(pixelCoord), color);
}
#endif // IS_COMP_SHADER

////////////////////////// VERTEX SHADERS //////////////////////////

#ifdef IS_VERTEX_SHADER
VertexOutput VS_Render() {
  VertexOutput OUT;
  OUT.screenUV = VS_FullScreen();
  gl_Position = vec4(OUT.screenUV * 2.0 - 1.0, 0.0, 1.0);
  return OUT;
}
#endif // IS_VERTEX_SHADER

////////////////////////// PIXEL SHADERS //////////////////////////

#ifdef IS_PIXEL_SHADER
void PS_Render(VertexOutput IN) {
  outColor = texture(accumulationTexture, IN.screenUV);
  // outColor.rgb = vec3(1.0) - exp(-outColor.rgb * 0.8);
}
#endif // IS_PIXEL_SHADER

