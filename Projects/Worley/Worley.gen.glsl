#version 460 core

#define SCREEN_WIDTH 1440
#define SCREEN_HEIGHT 1280
#define OUT_IMAGE_WIDTH 128
#define MAX_WORLEY_GRID_DIM 256
#define MAX_WORLEY_GRID_CELLS 65536

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

struct IndirectDispatch {
  uint groupCountX;
  uint groupCountY;
  uint groupCountZ;
};

struct VertexOutput {
  vec2 uv;
};

layout(set=1,binding=1) buffer BUFFER_worleySeeds {  vec2 worleySeeds[]; };
layout(set=1,binding=2, rgba8) uniform image2D WorleyImage;
layout(set=1,binding=3) uniform sampler2D WorleyTexture;

layout(set=1, binding=4) uniform _UserUniforms {
	uint WORLEY_GRID_DIM;
	uint GEN_SEED;
};

#include <FlrLib/Fluorescence.glsl>



#ifdef IS_PIXEL_SHADER
#if defined(_ENTRY_POINT_PS_Worley) && !defined(_ENTRY_POINT_PS_Worley_ATTACHMENTS)
#define _ENTRY_POINT_PS_Worley_ATTACHMENTS
layout(location = 0) out vec4 outColor;
#endif // _ENTRY_POINT_PS_Worley
#endif // IS_PIXEL_SHADER
#include "Worley.glsl"

#ifdef IS_COMP_SHADER
#ifdef _ENTRY_POINT_CS_InitSeeds
layout(local_size_x = 8, local_size_y = 8, local_size_z = 1) in;
void main() { CS_InitSeeds(); }
#endif // _ENTRY_POINT_CS_InitSeeds
#ifdef _ENTRY_POINT_CS_Worley
layout(local_size_x = 8, local_size_y = 8, local_size_z = 1) in;
void main() { CS_Worley(); }
#endif // _ENTRY_POINT_CS_Worley
#endif // IS_COMP_SHADER


#ifdef IS_VERTEX_SHADER
#ifdef _ENTRY_POINT_VS_Worley
layout(location = 0) out VertexOutput _VERTEX_OUTPUT;
void main() { _VERTEX_OUTPUT = VS_Worley(); }
#endif // _ENTRY_POINT_VS_Worley
#endif // IS_VERTEX_SHADER


#ifdef IS_PIXEL_SHADER
#if defined(_ENTRY_POINT_PS_Worley) && !defined(_ENTRY_POINT_PS_Worley_INTERPOLANTS)
#define _ENTRY_POINT_PS_Worley_INTERPOLANTS
layout(location = 0) in VertexOutput _VERTEX_INPUT;
void main() { PS_Worley(_VERTEX_INPUT); }
#endif // _ENTRY_POINT_PS_Worley
#endif // IS_PIXEL_SHADER
