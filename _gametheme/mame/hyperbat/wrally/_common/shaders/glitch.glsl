// HyperBat Glitch — port clean-room de "Distortion Glitch" (WE 2489075276).
// Glitch numerique : decalage chromatique (RGB split), failles horizontales qui
// sautent par blocs, entrelacement (scanlines) et bruit, le tout anime par a-coups.
// Mono-passe procedural (bruit par hash, pas de texture). ⚠ pas de mots reserves ES 3.00.
//   glitchAmount : intensite globale (maitre, 0 = net)
//   glitchSpeed  : frequence des sauts
//   glitchBlock  : hauteur des blocs de failles
//   glitchSplit  : decalage chromatique
//   glitchJitter : amplitude du saut horizontal
//   glitchNoise  : grain / parasites

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
uniform COMPAT_PRECISION float uTime;
vec2 hbFlipV(vec2 p) { return vec2(p.x, 1.0 - p.y); }

uniform COMPAT_PRECISION float glitchAmount;
uniform COMPAT_PRECISION float glitchSpeed;
uniform COMPAT_PRECISION float glitchBlock;
uniform COMPAT_PRECISION float glitchSplit;
uniform COMPAT_PRECISION float glitchJitter;
uniform COMPAT_PRECISION float glitchNoise;

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

float hash21(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453123); }

void main(void) {
    float amt = clamp(glitchAmount, 0.0, 1.0);
    float spd = (glitchSpeed == 0.0) ? 8.0 : glitchSpeed;
    float blockH = (glitchBlock == 0.0) ? 12.0 : glitchBlock;
    float split = (glitchSplit == 0.0) ? 0.006 : glitchSplit;
    float jit = (glitchJitter == 0.0) ? 0.05 : glitchJitter;

    // temps discretise : le glitch "saute" plutot que de glisser
    float t = floor(uTime * spd);
    // bloc de lignes courant + sa graine aleatoire
    float row = floor(v_tex.y * blockH);
    float seed = hash21(vec2(row, t));
    // seuls quelques blocs glitchent a un instant donne
    float act = step(0.7, seed) * amt;

    // saut horizontal du bloc
    float shift = (hash21(vec2(row, t + 1.0)) - 0.5) * jit * act;
    vec2 uv = vec2(v_tex.x + shift, v_tex.y);

    // decalage chromatique, accentue sur les blocs actifs (s'eteint avec l'intensite)
    float ca = split * (0.4 + act) * amt;
    float r = COMPAT_TEXTURE(u_tex, hbFlipV(vec2(uv.x + ca, uv.y))).r;
    float g = COMPAT_TEXTURE(u_tex, hbFlipV(uv)).g;
    float b = COMPAT_TEXTURE(u_tex, hbFlipV(vec2(uv.x - ca, uv.y))).b;
    float a = COMPAT_TEXTURE(u_tex, hbFlipV(uv)).a;
    vec3 col = vec3(r, g, b);

    // entrelacement (scanlines) + parasites sur les blocs actifs
    vec2 res = (textureSize.x > 0.0 && textureSize.y > 0.0) ? textureSize : vec2(1.0, 256.0);
    float scan = 0.85 + 0.15 * sin(v_tex.y * res.y * 1.5708);
    col *= mix(1.0, scan, act);
    float noiseAmt = (glitchNoise == 0.0) ? 0.15 : glitchNoise;
    float n = hash21(v_tex * res * 0.5 + t) - 0.5;
    col += n * noiseAmt * act;

    vec3 base = COMPAT_TEXTURE(u_tex, hbFlipV(v_tex)).rgb;
    col = mix(base, col, zoneMask(v_tex));
    FragColor = vec4(col, a) * v_col;
}
#endif
