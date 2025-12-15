#version 460 core

#define SCREEN_WIDTH 1440
#define SCREEN_HEIGHT 1280
#define GRID_WIDTH 800
#define GRID_NUM_POINTS 640000
#define GRID_NUM_INDICES 3830406
#define VISC_MAX 10.000000

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

struct GridVertex {
  vec3 pos;
  vec2 uv;
};

layout(set=1,binding=1) buffer BUFFER_gridIndices {  uint gridIndices[]; };
layout(set=1,binding=2, rg16f) uniform image2D HeightImage;
layout(set=1,binding=3, rgba16f) uniform image2D FlowFieldImage;
layout(set=1,binding=4, rgba16f) uniform image2D PrevFlowFieldImage;
layout(set=1,binding=5) uniform sampler2D HeightTexture;
layout(set=1,binding=6) uniform sampler2D FlowFieldTexture;
layout(set=1,binding=7) uniform sampler2D PrevFlowFieldTexture;

layout(set=1, binding=8) uniform _UserUniforms {
	vec4 SKY_COLOR;
	float INLET_SPEED;
	float INLET_HEIGHT;
	float VISC;
	float TEST;
	float EXPOSURE;
	float SUN_INT;
	float SUN_ELEV;
	float SUN_ROT;
	float SKY_INT;
	float HORIZON_WHITENESS;
	float HORIZON_WHITENESS_FALLOFF;
	bool SHOW_FLOW;
};

#include <FlrLib/Fluorescence.glsl>

layout(set=1, binding=9) uniform _CameraUniforms { PerspectiveCamera camera; };



#ifdef IS_PIXEL_SHADER
#if defined(_ENTRY_POINT_PS_Background) && !defined(_ENTRY_POINT_PS_Background_ATTACHMENTS)
#define _ENTRY_POINT_PS_Background_ATTACHMENTS
layout(location = 0) out vec4 outColor;
#endif // _ENTRY_POINT_PS_Background
#if defined(_ENTRY_POINT_PS_Grid) && !defined(_ENTRY_POINT_PS_Grid_ATTACHMENTS)
#define _ENTRY_POINT_PS_Grid_ATTACHMENTS
layout(location = 0) out vec4 outColor;
#endif // _ENTRY_POINT_PS_Grid
#endif // IS_PIXEL_SHADER
#include "Meander.glsl"

#ifdef IS_COMP_SHADER
#ifdef _ENTRY_POINT_CS_Init
layout(local_size_x = 1, local_size_y = 1, local_size_z = 1) in;
void main() { CS_Init(); }
#endif // _ENTRY_POINT_CS_Init
#ifdef _ENTRY_POINT_CS_InitHeight
layout(local_size_x = 8, local_size_y = 8, local_size_z = 1) in;
void main() { CS_InitHeight(); }
#endif // _ENTRY_POINT_CS_InitHeight
#ifdef _ENTRY_POINT_CS_UpdateFlow
layout(local_size_x = 8, local_size_y = 8, local_size_z = 1) in;
void main() { CS_UpdateFlow(); }
#endif // _ENTRY_POINT_CS_UpdateFlow
#ifdef _ENTRY_POINT_CS_UpdateHeight
layout(local_size_x = 8, local_size_y = 8, local_size_z = 1) in;
void main() { CS_UpdateHeight(); }
#endif // _ENTRY_POINT_CS_UpdateHeight
#ifdef _ENTRY_POINT_CS_CopyFlow
layout(local_size_x = 8, local_size_y = 8, local_size_z = 1) in;
void main() { CS_CopyFlow(); }
#endif // _ENTRY_POINT_CS_CopyFlow
#endif // IS_COMP_SHADER


#ifdef IS_VERTEX_SHADER
#ifdef _ENTRY_POINT_VS_Background
layout(location = 0) out VertexOutput _VERTEX_OUTPUT;
void main() { _VERTEX_OUTPUT = VS_Background(); }
#endif // _ENTRY_POINT_VS_Background
#ifdef _ENTRY_POINT_VS_Grid
layout(location = 0) out GridVertex _VERTEX_OUTPUT;
void main() { _VERTEX_OUTPUT = VS_Grid(); }
#endif // _ENTRY_POINT_VS_Grid
#endif // IS_VERTEX_SHADER


#ifdef IS_PIXEL_SHADER
#if defined(_ENTRY_POINT_PS_Background) && !defined(_ENTRY_POINT_PS_Background_INTERPOLANTS)
#define _ENTRY_POINT_PS_Background_INTERPOLANTS
layout(location = 0) in VertexOutput _VERTEX_INPUT;
void main() { PS_Background(_VERTEX_INPUT); }
#endif // _ENTRY_POINT_PS_Background
#if defined(_ENTRY_POINT_PS_Grid) && !defined(_ENTRY_POINT_PS_Grid_INTERPOLANTS)
#define _ENTRY_POINT_PS_Grid_INTERPOLANTS
layout(location = 0) in GridVertex _VERTEX_INPUT;
void main() { PS_Grid(_VERTEX_INPUT); }
#endif // _ENTRY_POINT_PS_Grid
#endif // IS_PIXEL_SHADER
