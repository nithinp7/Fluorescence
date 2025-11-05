#ifdef IS_VERTEX_SHADER
VertexOutput VS_Test() {
  return VertexOutput(VS_FullScreen());
}
#endif // IS_VERTEX_SHADER

#ifdef IS_PIXEL_SHADER
void PS_Test(VertexOutput IN) {
  outColor = vec4(IN.uv, testBuf(uniforms.frameCount&1)[0], 1.0);
}
#endif // IS_PIXEL_SHADER