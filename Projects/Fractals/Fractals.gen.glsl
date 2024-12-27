#version 460 core

#define SCREEN_WIDTH 2560
#define SCREEN_HEIGHT 1334
#define IMAGE_SIZE_X 1440
#define IMAGE_SIZE_Y 1280
#define IMAGE_PIXEL_COUNT 1843200
#define MIN_ZOOM 0.500000

struct GlobalState {
  vec2 pan;
  float zoom;
  float padding;
};

layout(set=1,binding=1) buffer BUFFER_globalStateBuffer {  GlobalState globalStateBuffer[]; };

layout(set=1, binding=2) uniform _UserUniforms {
	float TEST_SLIDER;
};

#include <Fluorescence.glsl>

#include "Fractals.glsl"

#ifdef IS_COMP_SHADER
#ifdef _ENTRY_POINT_CS_HandleInput
layout(local_size_x = 1, local_size_y = 1, local_size_z = 1) in;
void main() { CS_HandleInput(); }
#endif // _ENTRY_POINT_CS_HandleInput
#endif // IS_COMP_SHADER


#ifdef IS_VERTEX_SHADER
#ifdef _ENTRY_POINT_VS_FractalDisplay
void main() { VS_FractalDisplay(); }
#endif // _ENTRY_POINT_VS_FractalDisplay
#endif // IS_VERTEX_SHADER


#ifdef IS_PIXEL_SHADER
#ifdef _ENTRY_POINT_PS_FractalDisplay
void main() { PS_FractalDisplay(); }
#endif // _ENTRY_POINT_PS_FractalDisplay
#endif // IS_PIXEL_SHADER
