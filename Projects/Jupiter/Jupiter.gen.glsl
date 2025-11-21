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
	vec4 COLOR0;
	vec4 COLOR1;
	vec4 COLOR2;
	vec4 COLOR3;
	float ETA;
	float TURB_AMP;
	float TURB_FREQ;
	float TURB_SPEED;
	float TURB_ROT;
	float TURB_EXP;
	float RM_0;
	float RM_1;
	float EXPOSURE;
	float COLOR0_FALLOFF;
	float COLOR0_INT;
	float COLOR1_FALLOFF;
	float COLOR1_INT;
	float COLOR2_FALLOFF;
	float COLOR2_INT;
	float COLOR3_FALLOFF;
	float COLOR3_INT;
	bool APPLY_TURBULENCE;
};

#include <FlrLib/Fluorescence.glsl>

layout(set=1, binding=2) uniform _CameraUniforms { PerspectiveCamera camera; };



#ifdef IS_PIXEL_SHADER
#if defined(_ENTRY_POINT_PS_Jupiter) && !defined(_ENTRY_POINT_PS_Jupiter_ATTACHMENTS)
#define _ENTRY_POINT_PS_Jupiter_ATTACHMENTS
layout(location = 0) out vec4 outColor;
#endif // _ENTRY_POINT_PS_Jupiter
#endif // IS_PIXEL_SHADER
#include "Jupiter.glsl"

#ifdef IS_COMP_SHADER
#endif // IS_COMP_SHADER


#ifdef IS_VERTEX_SHADER
#ifdef _ENTRY_POINT_VS_Jupiter
layout(location = 0) out VertexOutput _VERTEX_OUTPUT;
void main() { _VERTEX_OUTPUT = VS_Jupiter(); }
#endif // _ENTRY_POINT_VS_Jupiter
#endif // IS_VERTEX_SHADER


#ifdef IS_PIXEL_SHADER
#if defined(_ENTRY_POINT_PS_Jupiter) && !defined(_ENTRY_POINT_PS_Jupiter_INTERPOLANTS)
#define _ENTRY_POINT_PS_Jupiter_INTERPOLANTS
layout(location = 0) in VertexOutput _VERTEX_INPUT;
void main() { PS_Jupiter(_VERTEX_INPUT); }
#endif // _ENTRY_POINT_PS_Jupiter
#endif // IS_PIXEL_SHADER
