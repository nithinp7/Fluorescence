#version 460 core

#define SCREEN_WIDTH 1440
#define SCREEN_HEIGHT 1280
#define CELLS_X 1440
#define CELLS_Y 1280
#define CELLS_COUNT 1843200
#define HALF_CELLS_COUNT 921600
#define QUARTER_CELLS_COUNT 460800
#define H 0.000694
#define DELTA_TIME 0.033333

struct GlobalState {
  vec2 pan;
  float zoom;
  uint initialized;
};

struct ExtraFields {
  vec4 color; // TODO: turn into id or quantized color
};;

struct Uint { uint u; };

struct Float { float f; };

struct U16x2 { uint packed; };

layout(set=1,binding=1) buffer BUFFER_globalStateBuffer {  GlobalState globalStateBuffer[]; };
layout(set=1,binding=2) buffer BUFFER_velocityField {  Uint velocityField[]; };
layout(set=1,binding=3) buffer BUFFER_advectedVelocityField {  Uint advectedVelocityField[]; };
layout(set=1,binding=4) buffer BUFFER_extraFields {  ExtraFields extraFields[]; };
layout(set=1,binding=5) buffer BUFFER_advectedExtraFields {  ExtraFields advectedExtraFields[]; };
layout(set=1,binding=6) buffer BUFFER_divergenceField {  Float divergenceField[]; };
layout(set=1,binding=7) buffer BUFFER_pressureFieldA {  Float pressureFieldA[]; };
layout(set=1,binding=8) buffer BUFFER_pressureFieldB {  Float pressureFieldB[]; };

layout(set=1, binding=9) uniform _UserUniforms {
	uint CLAMP_MODE;
	uint RENDER_MODE;
	float VEL_DAMPING;
	float JITTER;
	float MAX_VELOCITY;
};

#include <Fluorescence.glsl>

#include "Creatures.glsl"

#ifdef IS_COMP_SHADER
#ifdef _ENTRY_POINT_CS_HandleInput
layout(local_size_x = 1, local_size_y = 1, local_size_z = 1) in;
void main() { CS_HandleInput(); }
#endif // _ENTRY_POINT_CS_HandleInput
#ifdef _ENTRY_POINT_CS_InitVelocity
layout(local_size_x = 32, local_size_y = 1, local_size_z = 1) in;
void main() { CS_InitVelocity(); }
#endif // _ENTRY_POINT_CS_InitVelocity
#ifdef _ENTRY_POINT_CS_AdvectVelocity
layout(local_size_x = 32, local_size_y = 1, local_size_z = 1) in;
void main() { CS_AdvectVelocity(); }
#endif // _ENTRY_POINT_CS_AdvectVelocity
#ifdef _ENTRY_POINT_CS_AdvectColor
layout(local_size_x = 32, local_size_y = 1, local_size_z = 1) in;
void main() { CS_AdvectColor(); }
#endif // _ENTRY_POINT_CS_AdvectColor
#ifdef _ENTRY_POINT_CS_ComputeDivergence
layout(local_size_x = 32, local_size_y = 1, local_size_z = 1) in;
void main() { CS_ComputeDivergence(); }
#endif // _ENTRY_POINT_CS_ComputeDivergence
#ifdef _ENTRY_POINT_CS_ComputePressureA
layout(local_size_x = 32, local_size_y = 1, local_size_z = 1) in;
void main() { CS_ComputePressureA(); }
#endif // _ENTRY_POINT_CS_ComputePressureA
#ifdef _ENTRY_POINT_CS_ComputePressureB
layout(local_size_x = 32, local_size_y = 1, local_size_z = 1) in;
void main() { CS_ComputePressureB(); }
#endif // _ENTRY_POINT_CS_ComputePressureB
#ifdef _ENTRY_POINT_CS_ResolveVelocity
layout(local_size_x = 32, local_size_y = 1, local_size_z = 1) in;
void main() { CS_ResolveVelocity(); }
#endif // _ENTRY_POINT_CS_ResolveVelocity
#endif // IS_COMP_SHADER


#ifdef IS_VERTEX_SHADER
#ifdef _ENTRY_POINT_VS_Display
void main() { VS_Display(); }
#endif // _ENTRY_POINT_VS_Display
#endif // IS_VERTEX_SHADER


#ifdef IS_PIXEL_SHADER
#ifdef _ENTRY_POINT_PS_Display
void main() { PS_Display(); }
#endif // _ENTRY_POINT_PS_Display
#endif // IS_PIXEL_SHADER
