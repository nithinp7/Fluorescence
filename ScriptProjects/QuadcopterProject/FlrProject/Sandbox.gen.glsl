#version 460 core

#define VERT_COUNT 57
#define SCREEN_WIDTH 1440
#define SCREEN_HEIGHT 1280
#define POS_FLOATS_COUNT 171
#define SPHERE_RES 12
#define SPHERE_VERT_COUNT 864
#define GIZMO_VERT_COUNT 2592
#define POINT_LIGHT_COUNT 5
#define MATERIAL_SLOT_GROUND 0
#define MATERIAL_SLOT_NODES 1
#define MATERIAL_SLOT_GIZMO_RED 2
#define MATERIAL_SLOT_GIZMO_GREEN 3
#define MATERIAL_SLOT_GIZMO_BLUE 4
#define MATERIAL_SLOT_MOTOR0 5
#define MATERIAL_SLOT_MOTOR1 6
#define MATERIAL_SLOT_MOTOR2 7
#define MATERIAL_SLOT_MOTOR3 8
#define MATERIAL_SLOT_COUNT 10
#define MAX_GIZMOS 500
#define FLOOR_HEIGHT -25.000000
#define SPHERE_RADIUS 0.500000

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

struct SimpleVertexOutput {
  vec2 uv;
};

struct VertexOutput {
  vec3 pos;
  vec3 normal;
  vec2 uv;
  vec4 debugColor;
  float materialIdx;
};

struct Material {
  vec3 diffuse;
  float roughness;
  vec3 emissive;
  float metallic;
  vec3 specular;
  float padding;
};

struct GizmoView {
  uint head;
  uint tail;
};

layout(set=1,binding=1) buffer BUFFER_positions {  float _INNER_positions[]; } _HEAP_positions [2];
#define positions(IDX) _HEAP_positions[IDX]._INNER_positions
layout(set=1,binding=2) buffer BUFFER_throttleData {  vec4 _INNER_throttleData[]; } _HEAP_throttleData [2];
#define throttleData(IDX) _HEAP_throttleData[IDX]._INNER_throttleData
layout(set=1,binding=3) buffer BUFFER_sphereVertexBuffer {  vec4 sphereVertexBuffer[]; };
layout(set=1,binding=4) buffer BUFFER_cylinderVertexBuffer {  vec4 cylinderVertexBuffer[]; };
layout(set=1,binding=5) buffer BUFFER_nodeMaterials {  uint nodeMaterials[]; };
layout(set=1,binding=6) buffer BUFFER_materialBuffer {  Material materialBuffer[]; };
layout(set=1,binding=7) buffer BUFFER_gizmoView {  GizmoView _INNER_gizmoView[]; } _HEAP_gizmoView [2];
#define gizmoView(IDX) _HEAP_gizmoView[IDX]._INNER_gizmoView
layout(set=1,binding=8) buffer BUFFER_gizmoBuffer {  mat4 gizmoBuffer[]; };
layout(set=1,binding=9) buffer BUFFER_shadowCamera {  mat4 shadowCamera[]; };
layout(set=1,binding=10) uniform sampler2D shadowMapTexture;

layout(set=1, binding=11) uniform _UserUniforms {
	vec4 SKY_COLOR;
	uint TRAIL_FREQUENCY;
	uint LOG_FREQUENCY;
	float ALT_PROP;
	float ALT_DIFF;
	float ALT_INT;
	float ROT_PROP;
	float ROT_DIFF;
	float ROT_INT;
	float THROTTLE0;
	float THROTTLE1;
	float THROTTLE2;
	float THROTTLE3;
	float GIZMO_SCALE;
	float GIZMO_THICKNESS;
	float EXPOSURE;
	float SUN_INT;
	float SUN_ELEV;
	float SUN_ROT;
	float SKY_INT;
	float HORIZON_WHITENESS;
	float HORIZON_WHITENESS_FALLOFF;
	bool ENABLE_SIM;
	bool USE_CONTROLLER;
	bool PIN_TO_ORIGIN;
	bool DISABLE_FLOOR;
	bool OSCILLATE_MOTORS;
	bool ENABLE_SHADOWS;
	bool SHOW_SHADOWMAP;
	bool SHOW_NORMALS;
};

