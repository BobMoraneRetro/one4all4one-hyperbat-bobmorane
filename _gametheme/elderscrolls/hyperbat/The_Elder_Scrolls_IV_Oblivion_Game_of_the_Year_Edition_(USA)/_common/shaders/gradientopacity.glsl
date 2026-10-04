// HyperBat Gradient Opacity Shader (balayage de fondu)
// Porté de l'effet workshop "gradientopacity" (3373140814, utilisé par le
// thème Saint Seiya 3549997355) : un fondu d'opacité qui balaye l'image
// suivant un masque-gradient. Le masque peint de WE est remplacé par un
// gradient directionnel procédural + bruit optionnel : on obtient un effet
// de "wipe" (révélation/disparition progressive) pilotable en storyboard.
// Effet statique : animer `shader.wipeProgress` de 0 a 1 pour le balayage.
// Compatible ES GLSL shader pipeline.
//
// Uniforms pilotables (storyboard "shader.xxx") — 0 = valeur par défaut :
//   wipeProgress  : avancement du fondu, 0 = image entière, 1 = invisible
//                   (équivalent du "blend amount" WE ; défaut effectif 0)
//   wipeSoftness  : douceur du bord du balayage (WE gradientScale : 0.25, plage 0..0.25)
//   wipeDirection : direction du balayage en radians (défaut : 90° = vertical)
//   wipeNoise     : irrégularité du bord (0..1, ajout HyperBat)

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
    vec2 hbTexCoord = vec2(TexCoord.x, 1.0 - TexCoord.y); // HB-FLIPV: ES texcoords -> espace effet (toutes varyings géométriques conjuguées)
    gl_Position = MVPMatrix * vec4(VertexCoord.xy, 0.0, 1.0);
    v_tex       = hbTexCoord;
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
#define COMPAT_PRECISION mediump
#else
#define COMPAT_PRECISION
#endif

COMPAT_VARYING vec4 v_col;
COMPAT_VARYING vec2 v_tex;

uniform sampler2D u_tex;
vec2 hbFlipV(vec2 p) { return vec2(p.x, 1.0 - p.y); } // HB-FLIPV


uniform COMPAT_PRECISION float wipeProgress;
uniform COMPAT_PRECISION float wipeSoftness;
uniform COMPAT_PRECISION float wipeDirection;
uniform COMPAT_PRECISION float wipeNoise;

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
    float softness  = (wipeSoftness  == 0.0) ? 0.25 : wipeSoftness;
    float direction = (wipeDirection == 0.0) ? 1.57079632679 : wipeDirection;

    vec4 albedo = COMPAT_TEXTURE(u_tex, hbFlipV(v_tex));

    // Remplace le masque-gradient peint de WE : gradient directionnel
    vec2 dir = rotateVec2(vec2(1.0, 0.0), direction);
    float mask = clamp(dot(v_tex - vec2(0.5), dir) + 0.5, 0.0, 1.0);
    if (wipeNoise > 0.0) {
        mask += (noise(v_tex * 12.0) - 0.5) * wipeNoise * 0.5;
        mask = clamp(mask, 0.0, 1.0);
    }

    // Formule d'origine de gradientopacity.frag
    float blend = smoothstep(clamp(mask - softness, 0.0, 1.0),
                             clamp(mask + softness, 0.0, 1.0),
                             wipeProgress);
    albedo.a *= (1.0 - blend * zoneMask(v_tex));

    FragColor = albedo * v_col;
}

#endif
