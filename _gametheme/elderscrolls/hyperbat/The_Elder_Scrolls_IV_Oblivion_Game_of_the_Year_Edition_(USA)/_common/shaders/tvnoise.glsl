// HyperBat TV Noise / Static Shader
// Simulates analog TV static noise effect
// Compatible with ES GLSL shader pipeline

#if defined(VERTEX)

#if __VERSION__ >= 130
#define COMPAT_VARYING out
#define COMPAT_ATTRIBUTE in
#define COMPAT_TEXTURE texture
#else
#define COMPAT_VARYING varying
#define COMPAT_ATTRIBUTE attribute
#define COMPAT_TEXTURE texture2D
#endif

#ifdef GL_ES
#define COMPAT_PRECISION mediump
#else
#define COMPAT_PRECISION
#endif

uniform   mat4 MVPMatrix;
COMPAT_ATTRIBUTE vec2 VertexCoord;
COMPAT_ATTRIBUTE vec2 TexCoord;
COMPAT_ATTRIBUTE vec4 COLOR;
COMPAT_VARYING   vec2 v_tex;
COMPAT_VARYING   vec4 v_col;

void main(void)
{
    gl_Position = MVPMatrix * vec4(VertexCoord.xy, 0.0, 1.0);
    v_tex       = TexCoord;
    v_col       = COLOR;
}

#elif defined(FRAGMENT)

#if __VERSION__ >= 130
#define COMPAT_VARYING in
#define COMPAT_TEXTURE texture
out vec4 FragColor;
#else
#define COMPAT_VARYING varying
#define FragColor gl_FragColor
#define COMPAT_TEXTURE texture2D
#endif

#ifdef GL_ES
#ifdef GL_FRAGMENT_PRECISION_HIGH
precision highp float;
#else
precision mediump float;
#endif
#else
#define COMPAT_PRECISION
#endif

COMPAT_VARYING vec4 v_col;
COMPAT_VARYING vec2 v_tex;

uniform sampler2D u_tex;
uniform float noiseTime;

// Pseudo-random hash function (GPU-friendly, no external state)
float hash(vec2 p) {
    p = fract(p * vec2(443.8975, 397.2973));
    p += dot(p, p.yx + 19.19);
    return fract(p.x * p.y);
}

// Smooth noise based on hash
float noise(vec2 uv) {
    vec2 i = floor(uv);
    vec2 f = fract(uv);
    f = f * f * (3.0 - 2.0 * f); // smoothstep

    float a = hash(i);
    float b = hash(i + vec2(1.0, 0.0));
    float c = hash(i + vec2(0.0, 1.0));
    float d = hash(i + vec2(1.0, 1.0));

    return mix(mix(a, b, f.x), mix(c, d, f.x), f.y);
}

void main(void)
{
    vec4 texColor = COMPAT_TEXTURE(u_tex, v_tex);

    if (noiseTime <= 0.0) {
        FragColor = texColor * v_col;
        return;
    }

    // Generate time-varying noise
    float t = noiseTime;

    // High-frequency noise (TV static grain)
    float n1 = hash(v_tex * 500.0 + vec2(t * 13.7, t * 7.3));

    // Medium-frequency noise (interference bands)
    float scanline = sin(v_tex.y * 800.0 + t * 50.0) * 0.5 + 0.5;
    float band = smoothstep(0.3, 0.7, noise(vec2(v_tex.y * 4.0 + t * 2.0, t)));

    // Combine noise layers
    float noiseVal = n1 * 0.6 + scanline * 0.2 + band * 0.2;

    // Mix original color with noise (intensity based on noiseTime position)
    // When noiseTime is about to loop, create "moments of clarity"
    float intensity = 0.4; // base noise strength
    vec3 noiseColor = vec3(noiseVal);
    vec3 finalRGB = mix(texColor.rgb, noiseColor, intensity);

    // Add slight color aberration for realism
    float aberration = hash(vec2(t, v_tex.y * 100.0)) * 0.02;
    finalRGB.r += aberration;
    finalRGB.b -= aberration;

    FragColor = vec4(finalRGB, texColor.a) * v_col;
}

#endif
