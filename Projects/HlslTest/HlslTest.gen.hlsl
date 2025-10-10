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

struct VertexOutput {
  float4 position : SV_Position;
  float2 uv : TEXCOORD0;
};;


[[vk::binding(1, 1)]] cbuffer _UserUniforms {
	float4 TEST_COLOR;
};

#include <FlrLib/Fluorescence.hlsl>



#ifdef IS_PIXEL_SHADER
#ifndef _ATTACHMENT_VAR_outColor
#define _ATTACHMENT_VAR_outColor
static float4 outColor;
#endif // _ATTACHMENT_VAR_ outColor
#endif // IS_PIXEL_SHADER
#include "HlslTest.hlsl"



#ifdef IS_PIXEL_SHADER
#if defined(_ENTRY_POINT_PS_Test)
struct _PixelOutput {
	float4 _outColor : SV_Target0;
}; // struct _PixelOutput
_PixelOutput main(VertexOutput IN) {
	_PixelOutput OUT;
	PS_Test(IN);
	OUT._outColor = outColor;
	return OUT;
}
#endif // _ENTRY_POINT_PS_Test
#endif // IS_PIXEL_SHADER