#include <FlrLib/Fluorescence.glsl>

layout(set=1, binding=12) uniform _CameraUniforms { PerspectiveCamera camera; };



#ifdef IS_PIXEL_SHADER
#if defined(_ENTRY_POINT_PS_Shadow) && !defined(_ENTRY_POINT_PS_Shadow_ATTACHMENTS)
#define _ENTRY_POINT_PS_Shadow_ATTACHMENTS
#endif // _ENTRY_POINT_PS_Shadow
#if defined(_ENTRY_POINT_PS_Shadow) && !defined(_ENTRY_POINT_PS_Shadow_ATTACHMENTS)
#define _ENTRY_POINT_PS_Shadow_ATTACHMENTS
#endif // _ENTRY_POINT_PS_Shadow
#if defined(_ENTRY_POINT_PS_Sky) && !defined(_ENTRY_POINT_PS_Sky_ATTACHMENTS)
#define _ENTRY_POINT_PS_Sky_ATTACHMENTS
layout(location = 0) out vec4 outColor;
#endif // _ENTRY_POINT_PS_Sky
#if defined(_ENTRY_POINT_PS_Shaded) && !defined(_ENTRY_POINT_PS_Shaded_ATTACHMENTS)
#define _ENTRY_POINT_PS_Shaded_ATTACHMENTS
layout(location = 0) out vec4 outColor;
#endif // _ENTRY_POINT_PS_Shaded
#if defined(_ENTRY_POINT_PS_Shaded) && !defined(_ENTRY_POINT_PS_Shaded_ATTACHMENTS)
#define _ENTRY_POINT_PS_Shaded_ATTACHMENTS
layout(location = 0) out vec4 outColor;
#endif // _ENTRY_POINT_PS_Shaded
#if defined(_ENTRY_POINT_PS_Shaded) && !defined(_ENTRY_POINT_PS_Shaded_ATTACHMENTS)
#define _ENTRY_POINT_PS_Shaded_ATTACHMENTS
layout(location = 0) out vec4 outColor;
#endif // _ENTRY_POINT_PS_Shaded
#if defined(_ENTRY_POINT_PS_Overlay) && !defined(_ENTRY_POINT_PS_Overlay_ATTACHMENTS)
#define _ENTRY_POINT_PS_Overlay_ATTACHMENTS
layout(location = 0) out vec4 outColor;
#endif // _ENTRY_POINT_PS_Overlay
#endif // IS_PIXEL_SHADER
#include "Sandbox.glsl"

#ifdef IS_COMP_SHADER
#ifdef _ENTRY_POINT_CS_Init
layout(local_size_x = 1, local_size_y = 1, local_size_z = 1) in;
void main() { CS_Init(); }
#endif // _ENTRY_POINT_CS_Init
#ifdef _ENTRY_POINT_CS_UpdateCamera
layout(local_size_x = 32, local_size_y = 1, local_size_z = 1) in;
void main() { CS_UpdateCamera(); }
#endif // _ENTRY_POINT_CS_UpdateCamera
#endif // IS_COMP_SHADER


