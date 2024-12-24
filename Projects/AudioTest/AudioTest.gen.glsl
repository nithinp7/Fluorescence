#version 460 core

#define SCREEN_WIDTH 1440
#define SCREEN_HEIGHT 1280
#define SAMPLE_CIRCLE_VERTS 48

#include <Fluorescence.glsl>

layout(set=1, binding=1) uniform _AudioUniforms { AudioInput audio; };

#include "AudioTest.glsl"

#ifdef IS_COMP_SHADER
#endif // IS_COMP_SHADER


#ifdef IS_VERTEX_SHADER
#ifdef _ENTRY_POINT_VS_Test
void main() { VS_Test(); }
#endif // _ENTRY_POINT_VS_Test
#ifdef _ENTRY_POINT_VS_SamplePlot
void main() { VS_SamplePlot(); }
#endif // _ENTRY_POINT_VS_SamplePlot
#endif // IS_VERTEX_SHADER


#ifdef IS_PIXEL_SHADER
#ifdef _ENTRY_POINT_PS_Test
void main() { PS_Test(); }
#endif // _ENTRY_POINT_PS_Test
#ifdef _ENTRY_POINT_PS_SamplePlot
void main() { PS_SamplePlot(); }
#endif // _ENTRY_POINT_PS_SamplePlot
#endif // IS_PIXEL_SHADER
