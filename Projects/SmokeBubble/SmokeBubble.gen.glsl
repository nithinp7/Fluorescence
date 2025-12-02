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


layout(set=1, binding=1) uniform _UserUniforms {
	vec4 SKY_COLOR;
	uint SAMPLE_COUNT;
	uint RM_ITERS;
	uint SHADOW_ITERS;
	float ETA;
	float DENSITY;
	float SHADOW_DT;
	float RM_0;
	float RM_1;
	float TURB_MULT;
	float TURB_AMP;
	float TURB_FREQ;
	float TURB_SPEED;
	float TURB_ROT;
	float TURB_EXP;
	float SUN_INT;
	float SUN_ELEV;
	float SUN_ROT;
	float SKY_INT;
	float HORIZON_WHITENESS;
	float HORIZON_WHITENESS_FALLOFF;
	float EXPOSURE;
	bool REFRACT_BUBBLE;
	bool APPLY_TURBULENCE;
};

#include <FlrLib/Fluorescence.glsl>

layout(set=1, binding=2) uniform _CameraUniforms { PerspectiveCamera camera; };



#ifdef IS_PIXEL_SHADER
#if defined(_ENTRY_POINT_PS_SkyBox) && !defined(_ENTRY_POINT_PS_SkyBox_ATTACHMENTS)
#define _ENTRY_POINT_PS_SkyBox_ATTACHMENTS
layout(location = 0) out vec4 outColor;
#endif // _ENTRY_POINT_PS_SkyBox
#endif // IS_PIXEL_SHADER
#include "SmokeBubble.glsl"

#ifdef IS_COMP_SHADER
#endif // IS_COMP_SHADER


#ifdef IS_VERTEX_SHADER
#ifdef _ENTRY_POINT_VS_SkyBox
layout(location = 0) out VertexOutput _VERTEX_OUTPUT;
void main() { _VERTEX_OUTPUT = VS_SkyBox(); }
#endif // _ENTRY_POINT_VS_SkyBox
#endif // IS_VERTEX_SHADER


#ifdef IS_PIXEL_SHADER
#if defined(_ENTRY_POINT_PS_SkyBox) && !defined(_ENTRY_POINT_PS_SkyBox_INTERPOLANTS)
#define _ENTRY_POINT_PS_SkyBox_INTERPOLANTS
layout(location = 0) in VertexOutput _VERTEX_INPUT;
void main() { PS_SkyBox(_VERTEX_INPUT); }
#endif // _ENTRY_POINT_PS_SkyBox
#endif // IS_PIXEL_SHADER
