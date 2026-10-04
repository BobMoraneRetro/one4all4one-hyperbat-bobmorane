// HyperBat Pixelate Shader
// Pixelisation effect for EmulationStation / RetroBat themes
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
uniform vec2 textureSize;
uniform float pixelSize;

void main(void)
{
    if (pixelSize <= 1.0) {
        // No pixelation, pass through
        FragColor = COMPAT_TEXTURE(u_tex, v_tex) * v_col;
        return;
    }

    // Quantize UV coordinates to create blocky pixel effect
    vec2 texSizeInPixels = textureSize;
    vec2 blockSize = vec2(pixelSize) / texSizeInPixels;
    vec2 quantizedUV = floor(v_tex / blockSize) * blockSize + blockSize * 0.5;

    // Clamp to valid range
    quantizedUV = clamp(quantizedUV, vec2(0.0), vec2(1.0));

    FragColor = COMPAT_TEXTURE(u_tex, quantizedUV) * v_col;
}

#endif
