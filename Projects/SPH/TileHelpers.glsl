#define TILE_WIDTH (1.0 / TILE_COUNT_X)
#define TILE_HEIGHT (1.0 / TILE_COUNT_Y)

int getTileIdxFromCoord(ivec2 coord) {
  coord.x = clamp(coord.x, 0, TILE_COUNT_X - 1);
  coord.y = clamp(coord.y, 0, TILE_COUNT_Y - 1);
  return coord.y * TILE_COUNT_X + coord.x;
}

int getTileIdxFromUv(vec2 uv) {
  ivec2 coord = ivec2(uv * vec2(TILE_COUNT_X, TILE_COUNT_Y));
  return getTileIdxFromCoord(coord);
}

void getTile(uint tileIdx, out uint offset, out uint count) {
  tileIdx += globalStateBuffer[0].bPhase * TILE_COUNT;
  uint tile = tilesBuffer[tileIdx].offset24count8;
  offset = tile >> 8;
  count = tile & 0xFF;
}

// TODO: archive this bump-compressed reduced tile idx idea, there are some issues
/*
vec2 unpackPrevParticlePos(uint particleIdx) {
  TileDict tileDict = subgroupBroadcast(tileDictionaryBuffer[particleIdx / 32], 0);
  uint bTileBumped = (tileDict.tileBumpMask >> gl_SubgroupInvocationID) & 1;
  uint redTileIdx = tileDict.startReducedTileIdx + subgroupInclusiveAdd(bTileBumped);
  uint tileIdx = reducedTilesBuffer[redTileIdx].u;
  
  uint phaseParticleOffs = (1 - uint(globalStateBuffer[0].bPhase)) * PARTICLE_COUNT;
  particleIdx += phaseOffs;
  
  uint packed = packedPositions[particleIdx / 2];
  packed = (packed >> ((particleIdx & 1) << 4)) & 0xFFFF;
  uvec2 qpos = uvec2(packed >> 8, packed & 0xFF);
  return (tileCoordf + qpos / 256.0) / vec2(TILE_COUNT_X, TILE_COUNT_Y);
}*/

void packDensityPressure(uint particleIdx, float density, float pressure) {
  packedDensityPressure[particleIdx].u = packHalf2x16(vec2(density, pressure));
}

void unpackDensityPressure(uint particleIdx, out float density, out float pressure) {
  vec2 unpacked = unpackHalf2x16(packedDensityPressure[particleIdx].u);
  density = unpacked.x;
  pressure = unpacked.y;
}

vec2 unpackPos(uint particleIdx) {
  particleIdx += globalStateBuffer[0].bPhase * PARTICLE_COUNT;
  uint tileIdx = (particleAddresses[particleIdx].u >> 8) % TILE_COUNT;
  vec2 tileCoordf = vec2(tileIdx % TILE_COUNT_X, tileIdx / TILE_COUNT_X);

  uint packed = packedPositions[particleIdx / 2].u;
  packed = (packed >> ((particleIdx & 1) << 4)) & 0xFFFF;
  uvec2 qpos = uvec2(packed >> 8, packed & 0xFF);

  return (tileCoordf + qpos / 256.0) / vec2(TILE_COUNT_X, TILE_COUNT_Y);
}

void packVelocity(uint particleIdx, vec2 vel) {
  particleIdx += globalStateBuffer[0].bPhase * PARTICLE_COUNT;
  packedVelocities[particleIdx].u = packHalf2x16(vel);
}

vec2 unpackVelocity(uint particleIdx) {
  particleIdx += globalStateBuffer[0].bPhase * PARTICLE_COUNT;
  return unpackHalf2x16(packedVelocities[particleIdx].u);
}

vec2 unpackPrevPos(uint particleIdx) {
  particleIdx += (globalStateBuffer[0].bPhase ^ 1) * PARTICLE_COUNT;
  uint tileIdx = (particleAddresses[particleIdx].u >> 8) % TILE_COUNT;
  vec2 tileCoordf = vec2(tileIdx % TILE_COUNT_X, tileIdx / TILE_COUNT_X);

  uint packed = packedPositions[particleIdx / 2].u;
  packed = (packed >> ((particleIdx & 1) << 4)) & 0xFFFF;
  uvec2 qpos = uvec2(packed >> 8, packed & 0xFF);
  return (tileCoordf + qpos / 256.0) / vec2(TILE_COUNT_X, TILE_COUNT_Y);
}

