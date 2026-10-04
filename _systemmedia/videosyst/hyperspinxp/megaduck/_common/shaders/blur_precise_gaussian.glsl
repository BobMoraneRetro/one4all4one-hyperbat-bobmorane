// HyperBat Precise Gaussian Blur Shader
// Flou gaussien de qualité, porté de l'effet workshop "blur_precise_gaussian"
// (3600631810, utilisé ×5 par le thème 3735601274 "镜花水月").
// L'original est un gaussien séparable en DEUX passes (H puis V) avec les
// noyaux optimisés bilinéaires de common_blur.h de Wallpaper Engine ; cette
// version MONO-PASSE compose le produit tensoriel des mêmes poids :
// vrai gaussien 13×13 en 49 fetches (ou 7×7 en 16, 3×3 en 9).
// Effet statique : animer `shader.blurScale` en storyboard pour un fondu de
// mise au point. Compatible ES GLSL shader pipeline.
//
// Uniforms pilotables (storyboard "shader.xxx") — 0 = valeur d'origine WE :
//   blurScale     : intensité du flou (vec2 x/y)  (WE : 1 1, plage 0.01..2)
//   blurKernel    : 0 = 13x13 (WE défaut), 1 = 7x7, 2 = 3x3
//   blurKeepAlpha : 0 = l'alpha est flouté aussi (WE BLURALPHA=1),
//                   1 = conserve l'alpha d'origine
//   + masque de zone commun (maskMode/maskCenter/maskSize/maskSoftness/maskInvert)
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

uniform COMPAT_PRECISION vec2 textureSize;

uniform COMPAT_PRECISION vec2 blurScale;
uniform int blurKernel;
uniform int blurKeepAlpha;

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

// Produit tensoriel du noyau 13 taps de common_blur.h (offsets bilinéaires)
vec4 gauss13(vec2 uv, vec2 t) {
    float OFF[7];
    float W[7];
    OFF[0] = 0.0;
    OFF[1] =  1.4091998770852122; OFF[2] = -1.4091998770852122;
    OFF[3] =  3.2979348079914822; OFF[4] = -3.2979348079914822;
    OFF[5] =  5.2062900776825969; OFF[6] = -5.2062900776825969;
    W[0] = 0.1976406528809576;
    W[1] = 0.2959855056006557;  W[2] = 0.2959855056006557;
    W[3] = 0.0935333619980593;  W[4] = 0.0935333619980593;
    W[5] = 0.0116608059608062;  W[6] = 0.0116608059608062;
    vec4 sum = vec4(0.0);
    for (int i = 0; i < 7; i++) {
        for (int j = 0; j < 7; j++) {
            sum += COMPAT_TEXTURE(u_tex, hbFlipV(uv + vec2(OFF[i] * t.x, OFF[j] * t.y))) * (W[i] * W[j]);
        }
    }
    return sum;
}

// Produit tensoriel du noyau 7 taps (échantillonnage asymétrique optimisé WE)
vec4 gauss7(vec2 uv, vec2 t) {
    float OFF[4];
    float W[4];
    OFF[0] =  2.3515644035337887; OFF[1] = 0.469433779698372;
    OFF[2] = -1.4091998770852121; OFF[3] = -3.0;
    W[0] = 0.2028175528299753; W[1] = 0.4044856614512112;
    W[2] = 0.3213933537319605; W[3] = 0.0713034319868530;
    vec4 sum = vec4(0.0);
    for (int i = 0; i < 4; i++) {
        for (int j = 0; j < 4; j++) {
            sum += COMPAT_TEXTURE(u_tex, hbFlipV(uv + vec2(OFF[i] * t.x, OFF[j] * t.y))) * (W[i] * W[j]);
        }
    }
    return sum;
}

// Produit tensoriel du noyau 3 taps
vec4 gauss3(vec2 uv, vec2 t) {
    float OFF[3];
    float W[3];
    OFF[0] = 0.0; OFF[1] = 1.0; OFF[2] = -1.0;
    W[0] = 0.5; W[1] = 0.25; W[2] = 0.25;
    vec4 sum = vec4(0.0);
    for (int i = 0; i < 3; i++) {
        for (int j = 0; j < 3; j++) {
            sum += COMPAT_TEXTURE(u_tex, hbFlipV(uv + vec2(OFF[i] * t.x, OFF[j] * t.y))) * (W[i] * W[j]);
        }
    }
    return sum;
}

void main(void)
{
    vec2 scale = (blurScale.x == 0.0 && blurScale.y == 0.0) ? vec2(1.0, 1.0) : blurScale;
    vec2 ts = (textureSize.y == 0.0) ? vec2(1024.0, 1024.0) : textureSize;
    vec2 texel = scale / ts;

    vec4 original = COMPAT_TEXTURE(u_tex, hbFlipV(v_tex));

    vec4 blurred;
    if (blurKernel == 2) {
        blurred = gauss3(v_tex, texel);
    } else if (blurKernel == 1) {
        blurred = gauss7(v_tex, texel);
    } else {
        blurred = gauss13(v_tex, texel);
    }

    if (blurKeepAlpha == 1) {
        blurred.a = original.a;          // BLURALPHA == 0 de WE
    }

    // équivalent du "mix(prev, albedo, mask)" de WE
    vec4 albedo = mix(original, blurred, zoneMask(v_tex));
    FragColor = albedo * v_col;
}

#endif
