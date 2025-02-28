#version 460 core

#define SCREEN_WIDTH 1440
#define SCREEN_HEIGHT 1280

struct VertexOutput {
  vec2 uv;
};;

layout(set=1,binding=1, rgba8) uniform image2D SaveImage;
layout(set=1,binding=2) uniform sampler2D HeadBumpTexture;
layout(set=1,binding=3) uniform sampler2D HeadLambertianTexture;

layout(set=1, binding=4) uniform _UserUniforms {
	uint MODE;
	float SLICE;
	float SCALE;
	float PAN_X;
	float PAN_Y;
	float ZOOM;
	float CURVATURE_RADIUS;
	bool FIX_UV;
};

#include <Fluorescence.glsl>



#ifdef IS_PIXEL_SHADER
#ifdef _ENTRY_POINT_PS_DrawMap
layout(location = 0) out vec4 outDisplay;
#endif // _ENTRY_POINT_PS_DrawMap
#ifdef _ENTRY_POINT_PS_SaveMap
layout(location = 0) out vec4 outSave;
#endif // _ENTRY_POINT_PS_SaveMap
#endif // IS_PIXEL_SHADER
#include "SkinMaps.glsl"

#ifdef IS_COMP_SHADER
#endif // IS_COMP_SHADER


#ifdef IS_VERTEX_SHADER
#ifdef _ENTRY_POINT_VS_DrawMap
layout(location = 0) out VertexOutput _VERTEX_OUTPUT;
void main() { _VERTEX_OUTPUT = VS_DrawMap(); }
#endif // _ENTRY_POINT_VS_DrawMap
#ifdef _ENTRY_POINT_VS_SaveMap
layout(location = 0) out VertexOutput _VERTEX_OUTPUT;
void main() { _VERTEX_OUTPUT = VS_SaveMap(); }
#endif // _ENTRY_POINT_VS_SaveMap
#endif // IS_VERTEX_SHADER


#ifdef IS_PIXEL_SHADER
#ifdef _ENTRY_POINT_PS_DrawMap
layout(location = 0) in VertexOutput _VERTEX_INPUT;
void main() { PS_DrawMap(_VERTEX_INPUT); }
#endif // _ENTRY_POINT_PS_DrawMap
#ifdef _ENTRY_POINT_PS_SaveMap
layout(location = 0) in VertexOutput _VERTEX_INPUT;
void main() { PS_SaveMap(_VERTEX_INPUT); }
#endif // _ENTRY_POINT_PS_SaveMap
#endif // IS_PIXEL_SHADER
