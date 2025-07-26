#version 460 core

#define SCREEN_WIDTH 1440
#define SCREEN_HEIGHT 1280
#define MAX_SCENE_TRIS 128
#define MAX_SCENE_SPHERES 12
#define MAX_LIGHT_COUNT 128
#define LIGHT_TYPE_TRI 0
#define LIGHT_TYPE_SPHERE 0
#define MAX_SCENE_MATERIALS 24
#define MAX_SCENE_VERTS 8192
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

struct GlobalState {
  uint accumulationFrames;
};

struct GlobalScene {
  uint triCount;
  uint sphereCount;
  uint lightCount;
  uint shereVertCount;
};

struct Tri {
  uint i0;
  uint i1;
  uint i2;
  uint matID;
};;

struct Sphere {
  vec3 c;
  float r;
  uint matID;
};;

struct Light {
  uint idx;
  uint type;
};;

struct Material {
  vec3 diffuse;
  float roughness;
  vec3 emissive;
  float metallic;
  vec3 specular;
  float padding;
};;

struct SceneVertex {
  vec3 pos;
};;

struct SceneVertexOutput {
  vec3 pos;
  vec3 normal;
  Material mat;
};

struct VertexOutput {
  vec2 screenUV;
};;

layout(set=1,binding=1) buffer BUFFER_globalStateBuffer {  GlobalState globalStateBuffer[]; };
layout(set=1,binding=2) buffer BUFFER_globalSceneBuffer {  GlobalScene globalSceneBuffer[]; };
layout(set=1,binding=3) buffer BUFFER_triBuffer {  Tri triBuffer[]; };
layout(set=1,binding=4) buffer BUFFER_sphereBuffer {  Sphere sphereBuffer[]; };
layout(set=1,binding=5) buffer BUFFER_materialBuffer {  Material materialBuffer[]; };
layout(set=1,binding=6) buffer BUFFER_sceneVertexBuffer {  SceneVertex sceneVertexBuffer[]; };
layout(set=1,binding=7) buffer BUFFER_lightBuffer {  Light lightBuffer[]; };
layout(set=1,binding=8) buffer BUFFER_trianglesIndirectArgs {  IndirectArgs trianglesIndirectArgs[]; };
layout(set=1,binding=9) buffer BUFFER_spheresIndirectArgs {  IndirectArgs spheresIndirectArgs[]; };
layout(set=1,binding=10, rgba32f) uniform image2D accumulationBuffer;
layout(set=1,binding=11, rgba32f) uniform image2D accumulationBuffer2;
layout(set=1,binding=12) uniform sampler2D accumulationTexture;
layout(set=1,binding=13) uniform sampler2D accumulationTexture2;

layout(set=1, binding=14) uniform _UserUniforms {
	vec4 DIFFUSE;
	vec4 SPECULAR;
	uint BOUNCES;
	uint BRDF_MODE;
	uint RENDER_MODE;
	uint BACKGROUND;
	float BLUR_RADIUS;
	float EXPOSURE;
	float BRDF_MIX;
	float ROUGHNESS;
	float BOUNCE_BIAS;
	float SCENE_SCALE;
	bool ACCUMULATE;
	bool JITTER;
	bool SPEC_SAMPLE;
	bool OVERRIDE_DIFFUSE;
	bool OVERRIDE_SPECULAR;
	bool OVERRIDE_ROUGHNESS;
};

#include <FlrLib/Fluorescence.glsl>

layout(set=1, binding=15) uniform _CameraUniforms { PerspectiveCamera camera; };



#ifdef IS_PIXEL_SHADER
#if defined(_ENTRY_POINT_PS_Render) && !defined(_ENTRY_POINT_PS_Render_ATTACHMENTS)
#define _ENTRY_POINT_PS_Render_ATTACHMENTS
layout(location = 0) out vec4 outColor;
#endif // _ENTRY_POINT_PS_Render
#endif // IS_PIXEL_SHADER
#include "CornellBox.glsl"

#ifdef IS_COMP_SHADER
#ifdef _ENTRY_POINT_CS_InitCornellBox
layout(local_size_x = 1, local_size_y = 1, local_size_z = 1) in;
void main() { CS_InitCornellBox(); }
#endif // _ENTRY_POINT_CS_InitCornellBox
#ifdef _ENTRY_POINT_CS_Tick
layout(local_size_x = 1, local_size_y = 1, local_size_z = 1) in;
void main() { CS_Tick(); }
#endif // _ENTRY_POINT_CS_Tick
#ifdef _ENTRY_POINT_CS_PathTrace
layout(local_size_x = 32, local_size_y = 32, local_size_z = 1) in;
void main() { CS_PathTrace(); }
#endif // _ENTRY_POINT_CS_PathTrace
#endif // IS_COMP_SHADER


#ifdef IS_VERTEX_SHADER
#ifdef _ENTRY_POINT_VS_Render
layout(location = 0) out VertexOutput _VERTEX_OUTPUT;
void main() { _VERTEX_OUTPUT = VS_Render(); }
#endif // _ENTRY_POINT_VS_Render
#endif // IS_VERTEX_SHADER


#ifdef IS_PIXEL_SHADER
#if defined(_ENTRY_POINT_PS_Render) && !defined(_ENTRY_POINT_PS_Render_INTERPOLANTS)
#define _ENTRY_POINT_PS_Render_INTERPOLANTS
layout(location = 0) in VertexOutput _VERTEX_INPUT;
void main() { PS_Render(_VERTEX_INPUT); }
#endif // _ENTRY_POINT_PS_Render
#endif // IS_PIXEL_SHADER
