#version 460 core

#define SCREEN_WIDTH 1440
#define SCREEN_HEIGHT 1280

struct GlobalState {
  uint accumulationFrames;
};

layout(set=1,binding=1) buffer BUFFER_globalStateBuffer {  GlobalState globalStateBuffer[]; };
layout(set=1,binding=2, rgba8) uniform image2D accumulationBuffer;
layout(set=1,binding=3) uniform sampler2D accumulationTexture;

layout(set=1, binding=4) uniform _UserUniforms {
	uint BOUNCES;
	uint MAX_ITERS;
	uint RENDER_MODE;
	float DENSITY_SCALE;
	float SUN_LIGHT_SCALE;
	float ATM_SIZE_SCALE;
	float RED;
	float GREEN;
	float BLUE;
	float TIME_OF_DAY;
	float ROUGHNESS;
	float SLIDER_A;
	float SLIDER_B;
	float SLIDER_C;
	bool ACCUMULATE;
	bool COLOR_REMAP;
};

#include <Fluorescence.glsl>

layout(set=1, binding=5) uniform _CameraUniforms { PerspectiveCamera camera; };

#include "SunSky.glsl"

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
#ifdef _ENTRY_POINT_PS_SDF
void main() { PS_SDF(); }
#endif // _ENTRY_POINT_PS_SDF
#endif // IS_PIXEL_SHADER
