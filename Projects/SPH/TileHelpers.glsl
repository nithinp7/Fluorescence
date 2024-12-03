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

vec2 unpackPosFromTileAddr(uint tileAddr) {
  uint tileIdx = tileAddr >> 4;
  uint slot = tileAddr & 0xF;
  
  ivec2 tileCoord = ivec2(tileIdx % TILE_COUNT_X, tileIdx / TILE_COUNT_X);
  vec2 tileCoordf = vec2(tileCoord);
  
  uint packed = tilesBuffer[tileIdx].packedPositions[slot/2];
  packed = (packed >> ((slot & 1) << 4)) & 0xFFFF;
  uvec2 qpos = uvec2(packed >> 8, packed & 0xFF);
  vec2 particlePos = (tileCoordf + qpos / 256.0) / vec2(TILE_COUNT_X, TILE_COUNT_Y);
  
  return particlePos;
}

vec2 unpackVelocityFromTileAddr(uint tileAddr) {
  uint tileIdx = tileAddr >> 4;
  uint slot = tileAddr & 0xF;
  return unpackHalf2x16(tilesBuffer[tileIdx].packedVelocities[slot]);
}

uint insertPosVelToTile(vec2 pos, vec2 vel) {
  vec2 tileCoordf = pos * vec2(TILE_COUNT_X, TILE_COUNT_Y);
  ivec2 tileCoord = ivec2(tileCoordf);
  tileCoord.x = clamp(tileCoord.x, 0, TILE_COUNT_X - 1);
  tileCoord.y = clamp(tileCoord.y, 0, TILE_COUNT_Y - 1);
  uint tileIdx = tileCoord.y * TILE_COUNT_X + tileCoord.x;
  uint slot = atomicAdd(tilesBuffer[tileIdx].count, 1);

  if (slot >= PACKED_PARTICLES_PER_TILE)
    return ~0;

  vec2 relPos = tileCoordf - vec2(tileCoord);
  relPos *= 256.0;
  uvec2 qpos = uvec2(relPos);
  qpos.x = clamp(qpos.x, 0, 255);
  qpos.y = clamp(qpos.y, 0, 255);
  uint packed = (qpos.x << 8) | qpos.y;
  packed = packed << ((slot & 1) << 4);

  atomicOr(tilesBuffer[tileIdx].packedPositions[slot / 2], packed);

  tilesBuffer[tileIdx].packedVelocities[slot] = packHalf2x16(vel);

  // TODO shader-assert here about tile size
  return (tileIdx << 4) | slot;
}

uint getParticleCountFromTile(uint tileIdx) {
  return min(tilesBuffer[tileIdx].count, PACKED_PARTICLES_PER_TILE-1);
}
