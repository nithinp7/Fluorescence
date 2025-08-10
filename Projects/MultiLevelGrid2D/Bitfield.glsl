#ifndef _BITFIELD_GLSL_
#define _BITFIELD_GLSL_

void setBitAtomicOr(int i, int j) {
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

    uint blockIdx = yBlock * blocksDim + xBlock;
    uint flatLocalIdx = (yLocal << 4) | xLocal;
    uint bitshift = ((yLocal & 1) << 4) | xLocal;
    uint bit = 1 << bitshift;
    uint uvec4Idx = yLocal >> 3;
    uint uintIdx = (yLocal >> 1) & 3;

    if (level == 0)
      atomicOr(bitfield0[blockIdx].bits[uvec4Idx][uintIdx], bit);
    else if (level == 1)
      atomicOr(bitfield1[blockIdx].bits[uvec4Idx][uintIdx], bit);
    else if (level == 2)
      atomicOr(bitfield2[blockIdx].bits[uvec4Idx][uintIdx], bit);

    i = int(xBlock);
    j = int(yBlock);
    blocksDim >>= 4;
  }
}

void setBlock(uint level, uint blockIdx, uvec4 v[2]) {
  if (level == 0 && blockIdx < NUM_BLOCKS_L0) {
    bitfield0[blockIdx].bits[0] = v[0];
    bitfield0[blockIdx].bits[1] = v[0];
  }
  
  if (level == 1 && blockIdx < NUM_BLOCKS_L1) {
    bitfield1[blockIdx].bits[0] = v[0];
    bitfield1[blockIdx].bits[1] = v[0];
  }
  
  if (level == 2 && blockIdx < NUM_BLOCKS_L0) {
    bitfield2[blockIdx].bits[0] = v[0];
    bitfield2[blockIdx].bits[1] = v[0];
  }
}

bool getBit(uint level, int i, int j) {
  uint blocksDim = BLOCKS_DIM_L0 >> (level << 2);
  uint gridWidth = blocksDim << 4;

  if (i < 0 || i >= gridWidth || j < 0 || j >= gridWidth) 
    return false;
  
  uint xBlock = uint(i >> 4);
  uint yBlock = uint(j >> 4);
  uint xLocal = uint(i & 0xF);
  uint yLocal = uint(j & 0xF);

  uint blockIdx = yBlock * blocksDim + xBlock;
  uint flatLocalIdx = (yLocal << 4) | xLocal;
  uint bitshift = ((yLocal & 1) << 4) | xLocal;
  uint bit = 1 << bitshift;
  uint uvec4Idx = yLocal >> 3;
  uint uintIdx = (yLocal >> 1) & 3;
  
  if (level == 0)
    return (bitfield0[blockIdx].bits[uvec4Idx][uintIdx] & bit) != 0;
  else if (level == 1)
    return (bitfield1[blockIdx].bits[uvec4Idx][uintIdx] & bit) != 0;
  else if (level == 2)
    return (bitfield2[blockIdx].bits[uvec4Idx][uintIdx] & bit) != 0;

  return false;
}
#endif // _BITFIELD_GLSL_