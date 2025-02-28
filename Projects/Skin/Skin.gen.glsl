#version 460 core

#define SCREEN_WIDTH 2560
#define SCREEN_HEIGHT 1334

struct VertexOutput {
  vec4 position;
  vec4 prevPosition;
  vec3 normal;
  vec2 uv;
};;

layout(set=1,binding=1, rgba32f) uniform image2D DisplayImage;
layout(set=1,binding=2, rgba32f) uniform image2D PrevDisplayImage;
layout(set=1,binding=3, r32f) uniform image2D PrevDepthImage;
layout(set=1,binding=4) uniform sampler2D HeadBumpTexture;
layout(set=1,binding=5) uniform sampler2D HeadLambertianTexture;
layout(set=1,binding=6) uniform sampler2D DiffusionProfileTexture;
layout(set=1,binding=7) uniform sampler2D HeadSpecTexture;
layout(set=1,binding=8) uniform sampler2D DisplayTexture;
layout(set=1,binding=9) uniform sampler2D PrevDisplayTexture;
layout(set=1,binding=10) uniform sampler2D DepthTexture;
layout(set=1,binding=11) uniform sampler2D PrevDepthTexture;

layout(set=1, binding=12) uniform _UserUniforms {
	vec4 HEMOGLOBIN_COLOR;
	vec4 EPI_ABS_COLOR;
	uint SAMPLE_COUNT;
	uint BACKGROUND;
	uint RENDER_MODE;
	float SSS_RADIUS;
	float TSR_SPEED;
	float REPROJ_TOLERANCE;
	float IOR;
	float HEMOGLOBIN_SCALE;
	float EPI_DEPTH;
	float BUMP_STRENGTH;
	float ROUGHNESS;
	float METALLIC;
	float LIGHT_THETA;
	float LIGHT_PHI;
	float LIGHT_STRENGTH;
	bool ENABLE_REFL;
	bool ENABLE_REFL_EPI;
	bool ENABLE_SSS_EPI;
	bool ENABLE_SSS_DER;
	bool ENABLE_SEE_THROUGH;
};

#include <Fluorescence.glsl>

layout(set=1, binding=13) uniform _CameraUniforms { PerspectiveCamera camera; };



#ifdef IS_PIXEL_SHADER
#ifdef _ENTRY_POINT_PS_Background
layout(location = 0) out vec4 outDisplay;
layout(location = 1) out vec4 outColor;
#endif // _ENTRY_POINT_PS_Background
#ifdef _ENTRY_POINT_PS_Obj
layout(location = 0) out vec4 outDisplay;
layout(location = 1) out vec4 outColor;
#endif // _ENTRY_POINT_PS_Obj
#endif // IS_PIXEL_SHADER
#include "Skin.glsl"

#ifdef IS_COMP_SHADER
#ifdef _ENTRY_POINT_CS_CopyDisplayImage
layout(local_size_x = 32, local_size_y = 32, local_size_z = 1) in;
void main() { CS_CopyDisplayImage(); }
#endif // _ENTRY_POINT_CS_CopyDisplayImage
#endif // IS_COMP_SHADER


#ifdef IS_VERTEX_SHADER
#ifdef _ENTRY_POINT_VS_Background
layout(location = 0) out VertexOutput _VERTEX_OUTPUT;
void main() { _VERTEX_OUTPUT = VS_Background(); }
#endif // _ENTRY_POINT_VS_Background
#ifdef _ENTRY_POINT_VS_Obj
layout(location = 0) out VertexOutput _VERTEX_OUTPUT;
void main() { _VERTEX_OUTPUT = VS_Obj(); }
#endif // _ENTRY_POINT_VS_Obj
#endif // IS_VERTEX_SHADER


#ifdef IS_PIXEL_SHADER
#ifdef _ENTRY_POINT_PS_Background
layout(location = 0) in VertexOutput _VERTEX_INPUT;
void main() { PS_Background(_VERTEX_INPUT); }
#endif // _ENTRY_POINT_PS_Background
#ifdef _ENTRY_POINT_PS_Obj
layout(location = 0) in VertexOutput _VERTEX_INPUT;
void main() { PS_Obj(_VERTEX_INPUT); }
#endif // _ENTRY_POINT_PS_Obj
#endif // IS_PIXEL_SHADER
