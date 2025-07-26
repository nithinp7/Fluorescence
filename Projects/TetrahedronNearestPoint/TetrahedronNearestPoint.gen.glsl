#version 460 core

#define SCREEN_WIDTH 1440
#define SCREEN_HEIGHT 1280
#define MAX_VERTS 100
#define SPHERE_RES 12
#define SPHERE_VERT_COUNT 864
#define MAX_LINE_VERT_COUNT 100

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

struct Vertex {
  vec4 position;
  vec4 color;
};

struct SimpleVertex {
  vec4 position;
};

struct ScreenVertexOutput {
  vec2 uv;
};

struct VertexOutput {
  vec4 color;
  vec3 normal;
};

layout(set=1,binding=1) buffer BUFFER_vertexBuffer {  Vertex vertexBuffer[]; };
layout(set=1,binding=2) buffer BUFFER_trianglesIndirect {  IndirectArgs trianglesIndirect[]; };
layout(set=1,binding=3) buffer BUFFER_spheresIndirect {  IndirectArgs spheresIndirect[]; };
layout(set=1,binding=4) buffer BUFFER_linesIndirect {  IndirectArgs linesIndirect[]; };
layout(set=1,binding=5) buffer BUFFER_sphereVertexBuffer {  SimpleVertex sphereVertexBuffer[]; };
layout(set=1,binding=6) buffer BUFFER_lineVertexBuffer {  Vertex lineVertexBuffer[]; };
#include <FlrLib/Fluorescence.glsl>

layout(set=1, binding=7) uniform _CameraUniforms { PerspectiveCamera camera; };



#ifdef IS_PIXEL_SHADER
#if defined(_ENTRY_POINT_PS_Background) && !defined(_ENTRY_POINT_PS_Background_ATTACHMENTS)
#define _ENTRY_POINT_PS_Background_ATTACHMENTS
layout(location = 0) out vec4 outColor;
#endif // _ENTRY_POINT_PS_Background
#if defined(_ENTRY_POINT_PS_Points) && !defined(_ENTRY_POINT_PS_Points_ATTACHMENTS)
#define _ENTRY_POINT_PS_Points_ATTACHMENTS
layout(location = 0) out vec4 outColor;
#endif // _ENTRY_POINT_PS_Points
#if defined(_ENTRY_POINT_PS_Triangles) && !defined(_ENTRY_POINT_PS_Triangles_ATTACHMENTS)
#define _ENTRY_POINT_PS_Triangles_ATTACHMENTS
layout(location = 0) out vec4 outColor;
#endif // _ENTRY_POINT_PS_Triangles
#if defined(_ENTRY_POINT_PS_Lines) && !defined(_ENTRY_POINT_PS_Lines_ATTACHMENTS)
#define _ENTRY_POINT_PS_Lines_ATTACHMENTS
layout(location = 0) out vec4 outColor;
#endif // _ENTRY_POINT_PS_Lines
#endif // IS_PIXEL_SHADER
#include "TetrahedronNearestPoint.glsl"

#ifdef IS_COMP_SHADER
#ifdef _ENTRY_POINT_CS_Init
layout(local_size_x = 1, local_size_y = 1, local_size_z = 1) in;
void main() { CS_Init(); }
#endif // _ENTRY_POINT_CS_Init
#ifdef _ENTRY_POINT_CS_Update
layout(local_size_x = 1, local_size_y = 1, local_size_z = 1) in;
void main() { CS_Update(); }
#endif // _ENTRY_POINT_CS_Update
#endif // IS_COMP_SHADER


#ifdef IS_VERTEX_SHADER
#ifdef _ENTRY_POINT_VS_Background
layout(location = 0) out ScreenVertexOutput _VERTEX_OUTPUT;
void main() { _VERTEX_OUTPUT = VS_Background(); }
#endif // _ENTRY_POINT_VS_Background
#ifdef _ENTRY_POINT_VS_Points
layout(location = 0) out VertexOutput _VERTEX_OUTPUT;
void main() { _VERTEX_OUTPUT = VS_Points(); }
#endif // _ENTRY_POINT_VS_Points
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
layout(location = 0) in ScreenVertexOutput _VERTEX_INPUT;
void main() { PS_Background(_VERTEX_INPUT); }
#endif // _ENTRY_POINT_PS_Background
#if defined(_ENTRY_POINT_PS_Points) && !defined(_ENTRY_POINT_PS_Points_INTERPOLANTS)
#define _ENTRY_POINT_PS_Points_INTERPOLANTS
layout(location = 0) in VertexOutput _VERTEX_INPUT;
void main() { PS_Points(_VERTEX_INPUT); }
#endif // _ENTRY_POINT_PS_Points
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
