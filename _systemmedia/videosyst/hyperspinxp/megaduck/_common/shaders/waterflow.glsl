// HyperBat Water Flow Shader
// Écoulement d'eau continu, porté de l'effet "waterflow" de Wallpaper Engine.
// La flow map peinte de WE est remplacée par une direction uniforme + une
// phase procédurale (bruit) : aucune texture externe requise.
// Technique classique du "flow mapping" : deux cycles déphasés de 0.5 sont
// mélangés pour masquer la réinitialisation de la distorsion.
// Compatible ES GLSL shader pipeline.
//
// Uniforms pilotables (storyboard "shader.xxx") — 0 = valeur d'origine WE :
//   flowTime       : temps en secondes (animer 0 -> 3600 sur 3600000 ms, repeat 0)
//   flowSpeed      : vitesse du cycle            (WE : 1, plage 0.01..2)
//   flowStrength   : amplitude de la distorsion  (WE : 1, plage 0.01..2)
//   flowFeather    : adoucissement du fondu de phase (WE : 0.4, plage 0.1..0.5)
//   flowPhaseScale : échelle de la variation de phase (WE : 2, plage 0.01..10)
//   flowDirection  : direction de l'écoulement en radians (0 = vers le haut)
//   flowMix        : mélange effet/image, 0 = 1.0 (plein effet)

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
COMPAT_VARYING   vec4 v_cycles;
COMPAT_VARYING   vec2 v_blend;

uniform COMPAT_PRECISION float flowTime;
uniform COMPAT_PRECISION float flowSpeed;
uniform COMPAT_PRECISION float flowFeather;

void main(void)
{
    vec2 hbTexCoord = vec2(TexCoord.x, 1.0 - TexCoord.y); // HB-FLIPV: ES texcoords -> espace effet (toutes varyings géométriques conjuguées)
    gl_Position = MVPMatrix * vec4(VertexCoord.xy, 0.0, 1.0);
    v_tex       = hbTexCoord;
    v_col       = COLOR;

    float speed   = (flowSpeed   == 0.0) ? 1.0 : flowSpeed;
    float feather = (flowFeather == 0.0) ? 0.4 : flowFeather;

    vec4 cycles = vec4(fract(flowTime * speed),
                       fract(flowTime * speed + 0.5),
                       fract(0.25 + flowTime * speed),
                       fract(0.25 + flowTime * speed + 0.5));

    float blend  = 2.0 * abs(cycles.x - 0.5);
    float blend2 = 2.0 * abs(cycles.z - 0.5);

    vec2 smoothParams = vec2(0.5 - feather, 0.5 + feather);
    blend  = smoothstep(smoothParams.x, smoothParams.y, blend);
    blend2 = smoothstep(smoothParams.x, smoothParams.y, blend2);

    v_cycles = cycles - vec4(0.5);
    v_blend  = vec2(blend, blend2);
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
COMPAT_VARYING vec4 v_cycles;
COMPAT_VARYING vec2 v_blend;

uniform sampler2D u_tex;
vec2 hbFlipV(vec2 p) { return vec2(p.x, 1.0 - p.y); } // HB-FLIPV


uniform COMPAT_PRECISION float flowStrength;
uniform COMPAT_PRECISION float flowPhaseScale;
uniform COMPAT_PRECISION float flowDirection;
uniform COMPAT_PRECISION float flowMix;

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

vec2 rotateVec2(vec2 v, float r)
{
    vec2 cs = vec2(cos(r), sin(r));
    return vec2(v.x * cs.x - v.y * cs.y, v.x * cs.y + v.y * cs.x);
}

void main(void)
{
    float strength = (flowStrength == 0.0) ? 1.0 : flowStrength;
    float phaseScale = (flowPhaseScale == 0.0) ? 2.0 : flowPhaseScale;
    float effectMix = (flowMix == 0.0) ? 1.0 : clamp(flowMix, 0.0, 1.0);
    effectMix *= zoneMask(v_tex);

    // Remplace la texture de phase de WE : variation procédurale
    float flowPhase = noise(v_tex * phaseScale * 8.0);

    // Remplace la flow map peinte : direction uniforme
    vec2 flowMask = rotateVec2(vec2(0.0, 1.0), flowDirection);

    vec4 flowUVOffset  = vec4(flowMask.xyxy * strength * 0.1) * v_cycles.xxyy;
    vec4 flowUVOffset2 = vec4(flowMask.xyxy * strength * 0.1) * v_cycles.zzww;

    vec4 albedo = COMPAT_TEXTURE(u_tex, hbFlipV(v_tex));
    vec4 flowAlbedo = mix(COMPAT_TEXTURE(u_tex, hbFlipV(v_tex + flowUVOffset.xy)),
                          COMPAT_TEXTURE(u_tex, hbFlipV(v_tex + flowUVOffset.zw)),
                          v_blend.x);

    vec4 flowAlbedo2 = mix(COMPAT_TEXTURE(u_tex, hbFlipV(v_tex + flowUVOffset2.xy)),
                           COMPAT_TEXTURE(u_tex, hbFlipV(v_tex + flowUVOffset2.zw)),
                           v_blend.y);

    flowAlbedo = mix(flowAlbedo, flowAlbedo2, smoothstep(0.2, 0.8, flowPhase));
    FragColor = mix(albedo, flowAlbedo, effectMix) * v_col;
}

#endif
