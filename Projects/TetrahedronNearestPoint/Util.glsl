vec3 computeDir(vec2 uv) {
	vec2 d = uv * 2.0 - 1.0;

	vec4 target = camera.inverseProjection * vec4(d, 1.0.xx);
	return (camera.inverseView * vec4(normalize(target.xyz), 0)).xyz;
}

SimpleVertex calcSphereVert(float theta, float phi) {
  return SimpleVertex(vec4(cos(theta) * cos(phi), sin(phi), -sin(theta) * cos(phi), 1.0));
}

vec3 sampleEnv(vec3 dir) {
  float c = 5.0;
  vec3 n = 0.5 * normalize(dir) + 0.5.xxx;
  uint BACKGROUND = 0;
  if (BACKGROUND == 0) {
    return round(n * c) / c;
  } else if (BACKGROUND == 1) {
    return round(fract(n * c));
  } else if (BACKGROUND == 2) {
    return round(n);
  } else {
    float f = n.x + n.y + n.z;
    return max(round(fract(f * c)), 0.2).xxx;
  }
}

// DEBUG LINES TOOL
vec4 g_currentLineColor = vec4(0.0, 1.0, 0.0, 1.0);
uint g_lineVertexCount = 0;
void addLine(vec3 a, vec3 b) {
  lineVertexBuffer[g_lineVertexCount++] = Vertex(vec4(a, 1.0), g_currentLineColor);
  lineVertexBuffer[g_lineVertexCount++] = Vertex(vec4(b, 1.0), g_currentLineColor);
}

void setLineColor(vec3 color) { g_currentLineColor = vec4(color, 1.0); }

void finishLines() {
  IndirectArgs args;
  args.firstInstance = 0;
  args.instanceCount = 1;
  args.firstVertex = 0;
  args.vertexCount = g_lineVertexCount;
  linesIndirect[0] = args;
}
