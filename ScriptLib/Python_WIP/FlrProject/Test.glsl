#ifdef IS_VERTEX_SHADER
VertexOutput VS_Test() {
  return VertexOutput(VS_FullScreen());
}
#endif // IS_VERTEX_SHADER

#ifdef IS_PIXEL_SHADER
void PS_Test(VertexOutput IN) {
  uint phase = uniforms.frameCount&1;
  outColor = vec4(testBuf(phase)[0], testBuf(phase)[1], testBuf(phase)[2], 1.0);
}
#endif // IS_PIXEL_SHADER