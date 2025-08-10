#version 460 core

#define SCREEN_WIDTH 1440
#define SCREEN_HEIGHT 1280
#define MAX_VERTS 1000
#define BITS_PER_BLOCK 256
#define NUM_LEVELS 3
#define BLOCKS_DIM_L2 16
#define BLOCKS_DIM_L1 256
#define BLOCKS_DIM_L0 4096
#define GRID_WIDTH_L2 256
#define GRID_WIDTH_L1 4096
#define GRID_WIDTH_L0 65536
#define NUM_BLOCKS_L2 256
#define NUM_BLOCKS_L1 65536
#define NUM_BLOCKS_L0 16777216

struct IndexedIndirectArgs {
  uint indexCount;
  uint instanceCount;
  uint firstIndex;
  uint vertexOffset;
  uint firstInstance;
};

struct IndirectArgs {
  uint vertexCount;
  uint instanceCount;
  uint firstVertex;
  uint firstInstance;
};

struct GlobalState {
  vec2 pan;
  float zoom;
  float padding;
};

struct Vertex {
  vec4 color;
  vec2 pos;
  vec2 padding;
};

struct Block {
  uvec4 bits[2];
};

struct VertexOutput {
  vec4 color;
  vec2 uv;
};

layout(set=1,binding=1) buffer BUFFER_globalState {  GlobalState globalState[]; };
layout(set=1,binding=2) buffer BUFFER_bitfield0 {  Block bitfield0[]; };
layout(set=1,binding=3) buffer BUFFER_bitfield1 {  Block bitfield1[]; };
layout(set=1,binding=4) buffer BUFFER_bitfield2 {  Block bitfield2[]; };
#include <FlrLib/Fluorescence.glsl>



#ifdef IS_PIXEL_SHADER
#if defined(_ENTRY_POINT_PS_Background) && !defined(_ENTRY_POINT_PS_Background_ATTACHMENTS)
#define _ENTRY_POINT_PS_Background_ATTACHMENTS
layout(location = 0) out vec4 outColor;
#endif // _ENTRY_POINT_PS_Background
#endif // IS_PIXEL_SHADER
#include "MultiLevelGrid2D.glsl"

#ifdef IS_COMP_SHADER
#ifdef _ENTRY_POINT_CS_Update
layout(local_size_x = 1, local_size_y = 1, local_size_z = 1) in;
void main() { CS_Update(); }
#endif // _ENTRY_POINT_CS_Update
#ifdef _ENTRY_POINT_CS_ClearBlocks
layout(local_size_x = 32, local_size_y = 1, local_size_z = 1) in;
void main() { CS_ClearBlocks(); }
#endif // _ENTRY_POINT_CS_ClearBlocks
#endif // IS_COMP_SHADER


#ifdef IS_VERTEX_SHADER
#ifdef _ENTRY_POINT_VS_Background
layout(location = 0) out VertexOutput _VERTEX_OUTPUT;
void main() { _VERTEX_OUTPUT = VS_Background(); }
#endif // _ENTRY_POINT_VS_Background
#endif // IS_VERTEX_SHADER


#ifdef IS_PIXEL_SHADER
#if defined(_ENTRY_POINT_PS_Background) && !defined(_ENTRY_POINT_PS_Background_INTERPOLANTS)
#define _ENTRY_POINT_PS_Background_INTERPOLANTS
layout(location = 0) in VertexOutput _VERTEX_INPUT;
void main() { PS_Background(_VERTEX_INPUT); }
#endif // _ENTRY_POINT_PS_Background
#endif // IS_PIXEL_SHADER
