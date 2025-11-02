
#extension GL_KHR_shader_subgroup_shuffle: enable
#extension GL_KHR_shader_subgroup_shuffle_relative: enable
#extension GL_KHR_shader_subgroup_arithmetic: enable
#extension GL_KHR_shader_subgroup_ballot: enable

#include <Misc/Sampling.glsl>

#include "World.glsl"

////////////////////////// COMPUTE SHADERS //////////////////////////

#ifdef IS_COMP_SHADER

void setDispatchSize(uint idx, uint count) {
  IndirectDispatch args;
  args.groupCountX = (count + 31) / 32;
  args.groupCountY = 1;
  args.groupCountZ = 1;
  dispatchArgs[idx] = args;
}

void CS_Init() {
  GlobalState state = initWorld();

  uint particleCount = MAX_PARTICLES;

  setDispatchSize(CS_ARGS_PARTICLES_UPDATE, state.particleCount);
  setDispatchSize(CS_ARGS_SHAPES_UPDATE, 32 * state.shapeCount);

  {
    IndirectArgs args;
    args.vertexCount = CIRCLE_VERTS;
    args.instanceCount = state.particleCount;
    args.firstVertex = 0;
    args.firstInstance = 0;
    drawArgs[0] = args;
  }
}

void CS_Update() {
  uint pidx = uint(gl_GlobalInvocationID.x);
  if (pidx >= MAX_PARTICLES)
    return;

  float DT = 0.033;
  uvec2 pseed = uvec2(pidx, pidx+1);
  
  vec2 pos = getPrevPos(pidx);

  vec2 disp = pos - getCurPos(pidx);
  float dist2 = dot(disp, disp);
  float MAX_DISP = 0.0225;
  if (dist2 > MAX_DISP * MAX_DISP)
    disp = disp / sqrt(dist2) * MAX_DISP;
  vec2 adt2 = vec2(0.0, 0.25) * DT * DT;
  vec2 vdt = disp * VEL_DAMPING + impulses[pidx] + adt2;
  pos += vdt;
  setCurPos(pidx, pos);
  impulses[pidx] = 0.0.xx;
}

void CS_ClearGrid() {
  uint flatIdx = uint(gl_GlobalInvocationID.x);
  if (flatIdx >= CELLS_COUNT)
    return;
  gridAllocs[flatIdx] = 0;
}

void CS_ReserveGrid() {
  uint pidx = uint(gl_GlobalInvocationID.x);
  if (pidx >= MAX_PARTICLES)
    return;

  uint cidx = gridToFlat(getGridCell(getCurPos(pidx)));
  // TODO encode quadrant here...
  uint alloc = atomicAdd(gridAllocs[cidx], 1);
  particleAllocs[pidx] = (cidx << 16) | alloc;
}

// single wave
void CS_AllocGrid() {
  uint tid = uint(gl_GlobalInvocationID.x);
  
  uint batches = (CELLS_COUNT + 31) / 32;
  uint allocOffs = 0;
  for (int i = 0; i < batches; i++) {
    uint cidx = tid + 32 * i;
    uint count = (cidx < CELLS_COUNT) ? gridAllocs[cidx] : 0;
    uint offs = allocOffs + subgroupExclusiveAdd(count);
    if (cidx < CELLS_COUNT)
      gridAllocs[cidx] = (offs << 16) | count;
    allocOffs = subgroupBroadcast(offs + count, 31);
  }
}

void CS_RegParticles() {
  uint pidx = uint(gl_GlobalInvocationID.x);
  if (pidx >= MAX_PARTICLES)
    return;
  uint alloc = particleAllocs[pidx];
  uint offs = (gridAllocs[alloc>>16]>>16) + (alloc&0xFFFF);
  // particles[pidx].alloc = offs;
  gridParticles[offs] = pidx;
}

ivec2 calcQuadrant(vec2 uv) {
  return 2 * ivec2(round(fract(uv * vec2(CELLS_X, CELLS_Y)))) - ivec2(1);
}

void processPair(inout vec2 a, vec2 b, bool order) {
  vec2 diff = a - b;
  float r2 = dot(diff, diff);
  if (r2 < 4.0 * PARTICLE_RADIUS * PARTICLE_RADIUS) {
    float r;
    if (r2 > 0.000001) {
      r = sqrt(r2);
    } else {
      r = 1.0;
      diff = (order ? 1.0 : -1.0) * vec2(0.5, 0.5);
    }
    a += 0.5 * COL_K * (2.0 * PARTICLE_RADIUS - r) * diff / r;
  }
}

void CS_ResolveCollisions(uint phase) {
  uint cidx = uint(gl_GlobalInvocationID.x);
  if (cidx >= CELLS_COUNT)
    return;
  
  uvec2 c = flatToGrid(cidx);
  // we are only allowed to mutate positions of particles in the quadrant
  // corresponding to the current phase
  // TODO: precompute quadrants, organize particles by quadrant to begin with
  // during registration...
  ivec2 q = 2 * ivec2(phase>>1,phase&1) - ivec2(1);
  AllocInfo alloc = getGridAlloc(cidx);
  for (uint i=0; i<alloc.count; i++) {
    uint p0idx = gridParticles[i+alloc.offs];
    vec2 p0 = getCurPos(p0idx);
    // filter out quadrant
    // TODO: pre-filter...
    ivec2 q0 = calcQuadrant(p0);
    if (q == q0) {
      // iterate all other particles in this bucket
      for (int j=0; j<alloc.count; j++) {
        if (i != j) {
          vec2 p1 = getCurPos(gridParticles[j+alloc.offs]);
          processPair(p0, p1, i < j); 
        }
      }
      // TODO
      // iterate neighbor buckets...
      for (int neighbor=1; neighbor<4; neighbor++) {
        ivec2 c1 = q * ivec2(neighbor>>1, neighbor&1) + ivec2(c);
        if (withinGrid(c1)) {
          AllocInfo allocOther = getGridAlloc(gridToFlat(uvec2(c1)));
          for (int j=0; j<allocOther.count; j++) {
            vec2 p1 = getCurPos(gridParticles[j+allocOther.offs]);
            processPair(p0, p1, i < j);
          }
        }
      }

      vec2 pt = clamp(p0, vec2(PARTICLE_RADIUS), vec2(1.0 - PARTICLE_RADIUS));
      p0 += (pt - p0) * COL_K;
      // p0 += (clamp(p0, vec2(PARTICLE_RADIUS), vec2(1.0 - PARTICLE_RADIUS)) - p0) * COL_K;
      setCurPos(p0idx, p0);      
    }
  }
}

