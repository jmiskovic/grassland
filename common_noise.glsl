vec2 hash22 (vec2 p) {
  p = vec2(dot(p, vec2(127.1, 311.7)), dot(p, vec2(269.5, 183.3)));
  return -1.0 + 2.0 * fract(sin(p) * 43758.5453123);
}

float noise2(in vec2 p) {
  const float K1 = 0.366025404; // (sqrt(3)-1)/2;
  const float K2 = 0.211324865; // (3-sqrt(3))/6;
  vec2 i = floor(p + (p.x+p.y)*K1);
  vec2 a = p - i + (i.x+i.y)*K2;
  vec2 o = (a.x>a.y) ? vec2(1.0,0.0) : vec2(0.0,1.0); //vec2 of = 0.5 + 0.5*vec2(sign(a.x-a.y), sign(a.y-a.x));
  vec2 b = a - o + K2;
  vec2 c = a - 1.0 + 2.0*K2;
  vec3 h = max(0.5-vec3(dot(a,a), dot(b,b), dot(c,c) ), 0.0 );
  vec3 n = h*h*h*h*vec3( dot(a, hash22(i+0.0)), dot(b, hash22(i+o)), dot(c, hash22(i+1.0)));
  return dot(n, vec3(70.0));
}

float terrain(vec2 pos) {
  return 18. * noise2(pos * 0.005) - 4.;
}