#version 460 core

#define SCREEN_WIDTH 1440
#define SCREEN_HEIGHT 1280

#include <Fluorescence.glsl>

layout(set=1, binding=1) uniform _CameraUniforms { PerspectiveCamera camera; };

#include "ObjModel.glsl"

#ifdef IS_COMP_SHADER
#endif // IS_COMP_SHADER


#ifdef IS_VERTEX_SHADER
#ifdef _ENTRY_POINT_VS_Obj
void main() { VS_Obj(); }
#endif // _ENTRY_POINT_VS_Obj
#endif // IS_VERTEX_SHADER


#ifdef IS_PIXEL_SHADER
#ifdef _ENTRY_POINT_PS_Obj
void main() { PS_Obj(); }
#endif // _ENTRY_POINT_PS_Obj
#endif // IS_PIXEL_SHADER
