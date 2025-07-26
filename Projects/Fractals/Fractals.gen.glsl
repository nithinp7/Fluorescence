#version 460 core

#define SCREEN_WIDTH 1440
#define SCREEN_HEIGHT 1280
#define IMAGE_SIZE_X 1440
#define IMAGE_SIZE_Y 1280
#define IMAGE_PIXEL_COUNT 1843200
#define MIN_ZOOM 0.500000

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

struct GlobalState {
  vec2 pan;
  float zoom;
  float padding;
};

layout(set=1,binding=1) buffer BUFFER_globalStateBuffer {  GlobalState globalStateBuffer[]; };

layout(set=1, binding=2) uniform _UserUniforms {
	float TEST_SLIDER;
};

#include <FlrLib/Fluorescence.glsl>



#ifdef IS_PIXEL_SHADER
#if defined(_ENTRY_POINT_PS_FractalDisplay) && !defined(_ENTRY_POINT_PS_FractalDisplay_ATTACHMENTS)
#define _ENTRY_POINT_PS_FractalDisplay_ATTACHMENTS
layout(location = 0) out vec4 outColor;
#endif // _ENTRY_POINT_PS_FractalDisplay
#endif // IS_PIXEL_SHADER
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
#if defined(_ENTRY_POINT_PS_FractalDisplay) && !defined(_ENTRY_POINT_PS_FractalDisplay_INTERPOLANTS)
#define _ENTRY_POINT_PS_FractalDisplay_INTERPOLANTS
void main() { PS_FractalDisplay(); }
#endif // _ENTRY_POINT_PS_FractalDisplay
#endif // IS_PIXEL_SHADER
