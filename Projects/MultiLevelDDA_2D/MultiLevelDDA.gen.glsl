#version 460 core

#define SCREEN_WIDTH 1440
#define SCREEN_HEIGHT 1280
#define MAX_VERTS 10000
#define BITS_PER_BLOCK 256
#define NUM_LEVELS 7
#define BR_FACTOR_LOG2 1
#define BR_FACTOR 2
#define BLOCKS_DIM_L6 1
#define BLOCKS_DIM_L5 2
#define BLOCKS_DIM_L4 4
#define BLOCKS_DIM_L3 8
#define BLOCKS_DIM_L2 16
#define BLOCKS_DIM_L1 32
#define BLOCKS_DIM_L0 64
#define GRID_WIDTH_L6 16
#define GRID_WIDTH_L5 32
#define GRID_WIDTH_L4 64
#define GRID_WIDTH_L3 128
#define GRID_WIDTH_L2 256
#define GRID_WIDTH_L1 512
#define GRID_WIDTH_L0 1024
#define NUM_BLOCKS_L6 1
#define NUM_BLOCKS_L5 4
#define NUM_BLOCKS_L4 16
#define NUM_BLOCKS_L3 64
#define NUM_BLOCKS_L2 256
#define NUM_BLOCKS_L1 1024
#define NUM_BLOCKS_L0 4096
#define NUM_BLOCKS_TOTAL 5461

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
  vec2 rayOrigin;
  float zoom;
  float rayAngle;
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
layout(set=1,binding=2) buffer BUFFER_lineVertexBuffer {  Vertex lineVertexBuffer[]; };
layout(set=1,binding=3) buffer BUFFER_triangleVertexBuffer {  Vertex triangleVertexBuffer[]; };
layout(set=1,binding=4) buffer BUFFER_linesIndirect {  IndirectArgs linesIndirect[]; };
layout(set=1,binding=5) buffer BUFFER_trianglesIndirect {  IndirectArgs trianglesIndirect[]; };
layout(set=1,binding=6) buffer BUFFER_bitfield {  Block bitfield[]; };

layout(set=1, binding=7) uniform _UserUniforms {
	uint RAY_DBG;
};

#include <FlrLib/Fluorescence.glsl>



#ifdef IS_PIXEL_SHADER
#if defined(_ENTRY_POINT_PS_Background) && !defined(_ENTRY_POINT_PS_Background_ATTACHMENTS)
#define _ENTRY_POINT_PS_Background_ATTACHMENTS
layout(location = 0) out vec4 outColor;
#endif // _ENTRY_POINT_PS_Background
#if defined(_ENTRY_POINT_PS_Triangles) && !defined(_ENTRY_POINT_PS_Triangles_ATTACHMENTS)
#define _ENTRY_POINT_PS_Triangles_ATTACHMENTS
layout(location = 0) out vec4 outColor;
#endif // _ENTRY_POINT_PS_Triangles
#if defined(_ENTRY_POINT_PS_Lines) && !defined(_ENTRY_POINT_PS_Lines_ATTACHMENTS)
#define _ENTRY_POINT_PS_Lines_ATTACHMENTS
layout(location = 0) out vec4 outColor;
#endif // _ENTRY_POINT_PS_Lines
#endif // IS_PIXEL_SHADER
#include "MultiLevelDDA.glsl"

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
#ifdef _ENTRY_POINT_VS_Triangles
layout(location = 0) out VertexOutput _VERTEX_OUTPUT;
void main() { _VERTEX_OUTPUT = VS_Triangles(); }
#endif // _ENTRY_POINT_VS_Triangles
#ifdef _ENTRY_POINT_VS_Lines
layout(location = 0) out VertexOutput _VERTEX_OUTPUT;
void main() { _VERTEX_OUTPUT = VS_Lines(); }
#endif // _ENTRY_POINT_VS_Lines
#endif // IS_VERTEX_SHADER


#ifdef IS_PIXEL_SHADER
#if defined(_ENTRY_POINT_PS_Background) && !defined(_ENTRY_POINT_PS_Background_INTERPOLANTS)
#define _ENTRY_POINT_PS_Background_INTERPOLANTS
layout(location = 0) in VertexOutput _VERTEX_INPUT;
void main() { PS_Background(_VERTEX_INPUT); }
#endif // _ENTRY_POINT_PS_Background
#if defined(_ENTRY_POINT_PS_Triangles) && !defined(_ENTRY_POINT_PS_Triangles_INTERPOLANTS)
#define _ENTRY_POINT_PS_Triangles_INTERPOLANTS
layout(location = 0) in VertexOutput _VERTEX_INPUT;
void main() { PS_Triangles(_VERTEX_INPUT); }
#endif // _ENTRY_POINT_PS_Triangles
#if defined(_ENTRY_POINT_PS_Lines) && !defined(_ENTRY_POINT_PS_Lines_INTERPOLANTS)
#define _ENTRY_POINT_PS_Lines_INTERPOLANTS
layout(location = 0) in VertexOutput _VERTEX_INPUT;
void main() { PS_Lines(_VERTEX_INPUT); }
#endif // _ENTRY_POINT_PS_Lines
#endif // IS_PIXEL_SHADER
