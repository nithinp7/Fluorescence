#version 460 core

#define SCREEN_WIDTH 1440
#define SCREEN_HEIGHT 1280
#define GRID_DIM_X 100
#define GRID_DIM_Y 100
#define GRID_DIM_Z 100
#define GRID_CELL_COUNT 1000000

struct GridCell {
  uvec4 packedValues[4];
};

struct GlobalState {
  uint accumulationFrames;
};

layout(set=1,binding=1) buffer BUFFER_cellBuffer {  GridCell cellBuffer[]; };
layout(set=1,binding=2) buffer BUFFER_globalStateBuffer {  GlobalState globalStateBuffer[]; };

layout(set=1, binding=3) uniform _UserUniforms {
	uint MAX_ITERS;
	uint RENDER_MODE;
	float FREQ;
	float AMPL;
	float OFFS;
	float STEP_SIZE;
};

#include <Fluorescence.glsl>

layout(set=1, binding=4) uniform _CameraUniforms { PerspectiveCamera camera; };

#include "Voxels.glsl"

#ifdef IS_COMP_SHADER
#ifdef _ENTRY_POINT_CS_Tick
layout(local_size_x = 1, local_size_y = 1, local_size_z = 1) in;
void main() { CS_Tick(); }
#endif // _ENTRY_POINT_CS_Tick
#ifdef _ENTRY_POINT_CS_UpdateVoxels
layout(local_size_x = 8, local_size_y = 8, local_size_z = 8) in;
void main() { CS_UpdateVoxels(); }
#endif // _ENTRY_POINT_CS_UpdateVoxels
#endif // IS_COMP_SHADER


#ifdef IS_VERTEX_SHADER
#ifdef _ENTRY_POINT_VS_RayMarchVoxels
void main() { VS_RayMarchVoxels(); }
#endif // _ENTRY_POINT_VS_RayMarchVoxels
#endif // IS_VERTEX_SHADER


#ifdef IS_PIXEL_SHADER
#ifdef _ENTRY_POINT_PS_RayMarchVoxels
void main() { PS_RayMarchVoxels(); }
#endif // _ENTRY_POINT_PS_RayMarchVoxels
#endif // IS_PIXEL_SHADER
