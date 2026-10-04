// HyperBat Foliage Sway Shader
// Balancement de feuillage (mode UV), porté de l'effet "foliagesway" de
// Wallpaper Engine. La texture de bruit est remplacée par un bruit procédural
// (même hash/noise que tvnoise.glsl) : aucune texture externe requise.
// Le déphasage par bruit fait osciller chaque zone de l'image différemment,
// comme des feuilles dans le vent.
// Compatible ES GLSL shader pipeline.
//
// Uniforms pilotables (storyboard "shader.xxx") — 0 = valeur d'origine WE :
//   swayTime      : temps en secondes (animer 0 -> 3600 sur 3600000 ms, repeat 0)
//   swaySpeed     : vitesse d'oscillation        (WE : 5, plage 0.01..20)
//   swayStrength  : amplitude                    (WE : 0.4, plage 0.01..1)
//   swayPhase     : influence du déphasage local (WE : 0.5, plage 0..2)
//   swayPower     : forme de l'oscillation       (WE : 1, plage 0.01..2)
//   swayScale     : échelle des zones de bruit   (WE : 0.05, plage 0..1)
//   swayRatio     : ratio directionnel           (WE : 0.3, plage 0.01..10)
//   swayDirection : direction du balancement en radians (WE : 0)
//
// Le moteur doit fournir textureSize (déjà le cas dans le pipeline HyperBat).

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
COMPAT_VARYING   vec4 v_texnoise;
COMPAT_VARYING   vec3 v_params;

uniform COMPAT_PRECISION vec2 textureSize;
uniform COMPAT_PRECISION float swayStrength;
uniform COMPAT_PRECISION float swayScale;
uniform COMPAT_PRECISION float swayRatio;
uniform COMPAT_PRECISION float swayDirection;

vec2 rotateVec2(vec2 v, float r)
{
    vec2 cs = vec2(cos(r), sin(r));
    return vec2(v.x * cs.x - v.y * cs.y, v.x * cs.y + v.y * cs.x);
}

void main(void)
{
    vec2 hbTexCoord = vec2(TexCoord.x, 1.0 - TexCoord.y); // HB-FLIPV: ES texcoords -> espace effet (toutes varyings géométriques conjuguées)
    gl_Position = MVPMatrix * vec4(VertexCoord.xy, 0.0, 1.0);
    v_tex       = hbTexCoord;
    v_col       = COLOR;

    float strength = (swayStrength == 0.0) ? 0.4  : swayStrength;
    float nScale   = (swayScale    == 0.0) ? 0.05 : swayScale;
    float ratio    = (swayRatio    == 0.0) ? 0.3  : swayRatio;

    float texAspect = (textureSize.y == 0.0) ? 1.0 : (textureSize.x / textureSize.y);
    float aspect = texAspect * ratio;

    v_texnoise.zw = rotateVec2(vec2(1.0 / aspect, aspect), swayDirection);
    v_texnoise.xy = hbTexCoord.xy * nScale;

    v_params.xy = rotateVec2(hbTexCoord.xy, swayDirection);
    v_params.z  = strength * strength * 0.005;
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

#define M_PI 3.14159265359

COMPAT_VARYING vec4 v_col;
COMPAT_VARYING vec2 v_tex;
COMPAT_VARYING vec4 v_texnoise;
COMPAT_VARYING vec3 v_params;

uniform sampler2D u_tex;
vec2 hbFlipV(vec2 p) { return vec2(p.x, 1.0 - p.y); } // HB-FLIPV


uniform COMPAT_PRECISION float swayTime;
uniform COMPAT_PRECISION float swaySpeed;
uniform COMPAT_PRECISION float swayPower;
uniform COMPAT_PRECISION float swayPhase;

// ── Masque de zone (placement de l'effet, équivalent du masque peint WE) ──
uniform int maskMode;                        // 0 = partout, 1 = rectangle, 2 = ellipse
uniform COMPAT_PRECISION vec2  maskCenter;   // centre de la zone (UV)
uniform COMPAT_PRECISION vec2  maskSize;     // taille de la zone (UV, 0 = 0.5 0.5)
uniform COMPAT_PRECISION float maskSoftness; // douceur du bord
uniform int maskInvert;                      // 1 = effet hors de la zone

float zoneMask(vec2 uv) {
    if (maskMode == 0) return 1.0;
    vec2 size = (maskSize.x == 0.0 && maskSize.y == 0.0) ? vec2(0.5, 0.5) : maskSize;
    vec2 d = abs(uv - maskCenter) / max(size * 0.5, vec2(1e-5));
    float dist = (maskMode == 2) ? length(d) : max(d.x, d.y);
    float soft = max(maskSoftness, 1e-4);
    float m = 1.0 - smoothstep(1.0 - soft, 1.0 + soft, dist);
    return (maskInvert == 1) ? 1.0 - m : m;
}

// Pseudo-random hash function (identique à tvnoise.glsl)
float hash(vec2 p) {
    p = fract(p * vec2(443.8975, 397.2973));
    p += dot(p, p.yx + 19.19);
    return fract(p.x * p.y);
}

// Smooth noise based on hash (identique à tvnoise.glsl)
float noise(vec2 uv) {
    vec2 i = floor(uv);
    vec2 f = fract(uv);
    f = f * f * (3.0 - 2.0 * f);

    float a = hash(i);
    float b = hash(i + vec2(1.0, 0.0));
    float c = hash(i + vec2(0.0, 1.0));
    float d = hash(i + vec2(1.0, 1.0));

    return mix(mix(a, b, f.x), mix(c, d, f.x), f.y);
}

// Remplace la texture "util/noise" de WE (256.0 = fréquence équivalente)
float noiseSample(vec2 uv) {
    return noise(uv * 256.0);
}

void main(void)
{
    float speed = (swaySpeed == 0.0) ? 5.0 : swaySpeed;
    float power = (swayPower == 0.0) ? 1.0 : swayPower;
    float phaseAmount = (swayPhase == 0.0) ? 0.5 : swayPhase;

    float noiseValue = noiseSample(v_texnoise.xy);
    float amp = v_params.z * zoneMask(v_tex);   // équivalent du "amp *= mask" de WE

    // Oscillation à 4 harmoniques déphasées par le bruit local
    float phase = (noiseValue * M_PI * 2.0 + v_params.x * 10.0 + v_params.y * 5.0) * phaseAmount;
    vec4 sines = phase + speed * swayTime * vec4(1.0, -0.16161616, 0.0083333, -0.00019841);
    sines = sin(sines);
    vec4 csines = 0.4 + phase + speed * swayTime * vec4(-0.5, 0.041666666, -0.0013888889, 0.000024801587);
    csines = sin(csines);

    sines  = pow(abs(sines),  vec4(power)) * sign(sines);
    csines = pow(abs(csines), vec4(power)) * sign(csines);

    vec2 texCoordOffset;
    texCoordOffset.x = v_texnoise.z * dot(sines,  vec4(amp));
    texCoordOffset.y = v_texnoise.w * dot(csines, vec4(amp));

    vec2 texCoord = clamp(texCoordOffset + v_tex, vec2(0.0), vec2(1.0));
    FragColor = COMPAT_TEXTURE(u_tex, hbFlipV(texCoord)) * v_col;
}

#endif
