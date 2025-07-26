#version 460 core

#define SCREEN_WIDTH 1276
#define SCREEN_HEIGHT 1321
#define GRID_LEN 100
#define GRID_POINTS 10000
#define GRID_CELLS 9801

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

struct VertexOutput {
  vec2 uv;
};;

struct Gradient {
  vec2 dir;
};

layout(set=1,binding=1) buffer BUFFER_gradients {  Gradient gradients[]; };

layout(set=1, binding=2) uniform _UserUniforms {
	uint SEED;
};

#include <FlrLib/Fluorescence.glsl>



#ifdef IS_PIXEL_SHADER
#if defined(_ENTRY_POINT_PS_DrawNoise) && !defined(_ENTRY_POINT_PS_DrawNoise_ATTACHMENTS)
#define _ENTRY_POINT_PS_DrawNoise_ATTACHMENTS
layout(location = 0) out vec4 outDisplay;
#endif // _ENTRY_POINT_PS_DrawNoise
#endif // IS_PIXEL_SHADER
#include "PerlinNoise.glsl"

#ifdef IS_COMP_SHADER
#ifdef _ENTRY_POINT_CS_InitGradients
layout(local_size_x = 8, local_size_y = 8, local_size_z = 1) in;
void main() { CS_InitGradients(); }
#endif // _ENTRY_POINT_CS_InitGradients
#endif // IS_COMP_SHADER


#ifdef IS_VERTEX_SHADER
#ifdef _ENTRY_POINT_VS_DrawNoise
layout(location = 0) out VertexOutput _VERTEX_OUTPUT;
void main() { _VERTEX_OUTPUT = VS_DrawNoise(); }
#endif // _ENTRY_POINT_VS_DrawNoise
#endif // IS_VERTEX_SHADER


#ifdef IS_PIXEL_SHADER
#if defined(_ENTRY_POINT_PS_DrawNoise) && !defined(_ENTRY_POINT_PS_DrawNoise_INTERPOLANTS)
#define _ENTRY_POINT_PS_DrawNoise_INTERPOLANTS
layout(location = 0) in VertexOutput _VERTEX_INPUT;
void main() { PS_DrawNoise(_VERTEX_INPUT); }
#endif // _ENTRY_POINT_PS_DrawNoise
#endif // IS_PIXEL_SHADER
