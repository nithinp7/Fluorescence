#version 460 core

#define SCREEN_WIDTH 1440
#define SCREEN_HEIGHT 1280

struct VertexOutput {
  vec4 worldPosition;
  vec4 position;
  vec4 prevPosition;
  vec3 normal;
  vec2 uv;
};;

layout(set=1,binding=1, r32f) uniform image2D PrevDepthImage;
layout(set=1,binding=2, rgba32f) uniform image2D PrevIrradianceImage;
layout(set=1,binding=3, rgba32f) uniform image2D IrradianceImage;
layout(set=1,binding=4, r32f) uniform image2D MiscBuffer;
layout(set=1,binding=5, r32f) uniform image2D PrevMiscBuffer;
layout(set=1,binding=6, rgba8) uniform image2D DebugImage;
layout(set=1,binding=7) uniform sampler2D HeadBumpTexture;
layout(set=1,binding=8) uniform sampler2D HeadLambertianTexture;
layout(set=1,binding=9) uniform sampler2D DiffusionProfileTexture;
layout(set=1,binding=10) uniform sampler2D HeadSpecTexture;
layout(set=1,binding=11) uniform sampler2D EnvironmentMap;
layout(set=1,binding=12) uniform sampler2D DepthTexture;
layout(set=1,binding=13) uniform sampler2D PrevDepthTexture;
layout(set=1,binding=14) uniform sampler2D PrevIrradianceTexture;
layout(set=1,binding=15) uniform sampler2D IrradianceTexture;
layout(set=1,binding=16) uniform sampler2D MiscTexture;
layout(set=1,binding=17) uniform sampler2D PrevMiscTexture;
layout(set=1,binding=18) uniform sampler2D DebugTexture;

layout(set=1, binding=19) uniform _UserUniforms {
	vec4 HEMOGLOBIN_COLOR;
	vec4 EPI_ABS_COLOR;
	uint SHADOW_STEPS;
	uint SAMPLE_COUNT;
	uint BACKGROUND;
	uint RENDER_MODE;
	float RED_0;
	float RED_1;
	float BLUE_0;
	float BLUE_1;
	float GREEN_0;
	float GREEN_1;
	float SHADOW_DT;
	float SHADOW_BIAS;
	float SHADOW_THRESHOLD;
	float SSS_RADIUS;
	float TSR_SPEED;
	float REPROJ_TOLERANCE;
	float IOR;
	float HEMOGLOBIN_SCALE;
	float EPI_DEPTH;
	float LIGHT_THETA;
	float LIGHT_PHI;
	float LIGHT_STRENGTH;
	float LIGHT_COVERAGE;
	float BUMP_STRENGTH;
	float ROUGHNESS;
	float METALLIC;
	bool SHOW_PROFILE;
	bool ENABLE_SHADOWS;
	bool ENABLE_REFL;
	bool ENABLE_REFL_EPI;
	bool ENABLE_SSS_EPI;
	bool ENABLE_SSS_DER;
	bool ENABLE_SEE_THROUGH;
};

#include <Fluorescence.glsl>

layout(set=1, binding=20) uniform _CameraUniforms { PerspectiveCamera camera; };



#ifdef IS_PIXEL_SHADER
#ifdef _ENTRY_POINT_PS_SkinIrr
layout(location = 0) out vec4 outIrradiance;
layout(location = 1) out vec4 outDebug;
layout(location = 2) out vec4 outMisc;
#endif // _ENTRY_POINT_PS_SkinIrr
#ifdef _ENTRY_POINT_PS_SkinResolve
layout(location = 0) out vec4 outDisplay;
#endif // _ENTRY_POINT_PS_SkinResolve
#endif // IS_PIXEL_SHADER
#include "Skin.glsl"

#ifdef IS_COMP_SHADER
#ifdef _ENTRY_POINT_CS_CopyPrevBuffers
layout(local_size_x = 32, local_size_y = 32, local_size_z = 1) in;
void main() { CS_CopyPrevBuffers(); }
#endif // _ENTRY_POINT_CS_CopyPrevBuffers
#endif // IS_COMP_SHADER


#ifdef IS_VERTEX_SHADER
#ifdef _ENTRY_POINT_VS_SkinIrr
layout(location = 0) out VertexOutput _VERTEX_OUTPUT;
void main() { _VERTEX_OUTPUT = VS_SkinIrr(); }
#endif // _ENTRY_POINT_VS_SkinIrr
#ifdef _ENTRY_POINT_VS_SkinResolve
layout(location = 0) out VertexOutput _VERTEX_OUTPUT;
void main() { _VERTEX_OUTPUT = VS_SkinResolve(); }
#endif // _ENTRY_POINT_VS_SkinResolve
#endif // IS_VERTEX_SHADER


#ifdef IS_PIXEL_SHADER
#ifdef _ENTRY_POINT_PS_SkinIrr
layout(location = 0) in VertexOutput _VERTEX_INPUT;
void main() { PS_SkinIrr(_VERTEX_INPUT); }
#endif // _ENTRY_POINT_PS_SkinIrr
#ifdef _ENTRY_POINT_PS_SkinResolve
layout(location = 0) in VertexOutput _VERTEX_INPUT;
void main() { PS_SkinResolve(_VERTEX_INPUT); }
#endif // _ENTRY_POINT_PS_SkinResolve
#endif // IS_PIXEL_SHADER
