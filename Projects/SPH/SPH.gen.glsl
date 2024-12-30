#version 460 core

#define SCREEN_WIDTH 1440
#define SCREEN_HEIGHT 1280
#define PARTICLE_COUNT 10000
#define HALF_PARTICLE_COUNT 5000
#define DOUBLE_PARTICLE_COUNT 20000
#define TILE_COUNT_X 100
#define TILE_COUNT_Y 100
#define TILE_COUNT 10000
#define DOUBLE_TILE_COUNT 20000
#define PARTICLE_CIRCLE_VERTS 48
#define DELTA_TIME 0.033330
#define PARTICLE_RADIUS 0.005000

struct Uint { uint u; };

struct Tile {
  uint packedOffsetCount;
};

struct GlobalState {
  uint tileEntryAllocator;
  uint activeTileCount;
  uint bInitialized;
  uint bPhase;
};

layout(set=1,binding=1) buffer BUFFER_packedPositions {  Uint packedPositions[]; };
layout(set=1,binding=2) buffer BUFFER_packedVelocities {  Uint packedVelocities[]; };
layout(set=1,binding=3) buffer BUFFER_particleAddresses {  Uint particleAddresses[]; };
layout(set=1,binding=4) buffer BUFFER_packedDensityPressure {  Uint packedDensityPressure[]; };
layout(set=1,binding=5) buffer BUFFER_tilesBuffer {  Tile tilesBuffer[]; };
layout(set=1,binding=6) buffer BUFFER_reducedTilesBuffer {  Uint reducedTilesBuffer[]; };
layout(set=1,binding=7) buffer BUFFER_globalStateBuffer {  GlobalState globalStateBuffer[]; };

layout(set=1, binding=8) uniform _UserUniforms {
	uint DISPLAY_MODE;
	float DAMPING;
	float GRAVITY;
	float PARTICLE_MASS;
	float WAVES;
	float DISPLAY_RADIUS;
	float EOS_SOLVER_STIFFNESS;
	float EOS_SOLVER_COMPRESSIBILITY;
	float EOS_SOLVER_REST_DENSITY;
};

#include <Fluorescence.glsl>

#include "SPH.glsl"

#ifdef IS_COMP_SHADER
#ifdef _ENTRY_POINT_CS_Tick
layout(local_size_x = 1, local_size_y = 1, local_size_z = 1) in;
void main() { CS_Tick(); }
#endif // _ENTRY_POINT_CS_Tick
#ifdef _ENTRY_POINT_CS_ClearTiles
layout(local_size_x = 32, local_size_y = 1, local_size_z = 1) in;
void main() { CS_ClearTiles(); }
#endif // _ENTRY_POINT_CS_ClearTiles
#ifdef _ENTRY_POINT_CS_AdvectParticles_Reserve
layout(local_size_x = 32, local_size_y = 1, local_size_z = 1) in;
void main() { CS_AdvectParticles_Reserve(); }
#endif // _ENTRY_POINT_CS_AdvectParticles_Reserve
#ifdef _ENTRY_POINT_CS_AllocateTiles
layout(local_size_x = 32, local_size_y = 1, local_size_z = 1) in;
void main() { CS_AllocateTiles(); }
#endif // _ENTRY_POINT_CS_AllocateTiles
#ifdef _ENTRY_POINT_CS_AdvectParticles_Insert
layout(local_size_x = 32, local_size_y = 1, local_size_z = 1) in;
void main() { CS_AdvectParticles_Insert(); }
#endif // _ENTRY_POINT_CS_AdvectParticles_Insert
#ifdef _ENTRY_POINT_CS_ComputePressures
layout(local_size_x = 32, local_size_y = 1, local_size_z = 1) in;
void main() { CS_ComputePressures(); }
#endif // _ENTRY_POINT_CS_ComputePressures
#ifdef _ENTRY_POINT_CS_UpdateVelocities
layout(local_size_x = 32, local_size_y = 1, local_size_z = 1) in;
void main() { CS_UpdateVelocities(); }
#endif // _ENTRY_POINT_CS_UpdateVelocities
#endif // IS_COMP_SHADER


#ifdef IS_VERTEX_SHADER
#ifdef _ENTRY_POINT_VS_Tiles
void main() { VS_Tiles(); }
#endif // _ENTRY_POINT_VS_Tiles
#ifdef _ENTRY_POINT_VS_Particles
void main() { VS_Particles(); }
#endif // _ENTRY_POINT_VS_Particles
#endif // IS_VERTEX_SHADER


#ifdef IS_PIXEL_SHADER
#ifdef _ENTRY_POINT_PS_TilesDensity
void main() { PS_TilesDensity(); }
#endif // _ENTRY_POINT_PS_TilesDensity
#ifdef _ENTRY_POINT_PS_Particles
void main() { PS_Particles(); }
#endif // _ENTRY_POINT_PS_Particles
#endif // IS_PIXEL_SHADER
