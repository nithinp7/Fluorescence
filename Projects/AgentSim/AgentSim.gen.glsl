#version 460 core

#define MAX_AGENTS_PER_SHAPE 32
#define agentCount 12000
#define TILE_COUNT_X 16
#define TILE_COUNT_Y 16
#define TILE_COUNT 256
#define CIRCLE_VERTS 48
#define MAX_SHAPE_COUNT 256
#define SCREEN_WIDTH 1440
#define SCREEN_HEIGHT 1280
#define DELTA_TIME 0.010000
#define RADIUS 0.002000
#define GRAVITY 0.000000
#define PADDING 0.000000

struct GlobalState {
  uint initialized;
  uint shapeCount;
};

struct Agent {
  uint next;
  uint shape;
};

struct Tile {
  uint head;
  uint count;
};

struct Position {
  vec2 pos;
};

struct ShapeConstraint {
  vec2 restPose;
  uint idx;
  uint extra;
};

struct Shape {
  ShapeConstraint agents[MAX_AGENTS_PER_SHAPE]; 
  uint count;
  uint padding;
};

layout(set=1,binding=1) buffer BUFFER_shapeBuffer {  Shape shapeBuffer[]; };
layout(set=1,binding=2) buffer BUFFER_posBuffer {  Position posBuffer[]; };
layout(set=1,binding=3) buffer BUFFER_prevPosBuffer {  Position prevPosBuffer[]; };
layout(set=1,binding=4) buffer BUFFER_globalStateBuffer {  GlobalState globalStateBuffer[]; };
layout(set=1,binding=5) buffer BUFFER_tilesBuffer {  Tile tilesBuffer[]; };
layout(set=1,binding=6) buffer BUFFER_agentBuffer {  Agent agentBuffer[]; };
#include <Fluorescence.glsl>
#include "AgentSim.glsl"

#ifdef IS_COMP_SHADER
#ifdef _ENTRY_POINT_CS_ClearTiles
layout(local_size_x = 16, local_size_y = 16, local_size_z = 1) in;
void main() { CS_ClearTiles(); }
#endif // _ENTRY_POINT_CS_ClearTiles
#ifdef _ENTRY_POINT_CS_WriteAgentsToTiles
layout(local_size_x = 32, local_size_y = 1, local_size_z = 1) in;
void main() { CS_WriteAgentsToTiles(); }
#endif // _ENTRY_POINT_CS_WriteAgentsToTiles
#ifdef _ENTRY_POINT_CS_Init
layout(local_size_x = 1, local_size_y = 1, local_size_z = 1) in;
void main() { CS_Init(); }
#endif // _ENTRY_POINT_CS_Init
#ifdef _ENTRY_POINT_CS_TimeStepAgents
layout(local_size_x = 32, local_size_y = 1, local_size_z = 1) in;
void main() { CS_TimeStepAgents(); }
#endif // _ENTRY_POINT_CS_TimeStepAgents
#ifdef _ENTRY_POINT_CS_MoveAgents
layout(local_size_x = 32, local_size_y = 1, local_size_z = 1) in;
void main() { CS_MoveAgents(); }
#endif // _ENTRY_POINT_CS_MoveAgents
#ifdef _ENTRY_POINT_CS_CreateShapes
layout(local_size_x = 1, local_size_y = 1, local_size_z = 1) in;
void main() { CS_CreateShapes(); }
#endif // _ENTRY_POINT_CS_CreateShapes
#ifdef _ENTRY_POINT_CS_SolveShapes
layout(local_size_x = 32, local_size_y = 1, local_size_z = 1) in;
void main() { CS_SolveShapes(); }
#endif // _ENTRY_POINT_CS_SolveShapes
#endif // IS_COMP_SHADER


#ifdef IS_VERTEX_SHADER
#ifdef _ENTRY_POINT_VS_AgentSimDisplay
void main() { VS_AgentSimDisplay(); }
#endif // _ENTRY_POINT_VS_AgentSimDisplay
#ifdef _ENTRY_POINT_VS_Circle
void main() { VS_Circle(); }
#endif // _ENTRY_POINT_VS_Circle
#endif // IS_VERTEX_SHADER


#ifdef IS_PIXEL_SHADER
#ifdef _ENTRY_POINT_PS_UvTest
void main() { PS_UvTest(); }
#endif // _ENTRY_POINT_PS_UvTest
#ifdef _ENTRY_POINT_PS_Circle
void main() { PS_Circle(); }
#endif // _ENTRY_POINT_PS_Circle
#endif // IS_PIXEL_SHADER
