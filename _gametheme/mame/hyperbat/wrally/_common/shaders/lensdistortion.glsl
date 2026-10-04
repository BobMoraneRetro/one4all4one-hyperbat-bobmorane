// HyperBat Lens Distortion Shader — port clean-room de l'effet "Lens distortion"
// du Workshop Wallpaper Engine (id 2811235087). Distorsion radiale d'objectif
// (barrel / pincushion, ordre 1 + ordre 2) + ABERRATION CHROMATIQUE (les canaux
// R et B sont échantillonnés à des distorsions légèrement différentes → frange
// colorée), avec zoom, centre réglable et taille du champ. Mono-passe → un seul
// décalage UV par canal. L'anamorphique de WE est volontairement omis (niche).
// Compatible ES GLSL shader pipeline (⚠ pas de mots réservés ES 3.00).
//
// Uniforms pilotables (storyboard "shader.xxx") :
//   lensGeneral      : intensité globale 0..1 (maître ; 0 = pas de distorsion)
//   lensDistortion1  : distorsion principale  (-2..2 ; + barrel, - pincushion)
//   lensDistortion2  : distorsion d'ordre 2   (-2..2)
//   lensAberration   : aberration chromatique (-2..2)
//   lensZoom         : zoom de l'image        (0.5..1.5, défaut 1)
//   lensSize         : taille du champ de distorsion (0.05..1, défaut 0.5)
//   lensCenter       : centre (vec2 UV, défaut 0.5 0.5 — clic gauche au studio)
//   + masque de zone commun (confine l'effet, défaut partout)

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
    vec2 hbTexCoord = vec2(TexCoord.x, 1.0 - TexCoord.y); // HB-FLIPV: ES texcoords -> espace effet
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
uniform COMPAT_PRECISION vec2 textureSize;     // dimensions de l'image (aspect)
vec2 hbFlipV(vec2 p) { return vec2(p.x, 1.0 - p.y); } // HB-FLIPV

uniform COMPAT_PRECISION float lensGeneral;
uniform COMPAT_PRECISION float lensDistortion1;
uniform COMPAT_PRECISION float lensDistortion2;
uniform COMPAT_PRECISION float lensAberration;
uniform COMPAT_PRECISION float lensZoom;
uniform COMPAT_PRECISION float lensSize;
uniform COMPAT_PRECISION vec2  lensCenter;

// ── Masque de zone (placement de l'effet, équivalent du masque peint WE) ──
uniform int maskMode;                        // 0 = partout, 1 = rectangle, 2 = ellipse
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

void main(void)
{
    float general = lensGeneral;
    float zoom    = (lensZoom == 0.0) ? 1.0 : lensZoom;
    float fsize   = (lensSize == 0.0) ? 0.5 : lensSize;
    vec2  center  = (lensCenter.x == 0.0 && lensCenter.y == 0.0) ? vec2(0.5, 0.5) : lensCenter;

    // Aspect (= g_Texture0Resolution de WE) ; repli carré si non fourni.
    vec2 res    = (textureSize.x > 0.0 && textureSize.y > 0.0) ? textureSize : vec2(1.0, 1.0);
    vec2 aspect = vec2(res.y / max(res.x, 1.0), 1.0) * max(1e-6, fsize * 4.0);

    // Zoom autour du centre de l'image (WE v_TexCoord.xy).
    vec2 vtc = (v_tex - 0.5) * (1.0 + (1.0 - zoom) * general) + 0.5;
    // Décalage de centre (WE v_Transforms.xy).
    vec2 tCenter = (1.0 - center - 0.5) * general - 0.5;

    vec2 coord = (vtc + tCenter) / aspect;
    float len2 = dot(coord, coord);
    coord *= aspect;

    // Gain interne : len2 est petit (~0.1) à cause de l'échelle du champ, donc
    // la distorsion brute de WE est trop discrète ici — ×4 pour un rendu franc.
    vec2 dvec = vec2(lensDistortion1, lensDistortion2 + lensDistortion2) * (-general) * 4.0;
    vec2 amt = dvec * len2;
    vec2 ca  = lensAberration * 0.1 * dvec * len2;

    vec2 uv  = coord * (1.0 + amt.x + amt.y * len2) - tCenter;
    vec2 uv1 = coord * (1.0 + amt.x + ca.x + (amt.y + ca.y) * len2) - tCenter;
    vec2 uv2 = coord * (1.0 + amt.x - ca.x + (amt.y - ca.y) * len2) - tCenter;

    vec4 albedo = COMPAT_TEXTURE(u_tex, hbFlipV(uv));
    albedo.r = COMPAT_TEXTURE(u_tex, hbFlipV(uv1)).r;
    albedo.b = COMPAT_TEXTURE(u_tex, hbFlipV(uv2)).b;

    // Confine à la zone : hors zone, on garde l'image d'origine.
    vec4 orig = COMPAT_TEXTURE(u_tex, hbFlipV(v_tex));
    float m = zoneMask(v_tex);
    FragColor = vec4(mix(orig.rgb, albedo.rgb, m), mix(orig.a, albedo.a, m)) * v_col;
}

#endif
