#version 460 core

#define SCREEN_WIDTH 1440
#define SCREEN_HEIGHT 1280
#define GRID_LEN 1000
#define GRID_CELLS 1000000
#define GRID_VERT_COUNT 5988006

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

struct Cell {
  float height;
};

struct VertexOutput {
  vec4 vertColor;
  vec2 uv;
};

layout(set=1,binding=1) buffer BUFFER_cellBuffer {  Cell cellBuffer[]; };
#include <FlrLib/Fluorescence.glsl>

layout(set=1, binding=2) uniform _CameraUniforms { PerspectiveCamera camera; };



#ifdef IS_PIXEL_SHADER
#if defined(_ENTRY_POINT_PS_Background) && !defined(_ENTRY_POINT_PS_Background_ATTACHMENTS)
#define _ENTRY_POINT_PS_Background_ATTACHMENTS
layout(location = 0) out vec4 outColor;
#endif // _ENTRY_POINT_PS_Background
#if defined(_ENTRY_POINT_PS_HeightField) && !defined(_ENTRY_POINT_PS_HeightField_ATTACHMENTS)
#define _ENTRY_POINT_PS_HeightField_ATTACHMENTS
layout(location = 0) out vec4 outColor;
#endif // _ENTRY_POINT_PS_HeightField
#endif // IS_PIXEL_SHADER
#include "HeightField.glsl"

#ifdef IS_COMP_SHADER
#ifdef _ENTRY_POINT_CS_Init
layout(local_size_x = 32, local_size_y = 1, local_size_z = 1) in;
void main() { CS_Init(); }
#endif // _ENTRY_POINT_CS_Init
#endif // IS_COMP_SHADER


#ifdef IS_VERTEX_SHADER
#ifdef _ENTRY_POINT_VS_Background
layout(location = 0) out VertexOutput _VERTEX_OUTPUT;
void main() { _VERTEX_OUTPUT = VS_Background(); }
#endif // _ENTRY_POINT_VS_Background
#ifdef _ENTRY_POINT_VS_HeightField
layout(location = 0) out VertexOutput _VERTEX_OUTPUT;
void main() { _VERTEX_OUTPUT = VS_HeightField(); }
#endif // _ENTRY_POINT_VS_HeightField
#endif // IS_VERTEX_SHADER


#ifdef IS_PIXEL_SHADER
#if defined(_ENTRY_POINT_PS_Background) && !defined(_ENTRY_POINT_PS_Background_INTERPOLANTS)
#define _ENTRY_POINT_PS_Background_INTERPOLANTS
layout(location = 0) in VertexOutput _VERTEX_INPUT;
void main() { PS_Background(_VERTEX_INPUT); }
#endif // _ENTRY_POINT_PS_Background
#if defined(_ENTRY_POINT_PS_HeightField) && !defined(_ENTRY_POINT_PS_HeightField_INTERPOLANTS)
#define _ENTRY_POINT_PS_HeightField_INTERPOLANTS
layout(location = 0) in VertexOutput _VERTEX_INPUT;
void main() { PS_HeightField(_VERTEX_INPUT); }
#endif // _ENTRY_POINT_PS_HeightField
#endif // IS_PIXEL_SHADER