vec2 unpackPrevVelocity(uint particleIdx) {
  particleIdx += (globalStateBuffer[0].bPhase ^ 1) * PARTICLE_COUNT;
  return unpackHalf2x16(packedVelocities[particleIdx].u);
}

// in: globalStateBuffer
// out: tilesBuffer
void clearTile(uint tileIdx) {
  tileIdx += globalStateBuffer[0].bPhase * TILE_COUNT;
  
  Tile tile;
  tile.offset24count8 = 0;
  
  tilesBuffer[tileIdx] = tile;
}

// in: tilesBuffer
// out: tilesBuffer, reducedTilesBuffer, globalStateBuffer
void reserveTileEntry(vec2 pos) {
  uint bPhase = globalStateBuffer[0].bPhase;

  vec2 tileCoordf = pos * vec2(TILE_COUNT_X, TILE_COUNT_Y);
  ivec2 tileCoord = ivec2(tileCoordf);
  tileCoord.x = clamp(tileCoord.x, 0, TILE_COUNT_X - 1);
  tileCoord.y = clamp(tileCoord.y, 0, TILE_COUNT_Y - 1);
  uint tileIdx = tileCoord.y * TILE_COUNT_X + tileCoord.x + bPhase * TILE_COUNT;

  uint prev = atomicAdd(tilesBuffer[tileIdx].offset24count8, 1);
  if (prev == 0) { 
    // if this is the first entry in the tile, need to set up a reduced
    // tile idx
    uint reducedIdx = atomicAdd(globalStateBuffer[0].activeTileCount, 1);
    reducedTilesBuffer[reducedIdx].u = tileIdx;
  }
}

// in: globalStateBuffer, tilesBuffer, reducedTilesBuffer
// out: globalStateBuffer, tilesBuffer
void allocateTile(uint redTileIdx) {
  if (redTileIdx >= globalStateBuffer[0].activeTileCount)
    return;

  uint tileIdx = reducedTilesBuffer[redTileIdx].u;

  Tile tile = tilesBuffer[tileIdx];
  uint count = tile.offset24count8 & 0xFF;
  uint offset = atomicAdd(globalStateBuffer[0].tileEntryAllocator, count);
  uint particleStart = offset + globalStateBuffer[0].bPhase * PARTICLE_COUNT;
  for (uint i = particleStart/2; i < (particleStart + count)/2; i++) {
    packedPositions[i].u = 0;
  }
  tile.offset24count8 = offset << 8; // intentionally reset count
  tilesBuffer[tileIdx] = tile;
}

// in: globalStateBuffer, tilesBuffer
// out: tilesBuffer (?), packedPositions, particleAddresses, packedVelocities
uint insertTileEntry(vec2 pos, vec2 vel) {
  uint bPhase = globalStateBuffer[0].bPhase;

  vec2 tileCoordf = pos * vec2(TILE_COUNT_X, TILE_COUNT_Y);
  ivec2 tileCoord = ivec2(tileCoordf);
  tileCoord.x = clamp(tileCoord.x, 0, TILE_COUNT_X - 1);
  tileCoord.y = clamp(tileCoord.y, 0, TILE_COUNT_Y - 1);
  uint tileIdx = tileCoord.y * TILE_COUNT_X + tileCoord.x + bPhase * TILE_COUNT;

  uint tileOffs = tilesBuffer[tileIdx].offset24count8 >> 8;
  uint slot = atomicAdd(tilesBuffer[tileIdx].offset24count8, 1) & 0xFF;
  uint particleIdx = tileOffs + slot + bPhase * PARTICLE_COUNT;

  vec2 relPos = tileCoordf - vec2(tileCoord);
  relPos *= 256.0;
  uvec2 qpos = uvec2(relPos);
  qpos.x = clamp(qpos.x, 0, 255);
  qpos.y = clamp(qpos.y, 0, 255);
  uint packed = (qpos.x << 8) | qpos.y;
  packed = packed << ((particleIdx & 1) << 4);

  atomicOr(packedPositions[particleIdx / 2].u, packed);
  packedVelocities[particleIdx].u = packHalf2x16(vel);
  
  particleAddresses[particleIdx].u = (tileIdx << 8) | slot;
  
  return particleIdx;
}
