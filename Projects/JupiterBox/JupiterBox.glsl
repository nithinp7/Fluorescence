
#include <Misc/Constants.glsl>
#include <Misc/Sampling.glsl>

#include <FlrLib/Scene/Intersection.glsl>
#include <FlrLib/Scene/Scene.glsl>
#include <FlrLib/PBR/BRDF.glsl>


vec2 dirToPolar(vec3 dir) {
    float yaw = atan(dir.z, dir.x) - PI;
    float pitch = -atan(dir.y, length(dir.xz));
    return vec2(0.5 * yaw, pitch) / PI + 0.5;
}


vec2 applyTurbulence(vec2 pos) {
  float freq = TURB_FREQ;
  float amp = TURB_AMP;
  float speed = TURB_SPEED;

  float cosTheta = cos(TURB_ROT);
  float sinTheta = sin(TURB_ROT);
  mat2 drot = mat2(cosTheta, -sinTheta, sinTheta, cosTheta);
  mat2 rot = drot;

  for (int i = 0; i < 10; i++) {
    float phase = freq * (pos * rot).y + speed * uniforms.time + i;
    pos += amp * rot[0] * sin(phase) / freq;

    rot *= drot;
    freq *= TURB_EXP;
  }
  return pos;
}

vec3 sampleField(vec2 pos) {
  vec2 ar = vec2(1.0, float(SCREEN_HEIGHT)/float(SCREEN_WIDTH));
  vec3 col = 0.0.xxx;
  vec2 diff = fract(pos * 10.0) - 0.5.xx;
  if (diff.x < 0.0) {
    col += COLOR0.rgb * COLOR0_INT * exp(COLOR0_FALLOFF * diff.x);
  }
  if (diff.y < 0.0) {
    col += COLOR1.rgb * COLOR1_INT * exp(COLOR1_FALLOFF * diff.y);
  }
  if (diff.x > 0.4) {
    col += COLOR2.rgb * COLOR2_INT * exp(-COLOR2_FALLOFF * diff.x);
  }
  return col;
  // return (min(pos.x, pos.y) < 0.01) ? vec3(1.0, 0.0, 0.0) : 0.0.xxx;
}

bool trace(Ray ray, out HitResult hit, out Material mat) {
  if (traceScene(ray, hit)) {
    mat = materialBuffer[hit.matID];
    if (hit.matID == 7) {
      mat.diffuse = vec3(1.0, 0.0, 0.0);
      // incredibly hacky
      vec3 sphereCenter = vec3(0.45, 0.2 + 0.25, 0.15) * 15.0;
      vec3 dir = normalize(hit.p - sphereCenter);
      vec2 pos = dirToPolar(dir);
      float rm_0 = RM_0;//0.5 + RM_0 * (0.5 + 0.5 * sin(uniforms.time * 1.3 + 23.0) + pow(0.025 + 0.05 * sin(uniforms.time * 23.0 + 0.3), 2.0));
      vec3 col = 0.0.xxx;
      float throughput = 1.0;
      float z = 1.0;

      if (APPLY_TURBULENCE) {
        for (int i = 0; i < 10; i++) {
          vec3 c = sampleField(pos);
          col += throughput * c * float(i) / 20.0;
          vec2 dx = (1.9 * rm_0 - i/5.0 * RM_1) * (applyTurbulence(pos) - pos);
          vec3 dir = vec3(dx, z);
          dir = refract(dir, vec3(0.0, 0.0, -1.0), ETA);
          float dist = length(dir);
          throughput *= exp(-0.001 * COLOR3_FALLOFF * dist);
          // dir /= dist;
          z = dir.z;
          pos += dir.xy;
        }
      }
      mat.emissive = 10.0 * col;// sampleField(pos);
      // mat.diffuse = sampleField(pos);
    }
    return true;
  }

  return false;
}

vec4 sampleAccumulationTexture(vec2 uv, uint phase) {
  if (phase == 0) {
    return texture(accumulationTexture, uv);
  } else {
    return texture(accumulationTexture2, uv);
  }
}

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
  Material specMat;
  if (trace(specRay, specHit, specMat)) {
    return f * specMat.emissive;
  } else {
    return 0.0.xxx;//sampleEnv(specRay.d) * abs(dot(surfaceHit.n, specRay.d));
  }
}

vec4 samplePath(inout uvec2 seed, Ray ray) {
  vec4 color = vec4(0.0.xxx, 1.0);

  vec3 throughput = 1.0.xxx;
  for (int bounce = 0; bounce < BOUNCES; bounce++) {
    HitResult hit;
    Material mat;
    bool bResult = trace(ray, hit, mat);

    if (!bResult) {
      color.rgb = throughput * sampleEnv(ray.d);
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

void CS_PathTrace() {
  uvec2 pixelCoord = uvec2(gl_GlobalInvocationID.xy);
  if (pixelCoord.x >= SCREEN_WIDTH || pixelCoord.y >= SCREEN_HEIGHT) {
    return;
  }

  uvec2 seed = pixelCoord * uvec2(uniforms.frameCount, uniforms.frameCount + 1);
  
  vec2 uv = (vec2(pixelCoord)+0.5.xx) / vec2(SCREEN_WIDTH, SCREEN_HEIGHT);

  vec4 prevColor = sampleAccumulationTexture(uv, (uniforms.frameCount & 1)^1);
  /*if (bool(uniforms.frameCount & 1)) {
    prevColor = sampleAccumulationTexture(uv, 0);// imageLoad(accumulationBuffer, ivec2(pixelCoord));
  } else {
    prevColor = sampleAccumulationTexture(uv, 1);//imageLoad(accumulationBuffer2, ivec2(pixelCoord));
  }*/

  Ray ray;
  ray.o = camera.inverseView[3].xyz;
  ray.d = normalize(computeDir(uv));

  if (JITTER) {
    vec3 c = ray.o + DOF_DIST * ray.d;
    ray.o += DOF_RAD * (randVec3(seed) - 0.5.xxx) * 0.01;
    ray.d = normalize(c - ray.o);
  }

  vec4 color = 0.0.xxxx;
  if (RENDER_MODE == 0) {
    color = samplePath(seed, ray);
  } else {
    HitResult hit;
    Material mat;
    if (trace(ray, hit, mat)) {
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
  
  if (bool(uniforms.frameCount & 1)) {
    imageStore(accumulationBuffer2, ivec2(pixelCoord), color);
  } else {
    imageStore(accumulationBuffer, ivec2(pixelCoord), color);
  }
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
  outColor = sampleAccumulationTexture(IN.screenUV, uniforms.frameCount & 1);
  outColor.rgb = vec3(1.0) - exp(-outColor.rgb * EXPOSURE);
}
#endif // IS_PIXEL_SHADER

