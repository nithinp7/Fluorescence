#version 460 core

#define SCREEN_WIDTH 1440
#define SCREEN_HEIGHT 1280

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

layout(set=1,binding=1) buffer BUFFER_testBuf {  float _INNER_testBuf[]; } _HEAP_testBuf [2];
#define testBuf(IDX) _HEAP_testBuf[IDX]._INNER_testBuf

layout(set=1, binding=2) uniform _UserUniforms {
	float TEST_SLIDER;
};

#include <FlrLib/Fluorescence.glsl>



#ifdef IS_PIXEL_SHADER
#if defined(_ENTRY_POINT_PS_Test) && !defined(_ENTRY_POINT_PS_Test_ATTACHMENTS)
#define _ENTRY_POINT_PS_Test_ATTACHMENTS
layout(location = 0) out vec4 outColor;
#endif // _ENTRY_POINT_PS_Test
#endif // IS_PIXEL_SHADER
#include "Test.glsl"

#ifdef IS_COMP_SHADER
#endif // IS_COMP_SHADER


#ifdef IS_VERTEX_SHADER
#ifdef _ENTRY_POINT_VS_Test
layout(location = 0) out VertexOutput _VERTEX_OUTPUT;
void main() { _VERTEX_OUTPUT = VS_Test(); }
#endif // _ENTRY_POINT_VS_Test
#endif // IS_VERTEX_SHADER


#ifdef IS_PIXEL_SHADER
#if defined(_ENTRY_POINT_PS_Test) && !defined(_ENTRY_POINT_PS_Test_INTERPOLANTS)
#define _ENTRY_POINT_PS_Test_INTERPOLANTS
layout(location = 0) in VertexOutput _VERTEX_INPUT;
void main() { PS_Test(_VERTEX_INPUT); }
#endif // _ENTRY_POINT_PS_Test
#endif // IS_PIXEL_SHADER
