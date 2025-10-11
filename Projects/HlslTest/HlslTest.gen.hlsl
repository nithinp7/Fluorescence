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

struct TestStruct {
  float4 color;
};;

struct VertexOutput {
  float4 position : SV_Position;
  float2 uv : TEXCOORD0;
};;

[[vk::binding(1, 1)]] RWStructuredBuffer<TestStruct> TestBuffer;

[[vk::binding(2, 1)]] cbuffer _UserUniforms {
	float4 TEST_COLOR;
};

#ifdef _ENTRY_POINT_CS_Test
#define CS_Test main
#endif // _ENTRY_POINT_CS_Test



#ifdef IS_VERTEX_SHADER
#if defined(_ENTRY_POINT_VS_Test) && !defined(VS_Test)
#define VS_Test main
#endif // defined(_ENTRY_POINT_VS_Test) && !defined(VS_Test)

#endif // IS_VERTEX_SHADER

#include <FlrLib/Fluorescence.hlsl>



#ifdef IS_PIXEL_SHADER
#ifndef _ATTACHMENT_VAR_outColor
#define _ATTACHMENT_VAR_outColor
static float4 outColor;
#endif // _ATTACHMENT_VAR_ outColor
#endif // IS_PIXEL_SHADER
#include "HlslTest.hlsl"



#ifdef IS_PIXEL_SHADER
#if defined(_ENTRY_POINT_PS_Test) && !defined(_PS_WRAPPER)
#define _PS_WRAPPER
struct _PixelOutput {
	float4 _outColor : SV_Target0;
}; // struct _PixelOutput
_PixelOutput main(VertexOutput IN) {
	_PixelOutput OUT;
	PS_Test(IN);
	OUT._outColor = outColor;
	return OUT;
}
#endif // defined(_ENTRY_POINT_PS_Test) && !defined(_PS_WRAPPER)
#endif // IS_PIXEL_SHADER
