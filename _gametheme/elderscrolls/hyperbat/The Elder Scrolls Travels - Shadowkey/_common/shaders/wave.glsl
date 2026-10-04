// HyperBat Wave / Flag Undulation Shader
// Creates a waving flag effect on textures
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
uniform float waveTime;

// Wave parameters
const float WAVE_AMPLITUDE = 0.03;
const float WAVE_FREQUENCY = 8.0;
const float WAVE_SPEED = 2.0;

void main(void)
{
    if (waveTime <= 0.0) {
        // No wave effect
        FragColor = COMPAT_TEXTURE(u_tex, v_tex) * v_col;
        return;
    }

    // Calculate wave displacement based on position and time
    float phase = v_tex.x * WAVE_FREQUENCY + waveTime * WAVE_SPEED;
    float waveY = sin(phase) * WAVE_AMPLITUDE * (1.0 - exp(-waveTime * 0.5));

    // Progressive wave: stronger at the edges, weaker at the anchor point
    float progressiveFactor = v_tex.x; // Anchored on left side

    vec2 displacedUV = v_tex;
    displacedUV.y += waveY * progressiveFactor;

    // Add a subtle secondary wave for realism
    float phase2 = v_tex.x * WAVE_FREQUENCY * 1.7 + waveTime * WAVE_SPEED * 1.3;
    displacedUV.y += sin(phase2) * WAVE_AMPLITUDE * 0.3 * progressiveFactor;

    // Clamp UV to valid texture range
    displacedUV = clamp(displacedUV, vec2(0.0), vec2(1.0));

    // Sample texture with displaced coordinates
    vec4 texColor = COMPAT_TEXTURE(u_tex, displacedUV);

    // Add subtle shading based on wave slope for 3D appearance
    float slope = cos(phase) * WAVE_AMPLITUDE * WAVE_FREQUENCY;
    float shade = 1.0 + slope * progressiveFactor * 0.5;
    texColor.rgb *= clamp(shade, 0.7, 1.3);

    FragColor = texColor * v_col;
}

#endif
