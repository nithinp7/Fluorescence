#version 460 core

#define SCREEN_WIDTH 1440
#define SCREEN_HEIGHT 1280

struct VertexOutput {
  vec2 uv;
};;

layout(set=1,binding=1, rgba8) uniform image2D SaveImage;

layout(set=1, binding=2) uniform _UserUniforms {
	uint MODE;
	float RED_0;
	float RED_1;
	float BLUE_0;
	float BLUE_1;
	float GREEN_0;
	float GREEN_1;
};

#include <Fluorescence.glsl>



#ifdef IS_PIXEL_SHADER
#ifdef _ENTRY_POINT_PS_DrawProfile
layout(location = 0) out vec4 outDisplay;
layout(location = 1) out vec4 outSave;
#endif // _ENTRY_POINT_PS_DrawProfile
#endif // IS_PIXEL_SHADER
#include "DiffusionProfiles.glsl"

#ifdef IS_COMP_SHADER
#endif // IS_COMP_SHADER


#ifdef IS_VERTEX_SHADER
#ifdef _ENTRY_POINT_VS_DrawProfile
layout(location = 0) out VertexOutput _VERTEX_OUTPUT;
void main() { _VERTEX_OUTPUT = VS_DrawProfile(); }
#endif // _ENTRY_POINT_VS_DrawProfile
#endif // IS_VERTEX_SHADER


#ifdef IS_PIXEL_SHADER
#ifdef _ENTRY_POINT_PS_DrawProfile
layout(location = 0) in VertexOutput _VERTEX_INPUT;
void main() { PS_DrawProfile(_VERTEX_INPUT); }
#endif // _ENTRY_POINT_PS_DrawProfile
#endif // IS_PIXEL_SHADER
