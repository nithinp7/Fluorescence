
// reference: Monaghan 1992
float W(float r) {
  const float h = PARTICLE_RADIUS;
  const float o = 1.0 / PI / h / h / h;
  float r_h = r / h;

  if (r_h > 2.0)
    return 0.0;
  
  if (r_h <= 1.0) {
    float r_h_2 = r_h * r_h;
    float r_h_3 = r_h_2 * r_h;
    return o * (1.0 - 1.5 * r_h_2 + 0.75 * r_h_3);
  }
  else 
  {
    float t = 2.0 - r_h;
    return o * (0.25 * t * t * t);
  }
}

float grad_W(float r) {
  const float h = PARTICLE_RADIUS;
  const float o = 1.0 / PI / h / h / h;
  float r_h = r / h;

  if (r_h > 2.0)
    return 0.0;
  
  float r_h_2 = r_h * r_h;
  // TODO: check math here...
  if (r_h <= 1.0) {
    float r_h_2 = r_h * r_h;
    return o * (-3.0 * r_h + 2.25 * r_h_2) / h;
  }
  else 
  {
    return o * (-12.0 + 12.0 * r_h + 3.0 * r_h_2) / h;
  }
}

// reference: Monaghan 1992
float W_2D(float r) {
  const float h = PARTICLE_RADIUS;
  const float o = 10.0 / 7.0 / PI / h / h;
  float r_h = r / h;

  if (r_h > 2.0)
    return 0.0;
  
  if (r_h <= 1.0) {
    float r_h_2 = r_h * r_h;
    float r_h_3 = r_h_2 * r_h;
    return o * (1.0 - 1.5 * r_h_2 + 0.75 * r_h_3);
  }
  else 
  {
    float t = 2.0 - r_h;
    return o * (0.25 * t * t * t);
  }
}

float grad_W_2D(float r) {
  const float h = PARTICLE_RADIUS;
  const float o = 10.0 / 7.0 / PI / h / h;
  float r_h = r / h;

  if (r_h > 2.0)
    return 0.0;
  
  float r_h_2 = r_h * r_h;
  // TODO: check math here...
  if (r_h <= 1.0) {
    float r_h_2 = r_h * r_h;
    return o * (-3.0 * r_h + 2.25 * r_h_2) / h;
  }
  else 
  {
    return o * (-12.0 + 12.0 * r_h + 3.0 * r_h_2) / h;
  }
}

