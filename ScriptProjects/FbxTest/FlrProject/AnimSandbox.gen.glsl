#version 460 core

#define VERT_COUNT 146544
#define SCREEN_WIDTH 1440
#define SCREEN_HEIGHT 1280
#define POS_FLOATS_COUNT 439632
#define SPHERE_RES 12
#define SPHERE_VERT_COUNT 864

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
  vec3 normal;
  vec2 uv;
};

layout(set=1,binding=1) buffer BUFFER_positions {  float positions[]; };
layout(set=1,binding=2) buffer BUFFER_normals {  float normals[]; };
layout(set=1,binding=3) buffer BUFFER_sphereVertexBuffer {  vec4 sphereVertexBuffer[]; };

layout(set=1, binding=4) uniform _UserUniforms {
	uint BACKGROUND;
	float MESH_SCALE;
	float TEST_SLIDER;
};

#include <FlrLib/Fluorescence.glsl>

layout(set=1, binding=5) uniform _CameraUniforms { PerspectiveCamera camera; };



#ifdef IS_PIXEL_SHADER
#if defined(_ENTRY_POINT_PS_Test) && !defined(_ENTRY_POINT_PS_Test_ATTACHMENTS)
#define _ENTRY_POINT_PS_Test_ATTACHMENTS
layout(location = 0) out vec4 outColor;
#endif // _ENTRY_POINT_PS_Test
#if defined(_ENTRY_POINT_PS_Tris) && !defined(_ENTRY_POINT_PS_Tris_ATTACHMENTS)
#define _ENTRY_POINT_PS_Tris_ATTACHMENTS
layout(location = 0) out vec4 outColor;
#endif // _ENTRY_POINT_PS_Tris
#endif // IS_PIXEL_SHADER
#include "AnimSandbox.glsl"

#ifdef IS_COMP_SHADER
#ifdef _ENTRY_POINT_CS_Init
layout(local_size_x = 1, local_size_y = 1, local_size_z = 1) in;
void main() { CS_Init(); }
#endif // _ENTRY_POINT_CS_Init
#endif // IS_COMP_SHADER


#ifdef IS_VERTEX_SHADER
#ifdef _ENTRY_POINT_VS_Test
layout(location = 0) out VertexOutput _VERTEX_OUTPUT;
void main() { _VERTEX_OUTPUT = VS_Test(); }
#endif // _ENTRY_POINT_VS_Test
#ifdef _ENTRY_POINT_VS_Tris
layout(location = 0) out VertexOutput _VERTEX_OUTPUT;
void main() { _VERTEX_OUTPUT = VS_Tris(); }
#endif // _ENTRY_POINT_VS_Tris
#endif // IS_VERTEX_SHADER


#ifdef IS_PIXEL_SHADER
#if defined(_ENTRY_POINT_PS_Test) && !defined(_ENTRY_POINT_PS_Test_INTERPOLANTS)
#define _ENTRY_POINT_PS_Test_INTERPOLANTS
layout(location = 0) in VertexOutput _VERTEX_INPUT;
void main() { PS_Test(_VERTEX_INPUT); }
#endif // _ENTRY_POINT_PS_Test
#if defined(_ENTRY_POINT_PS_Tris) && !defined(_ENTRY_POINT_PS_Tris_INTERPOLANTS)
#define _ENTRY_POINT_PS_Tris_INTERPOLANTS
layout(location = 0) in VertexOutput _VERTEX_INPUT;
void main() { PS_Tris(_VERTEX_INPUT); }
#endif // _ENTRY_POINT_PS_Tris
#endif // IS_PIXEL_SHADER