void CS_ResolveCollisions0() { CS_ResolveCollisions(0); }
void CS_ResolveCollisions1() { CS_ResolveCollisions(1); }
void CS_ResolveCollisions2() { CS_ResolveCollisions(2); }
void CS_ResolveCollisions3() { CS_ResolveCollisions(3); }

void CS_SolveShapes() {
  uint sidx = uint(gl_WorkGroupID.x);
  if (sidx >= globalState[0].shapeCount)
    return;

  uint tid = gl_LocalInvocationID.x;
  
  // scalar
  Shape shape = shapes[sidx];
  uint offset = 0;
  vec2 lastPrevPos = 0.0.xx;
  for (uint pidx = tid + shape.particleStart; pidx < shape.particleEnd; pidx += 32) {
    vec2 pos = getCurPos(pidx);
    vec2 prevPos = subgroupShuffleUp(pos, 1);
    if (pidx == shape.particleStart) {
      // TODO
      prevPos = 0.0.xx;
    } else if (tid == 0) {
      prevPos = lastPrevPos;
    }

    vec2 disp = 0.0.xx;
    if (pidx != shape.particleStart) {
      vec2 diff = prevPos - pos;
      float spacing = SPACING * 0.025;
      float dist2 = dot(diff, diff);
      if (dist2 > 0.00001) {
        float dist = sqrt(dist2);
        disp = - FTL_K * (spacing - dist) * diff / dist;
      } else {
        disp = - FTL_K * spacing * vec2(1.0, 0.0);
      }
    }

    if (pidx > shape.particleStart) {
      impulses[pidx-1] += -disp * FTL_DAMPING;
    }  

    setCurPos(pidx, pos + disp);
    lastPrevPos = subgroupBroadcast(pos, 31);
  }
}
#endif // IS_COMP_SHADER

////////////////////////// VERTEX SHADERS //////////////////////////

#ifdef IS_VERTEX_SHADER
ScreenVertexOutput VS_Background() {
  ScreenVertexOutput OUT;
  OUT.uv = VS_FullScreen();
  return OUT;
}

ParticleVertexOutput VS_Particle() {
  vec2 ppos = getCurPos(gl_InstanceIndex);
  uint palloc = particleAllocs[gl_InstanceIndex];
  ParticleVertexOutput OUT;
  OUT.radius = ((gl_VertexIndex % 3) == 2) ? 0.0 : 1.0;
  OUT.uv = VS_Circle(gl_VertexIndex, ppos, PARTICLE_RADIUS, CIRCLE_VERTS);
  gl_Position = vec4(OUT.uv * 2.0 - 1.0, 0.0, 1.0);
  OUT.dbgColor = getGridColor(flatToGrid(palloc >> 16));
  return OUT;
}
#endif // IS_VERTEX_SHADER

////////////////////////// PIXEL SHADERS //////////////////////////

#ifdef IS_PIXEL_SHADER
void PS_Background(ScreenVertexOutput IN) {
  bool bVelMode = (uniforms.inputMask & INPUT_BIT_V) != 0;
  if ((uniforms.inputMask & INPUT_BIT_B) != 0) {
    outColor = getGridColor(getGridCell(IN.uv));
  } else {
    vec3 color = 0.0.xxx;
    ivec2 c0 = ivec2(IN.uv * vec2(CELLS_X, CELLS_Y) - 0.5.xx);
    for (int i  = 0; i < 4; i++) {
      ivec2 c = c0 + ivec2(i>>1,i&1);
      if (withinGrid(c)) {
        uint alloc = gridAllocs[gridToFlat(uvec2(c))];
        uint count = alloc & 0xFFFF;
        uint offs = alloc >> 16;
        for (int j = 0; j < count; j++) {
          uint pidx = gridParticles[offs+j];
          vec2 pos = getCurPos(pidx);
          float r = length(pos - IN.uv);
          vec3 c = getParticleColor(pidx).rgb;
          float h = PARTICLE_RADIUS;
          if (bVelMode) {
            float s = 10.;
            c = 2.0 * s * (pos - getPrevPos(pidx)).xyx + s.xxx;
            h = 2.0 * PARTICLE_RADIUS;
          }
          color += W(r, h) / 100000.0 * c;
        }
      }
    }
    color = 1.0 - exp(-color * EXPOSURE);
    outColor = vec4(color, 1.0);
  }
}

void PS_Particle(ParticleVertexOutput IN) {
  if ((uniforms.inputMask & INPUT_BIT_C) != 0) {
    outColor = IN.dbgColor;
  } else {
    float f = pow(1.0 - IN.radius, 2.0);
    outColor = vec4(f.xxx, 1.0);
  }
}
#endif // IS_PIXEL_SHADER

