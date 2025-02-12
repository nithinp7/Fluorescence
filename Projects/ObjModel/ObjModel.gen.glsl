#version 460 core

#define SCREEN_WIDTH 1440
#define SCREEN_HEIGHT 1280

layout(set=1,binding=1) uniform sampler2D HeadBumpTexture;
layout(set=1,binding=2) uniform sampler2D HeadLambertianTexture;
#include <Fluorescence.glsl>

layout(set=1, binding=3) uniform _CameraUniforms { PerspectiveCamera camera; };

#include "ObjModel.glsl"

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
