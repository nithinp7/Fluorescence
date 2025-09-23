#ifndef _BITFIELD_GLSL_
#define _BITFIELD_GLSL_

uint getBlockOffset(uint level) {
  return
    ((level > 0) ? NUM_BLOCKS_L0 : 0) +
    ((level > 1) ? NUM_BLOCKS_L1 : 0) +
    ((level > 2) ? NUM_BLOCKS_L2 : 0) +
    ((level > 3) ? NUM_BLOCKS_L3 : 0) + 
    ((level > 4) ? NUM_BLOCKS_L4 : 0) + 
    ((level > 5) ? NUM_BLOCKS_L5 : 0) + 
    ((level > 6) ? NUM_BLOCKS_L6 : 0);
}

void setBitAtomicOr(int i, int j) {
  uint blockOffset = 0;
  uint blocksDim = BLOCKS_DIM_L0;
  uint gridWidth = blocksDim << 4;
  
  if (i < 0 || i >= gridWidth || j < 0 || j >= gridWidth)
    return;
  // 256 = 16*16
  for (uint level = 0; level < NUM_LEVELS; level++) {
    uint xBlock = uint(i >> 4);
    uint yBlock = uint(j >> 4);
    uint xLocal = uint(i & 0xF);
    uint yLocal = uint(j & 0xF);

    uint blockIdx = blockOffset + yBlock * blocksDim + xBlock;
    uint flatLocalIdx = (yLocal << 4) | xLocal;
    uint bitshift = ((yLocal & 1) << 4) | xLocal;
    uint bit = 1 << bitshift;
    uint uvec4Idx = yLocal >> 3;
    uint uintIdx = (yLocal >> 1) & 3;

    atomicOr(bitfield[blockIdx].bits[uvec4Idx][uintIdx], bit);
    
    i >>= BR_FACTOR_LOG2;
    j >>= BR_FACTOR_LOG2;
    blockOffset += blocksDim * blocksDim;
    blocksDim >>= BR_FACTOR_LOG2;
  }
}

void setBlock(uint blockIdx, uvec4 v[2]) {
  bitfield[blockIdx].bits[0] = v[0];
  bitfield[blockIdx].bits[1] = v[0];
}

bool getBit(uint level, int i, int j) {
  uint blockOffset = getBlockOffset(level);
  uint blocksDim = BLOCKS_DIM_L0 >> (BR_FACTOR_LOG2 * level);
  uint gridWidth = blocksDim << 4;

  if (i < 0 || i >= gridWidth || j < 0 || j >= gridWidth) 
    return false;
  
  uint xBlock = uint(i >> 4);
  uint yBlock = uint(j >> 4);
  uint xLocal = uint(i & 0xF);
  uint yLocal = uint(j & 0xF);

  uint blockIdx = blockOffset + yBlock * blocksDim + xBlock;
  uint flatLocalIdx = (yLocal << 4) | xLocal;
  uint bitshift = ((yLocal & 1) << 4) | xLocal;
  uint bit = 1 << bitshift;
  uint uvec4Idx = yLocal >> 3;
  uint uintIdx = (yLocal >> 1) & 3;
  
  return (bitfield[blockIdx].bits[uvec4Idx][uintIdx] & bit) != 0;
}
#endif // _BITFIELD_GLSL_