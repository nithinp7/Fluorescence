#ifndef _FLRCAMERA_
#define _FLRCAMERA_

// NOTE depends on enable_feature: perspective_camera 

vec3 computeDir(vec2 uv) {
	vec2 d = uv * 2.0 - 1.0;

	vec4 target = camera.inverseProjection * vec4(d, 1.0.xx);
	return (camera.inverseView * vec4(normalize(target.xyz), 0)).xyz;
}

vec3 getCameraPos() {
  return camera.inverseView[3].xyz;
}

#endif // _FLRCAMERA_