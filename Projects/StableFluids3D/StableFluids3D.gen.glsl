#version 460 core

#define SCREEN_WIDTH 1440
#define SCREEN_HEIGHT 1280
#define CELLS_X 200
#define CELLS_Y 400
#define CELLS_Z 200
#define CELLS_COUNT 16000000
#define HALF_CELLS_COUNT 8000000
#define QUARTER_CELLS_COUNT 4000000
#define H 0.005000
#define DELTA_TIME 0.033333

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
  uint initialized;
  uint accumulationFrames;
};

struct ExtraFields {
  vec4 color; // TODO: turn into id or quantized color
};;

struct Uint { uint u; };

struct Float { float f; };

struct U16x2 { uint packed; };

struct VertexOutput {
  vec2 uv;
};

layout(set=1,binding=1) buffer BUFFER_globalStateBuffer {  GlobalState globalStateBuffer[]; };
layout(set=1,binding=2) buffer BUFFER_velocityField {  Uint velocityField[]; };
layout(set=1,binding=3) buffer BUFFER_advectedVelocityField {  Uint advectedVelocityField[]; };
layout(set=1,binding=4) buffer BUFFER_extraFields {  ExtraFields extraFields[]; };
layout(set=1,binding=5) buffer BUFFER_advectedExtraFields {  ExtraFields advectedExtraFields[]; };
layout(set=1,binding=6) buffer BUFFER_scratchField {  Uint scratchField[]; };
layout(set=1,binding=7) buffer BUFFER_pressureFieldA {  Float pressureFieldA[]; };
layout(set=1,binding=8) buffer BUFFER_pressureFieldB {  Float pressureFieldB[]; };
layout(set=1,binding=9, rgba32f) uniform image2D accumulationBuffer;
layout(set=1,binding=10) uniform sampler2D accumulationTexture;

layout(set=1, binding=11) uniform _UserUniforms {
	uint SLICE_IDX;
	uint CLAMP_MODE;
	uint RENDER_MODE;
	uint BACKGROUND;
	uint LIGHT_ITERS;
	float VEL_DAMPING;
	float JITTER;
	float PRESSURE_JITTER;
	float MAX_VELOCITY;
	float MAX_PRESSURE;
	float RAYMARCH_ITERS;
	float RAYMARCH_STEP_SIZE;
	float DENSITY_CUTOFF;
	float DENSITY_MULT;
	float LIGHT_THETA;
	float LIGHT_PHI;
	float LIGHT_STRENGTH;
	float BUOYANCY;
	float G;
	float VORT;
	bool ENABLE_SIM;
};

#include <FlrLib/Fluorescence.glsl>

layout(set=1, binding=12) uniform _CameraUniforms { PerspectiveCamera camera; };



#ifdef IS_PIXEL_SHADER
#if defined(_ENTRY_POINT_PS_Display) && !defined(_ENTRY_POINT_PS_Display_ATTACHMENTS)
#define _ENTRY_POINT_PS_Display_ATTACHMENTS
layout(location = 0) out vec4 outColor;
#endif // _ENTRY_POINT_PS_Display
#endif // IS_PIXEL_SHADER
#include "StableFluids3D.glsl"

#ifdef IS_COMP_SHADER
#ifdef _ENTRY_POINT_CS_HandleInput
layout(local_size_x = 1, local_size_y = 1, local_size_z = 1) in;
void main() { CS_HandleInput(); }
#endif // _ENTRY_POINT_CS_HandleInput
#ifdef _ENTRY_POINT_CS_InitVelocity
layout(local_size_x = 32, local_size_y = 1, local_size_z = 1) in;
void main() { CS_InitVelocity(); }
#endif // _ENTRY_POINT_CS_InitVelocity
#ifdef _ENTRY_POINT_CS_ComputeCurl
layout(local_size_x = 32, local_size_y = 1, local_size_z = 1) in;
void main() { CS_ComputeCurl(); }
#endif // _ENTRY_POINT_CS_ComputeCurl
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
#ifdef _ENTRY_POINT_CS_PathTrace
layout(local_size_x = 32, local_size_y = 32, local_size_z = 1) in;
void main() { CS_PathTrace(); }
#endif // _ENTRY_POINT_CS_PathTrace
#endif // IS_COMP_SHADER


#ifdef IS_VERTEX_SHADER
#ifdef _ENTRY_POINT_VS_Display
layout(location = 0) out VertexOutput _VERTEX_OUTPUT;
void main() { _VERTEX_OUTPUT = VS_Display(); }
#endif // _ENTRY_POINT_VS_Display
#endif // IS_VERTEX_SHADER


#ifdef IS_PIXEL_SHADER
#if defined(_ENTRY_POINT_PS_Display) && !defined(_ENTRY_POINT_PS_Display_INTERPOLANTS)
#define _ENTRY_POINT_PS_Display_INTERPOLANTS
layout(location = 0) in VertexOutput _VERTEX_INPUT;
void main() { PS_Display(_VERTEX_INPUT); }
#endif // _ENTRY_POINT_PS_Display
#endif // IS_PIXEL_SHADER
