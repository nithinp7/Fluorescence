#ifndef _DEFERRED_
#define _DEFERRED_

struct PackedGBuffer {
  vec4 gbuffer0;
  vec4 gbuffer1;
  vec4 gbuffer2;
};

// #define GBUF_USE_PACKED_NORMALS

PackedGBuffer packGBuffer(Material mat, vec3 normal) {
  float emissiveIntensity = length(mat.emissive);
  float emissivePower = emissiveIntensity / (1 + emissiveIntensity);

  PackedGBuffer p;
  p.gbuffer0 = vec4((emissiveIntensity > 0.0) ? mat.emissive / emissiveIntensity : mat.diffuse,1.0);
  p.gbuffer1 = vec4(0.5 * normal + 0.5.xxx, 1.0);
  p.gbuffer2 = vec4(mat.roughness, mat.metallic, emissivePower, 1.0); // todo should be non-linearly encoded...

#ifdef GBUF_USE_PACKED_NORMALS
  normal = mat3(camera.view) * normal;
  if (normal.z > 0.0)
    {
      p.gbuffer1 = vec4(0.0.xxx, 1.0);
      return p;
    }
  normal = normalize(normal);
  p.gbuffer1 = vec4(0.5 * normal.xy + 0.5.xx, 0.0, 1.0);
#endif // GBUF_USE_PACKED_NORMALS
  return p;
}

void unpackGBuffer(PackedGBuffer p, out Material mat, out vec3 normal) {
  float emissivePower = p.gbuffer2.z;
  float emissiveIntensity = -emissivePower / (emissivePower - 1.0);

  mat.diffuse = p.gbuffer0.rgb;
  mat.roughness = p.gbuffer2.r;
  mat.emissive = emissiveIntensity * mat.diffuse;
  mat.metallic = p.gbuffer2.y;
  mat.specular = 0.04.xxx;

  normal = normalize(p.gbuffer1.rgb * 2.0 - 1.0.xxx);
#ifdef GBUF_USE_PACKED_NORMALS
  normal.xy = 2.0 * p.gbuffer1.rg - 1.0.xx;
  normal.z = sqrt(max(1.0 - dot(normal.xy, normal.xy), 0.0));
  normal = mat3(camera.inverseView) * normal;
#endif
}

#endif // _DEFERRED_