#version 460 core

#define SCREEN_WIDTH 1440
#define SCREEN_HEIGHT 1280

layout(set=1,binding=1) uniform sampler2D HeadBumpTexture;
layout(set=1,binding=2) uniform sampler2D HeadLambertianTexture;

layout(set=1, binding=3) uniform _UserUniforms {
	uint BRDF_MODE;
	uint BACKGROUND;
	uint RENDER_MODE;
	uint SAMPLE_COUNT;
	float EPI_DEPTH;
	float IOR_EPI;
	float IOR_DERM;
	float EPI_ABS_RED;
	float EPI_ABS_GREEN;
	float EPI_ABS_BLUE;
	float HEMOGLOBIN_SCALE;
	float BUMP_STRENGTH;
	float ROUGHNESS;
	float METALLIC;
	float LIGHT_THETA;
	float LIGHT_PHI;
	float LIGHT_STRENGTH;
	bool ENABLE_SSS;
	bool ENABLE_REFL;
};

#include <Fluorescence.glsl>

layout(set=1, binding=4) uniform _CameraUniforms { PerspectiveCamera camera; };

#include "Skin.glsl"

#ifdef IS_COMP_SHADER
#endif // IS_COMP_SHADER


#ifdef IS_VERTEX_SHADER
#ifdef _ENTRY_POINT_VS_Background
void main() { VS_Background(); }
#endif // _ENTRY_POINT_VS_Background
#ifdef _ENTRY_POINT_VS_Obj
void main() { VS_Obj(); }
#endif // _ENTRY_POINT_VS_Obj
#endif // IS_VERTEX_SHADER


#ifdef IS_PIXEL_SHADER
#ifdef _ENTRY_POINT_PS_Background
void main() { PS_Background(); }
#endif // _ENTRY_POINT_PS_Background
#ifdef _ENTRY_POINT_PS_Obj
void main() { PS_Obj(); }
#endif // _ENTRY_POINT_PS_Obj
#endif // IS_PIXEL_SHADER
