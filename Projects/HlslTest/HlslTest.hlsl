
#ifdef IS_COMP_SHADER
[numthreads(32, 1, 1)]
void CS_Test(uint tid : SV_DispatchThreadId) {
  TestBuffer[tid].color = float4(TEST_COLOR.rgb * tid / 32.0, 1.0);
}
#endif // IS_COMP_SHADER

#ifdef IS_VERTEX_SHADER
VertexOutput VS_Test(uint vidx : SV_VERTEXID) {
  VertexOutput OUT;
  OUT.uv = float4(vidx & 2, (vidx << 1) & 2, 0.0, 0.0);
  OUT.position = float4(OUT.uv * 2.0f - 1.0f, 0.0f, 1.0f);
  return OUT;
}
#endif // IS_VERTEX_SHADER

#ifdef IS_PIXEL_SHADER
void PS_Test(VertexOutput IN) {
  uint idx = uint(IN.uv.x * 31.9);
  outColor = TestBuffer[idx].color;
}
#endif // IS_PIXEL_SHADER