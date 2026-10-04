// HyperBat Radial Blur — port clean-room de "Radial blur" (WE 2818465820).
// Flou radial : N échantillons le long de la direction radiale depuis un centre,
// pondérés par la distance^exposant — zoom/flou qui s'intensifie vers les bords.
// Mono-passe (gather). Compatible ES GLSL (⚠ pas de mots réservés ES 3.00).
//   rblurStrength : intensité (maître, 0 = net)
//   rblurSamples  : nombre d'échantillons (qualité)
//   rblurCenter   : centre (vec2 UV)
//   rblurExponent : courbe (bords plus ou moins flous)
//   rblurSize     : échelle du champ

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
uniform mat4 MVPMatrix;
COMPAT_ATTRIBUTE vec2 VertexCoord;
COMPAT_ATTRIBUTE vec2 TexCoord;
COMPAT_ATTRIBUTE vec4 COLOR;
COMPAT_VARYING vec2 v_tex;
COMPAT_VARYING vec4 v_col;
void main(void) {
    v_tex = vec2(TexCoord.x, 1.0 - TexCoord.y);
    gl_Position = MVPMatrix * vec4(VertexCoord.xy, 0.0, 1.0);
    v_col = COLOR;
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
#define COMPAT_PRECISION mediump
#else
#define COMPAT_PRECISION
#endif
COMPAT_VARYING vec4 v_col;
COMPAT_VARYING vec2 v_tex;
uniform sampler2D u_tex;
uniform COMPAT_PRECISION vec2 textureSize;
vec2 hbFlipV(vec2 p) { return vec2(p.x, 1.0 - p.y); }

uniform COMPAT_PRECISION float rblurStrength;
uniform COMPAT_PRECISION float rblurSamples;
uniform COMPAT_PRECISION vec2  rblurCenter;
uniform COMPAT_PRECISION float rblurExponent;
uniform COMPAT_PRECISION float rblurSize;

uniform int maskMode;
uniform COMPAT_PRECISION vec2  maskCenter;
uniform COMPAT_PRECISION vec2  maskSize;
uniform COMPAT_PRECISION float maskSoftness;
uniform int maskInvert;
float zoneMask(vec2 uv) {
    if (maskMode == 0) return 1.0;
    vec2 size = (maskSize.x == 0.0 && maskSize.y == 0.0) ? vec2(0.5, 0.5) : maskSize;
    vec2 d = abs(uv - maskCenter) / max(size * 0.5, vec2(1e-5));
    float dist = (maskMode == 2) ? length(d) : max(d.x, d.y);
    float soft = max(maskSoftness, 1e-4);
    float m = 1.0 - smoothstep(1.0 - soft, 1.0 + soft, dist);
    return (maskInvert == 1) ? 1.0 - m : m;
}

void main(void) {
    int N = int(clamp((rblurSamples < 2.0) ? 20.0 : rblurSamples, 2.0, 40.0));
    vec2 center = (rblurCenter.x == 0.0 && rblurCenter.y == 0.0) ? vec2(0.5, 0.5) : rblurCenter;
    float expo = (rblurExponent == 0.0) ? 2.0 : rblurExponent;
    float fsize = (rblurSize == 0.0) ? 1.0 : rblurSize;
    vec2 res = (textureSize.x > 0.0 && textureSize.y > 0.0) ? textureSize : vec2(1.0, 1.0);
    vec2 asp = vec2(res.x / max(res.y, 1.0), 1.0) * fsize;

    float strength = -rblurStrength * 0.1 / float(N);
    vec4 sum = vec4(0.0);
    for (int i = 0; i < 40; i++) {
        if (i >= N) break;
        vec2 c = (v_tex - center) * asp;
        float r = length(c);
        vec2 uv = center + (c * (1.0 + strength * float(i) * pow(r, expo + 0.01))) / asp;
        sum += COMPAT_TEXTURE(u_tex, hbFlipV(clamp(uv, vec2(0.0), vec2(1.0))));
    }
    sum /= float(N);
    vec4 base = COMPAT_TEXTURE(u_tex, hbFlipV(v_tex));
    FragColor = mix(base, sum, zoneMask(v_tex)) * v_col;
}
#endif
