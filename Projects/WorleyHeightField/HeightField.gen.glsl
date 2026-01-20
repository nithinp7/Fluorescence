#version 460 core

#define SCREEN_WIDTH 1440
#define SCREEN_HEIGHT 1280
#define GRID_LEN 1024
#define GRID_CELLS 1048576
#define GRID_VERT_COUNT 6279174
#define SKIRT_VERT_COUNT 24552
#define GRID_SPACING 0.100000

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

struct GlobalState {
  vec2 uvOffset;
  float phaseOffset;
  float lastTime;
};

struct VertexOutput {
  vec3 pos;
  vec3 normal;
  vec2 uv;
};

layout(set=1,binding=1) buffer BUFFER_globalState {  GlobalState globalState[]; };
layout(set=1,binding=2) buffer BUFFER_cellBuffer {  float cellBuffer[]; };
layout(set=1,binding=3) buffer BUFFER_cellNormals {  vec4 cellNormals[]; };
layout(set=1,binding=4) buffer BUFFER_shadowCamera {  mat4 shadowCamera[]; };
layout(set=1,binding=5) uniform sampler2D shadowMapTexture;
layout(set=1,binding=6) uniform sampler2D Worley8x8;
layout(set=1,binding=7) uniform sampler2D Worley16x16;
layout(set=1,binding=8) uniform sampler2D Worley32x32;

layout(set=1, binding=9) uniform _UserUniforms {
	vec4 SCATTER;
	vec4 SKY_COLOR;
	uint STEP_COUNT;
	uint DEBUG_MODE;
	float NOISE_SCALE;
	float NOISE_LEVEL0;
	float NOISE_LEVEL1;
	float NOISE_LEVEL2;
	float MEAN_FLOW_X;
	float MEAN_FLOW_Y;
	float TURB_AMP;
	float TURB_FREQ;
	float TURB_SPEED;
	float TURB_ROT;
	float TURB_EXP;
	float POWDER;
	float DENSITY;
	float G;
	float JITTER;
	float STEP_SIZE;
	float SUN_INT;
	float SUN_ELEV;
	float SUN_ROT;
	float SKY_INT;
	float HORIZON_WHITENESS;
	float HORIZON_WHITENESS_FALLOFF;
	float EXPOSURE;
};

#include <FlrLib/Fluorescence.glsl>

layout(set=1, binding=10) uniform _CameraUniforms { PerspectiveCamera camera; };



#ifdef IS_PIXEL_SHADER
#if defined(_ENTRY_POINT_PS_Shadow) && !defined(_ENTRY_POINT_PS_Shadow_ATTACHMENTS)
#define _ENTRY_POINT_PS_Shadow_ATTACHMENTS
#endif // _ENTRY_POINT_PS_Shadow
#if defined(_ENTRY_POINT_PS_Shadow) && !defined(_ENTRY_POINT_PS_Shadow_ATTACHMENTS)
#define _ENTRY_POINT_PS_Shadow_ATTACHMENTS
#endif // _ENTRY_POINT_PS_Shadow
#if defined(_ENTRY_POINT_PS_Background) && !defined(_ENTRY_POINT_PS_Background_ATTACHMENTS)
#define _ENTRY_POINT_PS_Background_ATTACHMENTS
layout(location = 0) out vec4 outColor;
#endif // _ENTRY_POINT_PS_Background
#if defined(_ENTRY_POINT_PS_HeightField) && !defined(_ENTRY_POINT_PS_HeightField_ATTACHMENTS)
#define _ENTRY_POINT_PS_HeightField_ATTACHMENTS
layout(location = 0) out vec4 outColor;
#endif // _ENTRY_POINT_PS_HeightField
#if defined(_ENTRY_POINT_PS_HeightField) && !defined(_ENTRY_POINT_PS_HeightField_ATTACHMENTS)
#define _ENTRY_POINT_PS_HeightField_ATTACHMENTS
layout(location = 0) out vec4 outColor;
#endif // _ENTRY_POINT_PS_HeightField
#endif // IS_PIXEL_SHADER
#include "HeightField.glsl"

#ifdef IS_COMP_SHADER
#ifdef _ENTRY_POINT_CS_Update
layout(local_size_x = 8, local_size_y = 8, local_size_z = 1) in;
void main() { CS_Update(); }
#endif // _ENTRY_POINT_CS_Update
#ifdef _ENTRY_POINT_CS_GenNormals
layout(local_size_x = 8, local_size_y = 8, local_size_z = 1) in;
void main() { CS_GenNormals(); }
#endif // _ENTRY_POINT_CS_GenNormals
#ifdef _ENTRY_POINT_CS_UpdateShadowCamera
layout(local_size_x = 1, local_size_y = 1, local_size_z = 1) in;
void main() { CS_UpdateShadowCamera(); }
#endif // _ENTRY_POINT_CS_UpdateShadowCamera
#endif // IS_COMP_SHADER


#ifdef IS_VERTEX_SHADER
#ifdef _ENTRY_POINT_VS_ShadowHeightField
void main() { VS_ShadowHeightField(); }
#endif // _ENTRY_POINT_VS_ShadowHeightField
#ifdef _ENTRY_POINT_VS_ShadowSkirts
void main() { VS_ShadowSkirts(); }
#endif // _ENTRY_POINT_VS_ShadowSkirts
#ifdef _ENTRY_POINT_VS_Background
layout(location = 0) out VertexOutput _VERTEX_OUTPUT;
void main() { _VERTEX_OUTPUT = VS_Background(); }
#endif // _ENTRY_POINT_VS_Background
#ifdef _ENTRY_POINT_VS_HeightField
layout(location = 0) out VertexOutput _VERTEX_OUTPUT;
void main() { _VERTEX_OUTPUT = VS_HeightField(); }
#endif // _ENTRY_POINT_VS_HeightField
#ifdef _ENTRY_POINT_VS_Skirts
layout(location = 0) out VertexOutput _VERTEX_OUTPUT;
void main() { _VERTEX_OUTPUT = VS_Skirts(); }
#endif // _ENTRY_POINT_VS_Skirts
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
#if defined(_ENTRY_POINT_PS_HeightField) && !defined(_ENTRY_POINT_PS_HeightField_INTERPOLANTS)
#define _ENTRY_POINT_PS_HeightField_INTERPOLANTS
layout(location = 0) in VertexOutput _VERTEX_INPUT;
void main() { PS_HeightField(_VERTEX_INPUT); }
#endif // _ENTRY_POINT_PS_HeightField
#endif // IS_PIXEL_SHADER
