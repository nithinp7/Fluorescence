#version 460 core

#define SCREEN_WIDTH 1440
#define SCREEN_HEIGHT 1280

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
  uint accumulationFrames;
};

layout(set=1,binding=1) buffer BUFFER_globalStateBuffer {  GlobalState globalStateBuffer[]; };
layout(set=1,binding=2, rgba8) uniform image2D accumulationBuffer;
layout(set=1,binding=3) uniform sampler2D accumulationTexture;

layout(set=1, binding=4) uniform _UserUniforms {
	uint MAX_ITERS;
	uint RENDER_MODE;
	float ROUGHNESS;
	float SLIDER_A;
	float SLIDER_B;
	float SLIDER_C;
	bool COLOR_REMAP;
};

#include <FlrLib/Fluorescence.glsl>

layout(set=1, binding=5) uniform _CameraUniforms { PerspectiveCamera camera; };



#ifdef IS_PIXEL_SHADER
#if defined(_ENTRY_POINT_PS_SDF) && !defined(_ENTRY_POINT_PS_SDF_ATTACHMENTS)
#define _ENTRY_POINT_PS_SDF_ATTACHMENTS
layout(location = 0) out vec4 outColor;
#endif // _ENTRY_POINT_PS_SDF
#endif // IS_PIXEL_SHADER
#include "SDF_Emissive.glsl"

#ifdef IS_COMP_SHADER
#ifdef _ENTRY_POINT_CS_Tick
layout(local_size_x = 1, local_size_y = 1, local_size_z = 1) in;
void main() { CS_Tick(); }
#endif // _ENTRY_POINT_CS_Tick
#ifdef _ENTRY_POINT_CS_PathTrace
layout(local_size_x = 32, local_size_y = 32, local_size_z = 1) in;
void main() { CS_PathTrace(); }
#endif // _ENTRY_POINT_CS_PathTrace
#endif // IS_COMP_SHADER


#ifdef IS_VERTEX_SHADER
#ifdef _ENTRY_POINT_VS_SDF
void main() { VS_SDF(); }
#endif // _ENTRY_POINT_VS_SDF
#endif // IS_VERTEX_SHADER


#ifdef IS_PIXEL_SHADER
#if defined(_ENTRY_POINT_PS_SDF) && !defined(_ENTRY_POINT_PS_SDF_INTERPOLANTS)
#define _ENTRY_POINT_PS_SDF_INTERPOLANTS
void main() { PS_SDF(); }
#endif // _ENTRY_POINT_PS_SDF
#endif // IS_PIXEL_SHADER
