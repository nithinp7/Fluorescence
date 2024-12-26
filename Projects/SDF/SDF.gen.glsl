#version 460 core

#define SCREEN_WIDTH 1440
#define SCREEN_HEIGHT 1280

struct Pixel {
  vec4 accumulated;
};


layout(set=1, binding=1) uniform _UserUniforms {
	uint MAX_ITERS;
	uint RENDER_MODE;
	float ROUGHNESS;
	float SLIDER_A;
	float SLIDER_B;
	float SLIDER_C;
	bool COLOR_REMAP;
};

#include <Fluorescence.glsl>

layout(set=1, binding=2) uniform _CameraUniforms { PerspectiveCamera camera; };

#include "SDF.glsl"

#ifdef IS_COMP_SHADER
#endif // IS_COMP_SHADER


#ifdef IS_VERTEX_SHADER
#ifdef _ENTRY_POINT_VS_SDF
void main() { VS_SDF(); }
#endif // _ENTRY_POINT_VS_SDF
#endif // IS_VERTEX_SHADER


#ifdef IS_PIXEL_SHADER
#ifdef _ENTRY_POINT_PS_SDF
void main() { PS_SDF(); }
#endif // _ENTRY_POINT_PS_SDF
#endif // IS_PIXEL_SHADER