#ifdef IS_VERTEX_SHADER
#ifdef _ENTRY_POINT_VS_ShadowSphere
void main() { VS_ShadowSphere(); }
#endif // _ENTRY_POINT_VS_ShadowSphere
#ifdef _ENTRY_POINT_VS_ShadowGizmo
void main() { VS_ShadowGizmo(); }
#endif // _ENTRY_POINT_VS_ShadowGizmo
#ifdef _ENTRY_POINT_VS_Sky
layout(location = 0) out SimpleVertexOutput _VERTEX_OUTPUT;
void main() { _VERTEX_OUTPUT = VS_Sky(); }
#endif // _ENTRY_POINT_VS_Sky
#ifdef _ENTRY_POINT_VS_Floor
layout(location = 0) out VertexOutput _VERTEX_OUTPUT;
void main() { _VERTEX_OUTPUT = VS_Floor(); }
#endif // _ENTRY_POINT_VS_Floor
#ifdef _ENTRY_POINT_VS_Sphere
layout(location = 0) out VertexOutput _VERTEX_OUTPUT;
void main() { _VERTEX_OUTPUT = VS_Sphere(); }
#endif // _ENTRY_POINT_VS_Sphere
#ifdef _ENTRY_POINT_VS_Gizmo
layout(location = 0) out VertexOutput _VERTEX_OUTPUT;
void main() { _VERTEX_OUTPUT = VS_Gizmo(); }
#endif // _ENTRY_POINT_VS_Gizmo
#ifdef _ENTRY_POINT_VS_Overlay
layout(location = 0) out SimpleVertexOutput _VERTEX_OUTPUT;
void main() { _VERTEX_OUTPUT = VS_Overlay(); }
#endif // _ENTRY_POINT_VS_Overlay
#endif // IS_VERTEX_SHADER


#ifdef IS_PIXEL_SHADER
#if defined(_ENTRY_POINT_PS_Shadow) && !defined(_ENTRY_POINT_PS_Shadow_INTERPOLANTS)
#define _ENTRY_POINT_PS_Shadow_INTERPOLANTS
void main() { PS_Shadow(); }
#endif // _ENTRY_POINT_PS_Shadow
#if defined(_ENTRY_POINT_PS_Shadow) && !defined(_ENTRY_POINT_PS_Shadow_INTERPOLANTS)
#define _ENTRY_POINT_PS_Shadow_INTERPOLANTS
void main() { PS_Shadow(); }
#endif // _ENTRY_POINT_PS_Shadow
#if defined(_ENTRY_POINT_PS_Sky) && !defined(_ENTRY_POINT_PS_Sky_INTERPOLANTS)
#define _ENTRY_POINT_PS_Sky_INTERPOLANTS
layout(location = 0) in SimpleVertexOutput _VERTEX_INPUT;
void main() { PS_Sky(_VERTEX_INPUT); }
#endif // _ENTRY_POINT_PS_Sky
#if defined(_ENTRY_POINT_PS_Shaded) && !defined(_ENTRY_POINT_PS_Shaded_INTERPOLANTS)
#define _ENTRY_POINT_PS_Shaded_INTERPOLANTS
layout(location = 0) in VertexOutput _VERTEX_INPUT;
void main() { PS_Shaded(_VERTEX_INPUT); }
#endif // _ENTRY_POINT_PS_Shaded
#if defined(_ENTRY_POINT_PS_Shaded) && !defined(_ENTRY_POINT_PS_Shaded_INTERPOLANTS)
#define _ENTRY_POINT_PS_Shaded_INTERPOLANTS
layout(location = 0) in VertexOutput _VERTEX_INPUT;
void main() { PS_Shaded(_VERTEX_INPUT); }
#endif // _ENTRY_POINT_PS_Shaded
#if defined(_ENTRY_POINT_PS_Shaded) && !defined(_ENTRY_POINT_PS_Shaded_INTERPOLANTS)
#define _ENTRY_POINT_PS_Shaded_INTERPOLANTS
layout(location = 0) in VertexOutput _VERTEX_INPUT;
void main() { PS_Shaded(_VERTEX_INPUT); }
#endif // _ENTRY_POINT_PS_Shaded
#if defined(_ENTRY_POINT_PS_Overlay) && !defined(_ENTRY_POINT_PS_Overlay_INTERPOLANTS)
#define _ENTRY_POINT_PS_Overlay_INTERPOLANTS
layout(location = 0) in SimpleVertexOutput _VERTEX_INPUT;
void main() { PS_Overlay(_VERTEX_INPUT); }
#endif // _ENTRY_POINT_PS_Overlay
#endif // IS_PIXEL_SHADER
