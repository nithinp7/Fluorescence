#version 460 core

#define SCREEN_WIDTH 1440
#define SCREEN_HEIGHT 1280
#define SAMPLE_CIRCLE_VERTS 48
#define SAMPLE_COUNT 2048
#define GROUP_SIZE 32
#define DISPATCH_SIZE 32
#define LINE_WIDTH 0.005000

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


layout(set=1, binding=1) uniform _UserUniforms {
	uint MODE;
	float SCALE;
};

#include <FlrLib/Fluorescence.glsl>

layout(set=1, binding=2) uniform _AudioUniforms { AudioInput audio; };



#ifdef IS_PIXEL_SHADER
#if defined(_ENTRY_POINT_PS_Test) && !defined(_ENTRY_POINT_PS_Test_ATTACHMENTS)
#define _ENTRY_POINT_PS_Test_ATTACHMENTS
layout(location = 0) out vec4 outColor;
#endif // _ENTRY_POINT_PS_Test
#if defined(_ENTRY_POINT_PS_SamplePlot) && !defined(_ENTRY_POINT_PS_SamplePlot_ATTACHMENTS)
#define _ENTRY_POINT_PS_SamplePlot_ATTACHMENTS
layout(location = 0) out vec4 outColor;
#endif // _ENTRY_POINT_PS_SamplePlot
#endif // IS_PIXEL_SHADER
#include "AudioTest.glsl"

#ifdef IS_COMP_SHADER
#endif // IS_COMP_SHADER


#ifdef IS_VERTEX_SHADER
#ifdef _ENTRY_POINT_VS_Test
void main() { VS_Test(); }
#endif // _ENTRY_POINT_VS_Test
#ifdef _ENTRY_POINT_VS_FrequencyPlot
void main() { VS_FrequencyPlot(); }
#endif // _ENTRY_POINT_VS_FrequencyPlot
#endif // IS_VERTEX_SHADER


#ifdef IS_PIXEL_SHADER
#if defined(_ENTRY_POINT_PS_Test) && !defined(_ENTRY_POINT_PS_Test_INTERPOLANTS)
#define _ENTRY_POINT_PS_Test_INTERPOLANTS
void main() { PS_Test(); }
#endif // _ENTRY_POINT_PS_Test
#if defined(_ENTRY_POINT_PS_SamplePlot) && !defined(_ENTRY_POINT_PS_SamplePlot_INTERPOLANTS)
#define _ENTRY_POINT_PS_SamplePlot_INTERPOLANTS
void main() { PS_SamplePlot(); }
#endif // _ENTRY_POINT_PS_SamplePlot
#endif // IS_PIXEL_SHADER
