// HyperBat Sun Rays — faisceaux de lumière qui TRAVERSENT l'image depuis un centre
// (haut par défaut), en éventail, avec une ROTATION lente. Rayons radiaux doux, largeurs
// organiques variées, dégradé de couleur, estompage avec la distance. Additif sur l'image.
// ⚠ pas de mots réservés ES 3.00.
//   sunIntensity : intensité globale (maître, 0 = off)
//   sunCenter    : point d'où partent les rayons (vec2 UV, clic gauche ; 0.5 0 = haut)
//   sunCount     : nombre de rayons
//   sunSpeed     : vitesse de rotation lente
//   sunSharpness : netteté des rayons (bas = doux/larges, haut = fins/nets)
//   sunFalloff   : portée — estompage avec la distance au centre
//   sunVariation : variation organique des largeurs/luminosités
//   sunColor / sunColorEdge : dégradé centre → bord

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

uniform COMPAT_PRECISION float sunIntensity;
uniform COMPAT_PRECISION vec2  sunCenter;
uniform COMPAT_PRECISION float sunCount;
uniform COMPAT_PRECISION float sunSpeed;
uniform COMPAT_PRECISION float sunSharpness;
uniform COMPAT_PRECISION float sunFalloff;
uniform COMPAT_PRECISION float sunVariation;
uniform COMPAT_PRECISION vec4  sunColor;
uniform COMPAT_PRECISION vec4  sunColorEdge;
uniform int sunOverlay;   // 1 = calque transparent additif (empilage)

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

float srHash(float n) { return fract(sin(n) * 43758.5453123); }
float srNoise(float x) {
    float i = floor(x), f = fract(x);
    f = f * f * (3.0 - 2.0 * f);
    return mix(srHash(i), srHash(i + 1.0), f);
}

void main(void) {
    vec4 src = COMPAT_TEXTURE(u_tex, hbFlipV(v_tex));
    float intensity = clamp(sunIntensity, 0.0, 1.0);
    vec2 center = (sunCenter.x == 0.0 && sunCenter.y == 0.0) ? vec2(0.5, 0.0) : sunCenter;
    float count = (sunCount <= 0.0) ? 16.0 : sunCount;
    float sharp = (sunSharpness == 0.0) ? 2.0 : sunSharpness;
    float falloff = (sunFalloff == 0.0) ? 0.7 : sunFalloff;

    vec2 res = (textureSize.x > 0.0 && textureSize.y > 0.0) ? textureSize : vec2(1.0, 1.0);
    float aspect = res.x / max(res.y, 1.0);
    vec2 d = (v_tex - center) * vec2(aspect, 1.0);
    float r = length(d);
    float a = atan(d.y, d.x) + uTime * sunSpeed;   // rotation lente

    // Variation organique : déphase et module la largeur des rayons par du bruit angulaire.
    float n = srNoise(a * 1.5);
    float spoke = 0.5 + 0.5 * sin(a * count + (n - 0.5) * sunVariation * 6.2831853);
    float ray = pow(clamp(spoke, 0.0, 1.0), sharp);
    // Luminosité variable d'un rayon à l'autre (certains plus forts).
    float idx = floor((a * count) / 6.2831853);
    ray *= mix(1.0, 0.45 + 0.55 * srHash(idx * 1.37), sunVariation);

    // Estompage avec la distance (les rayons s'éteignent en s'éloignant) + fondu au centre.
    float fade = pow(clamp(1.0 - r * falloff, 0.0, 1.0), 1.5) * smoothstep(0.0, 0.08, r);
    float fx = ray * fade;

    vec3 col = mix(sunColorEdge.rgb, sunColor.rgb, fade);
    float gate = intensity * zoneMask(v_tex);

    if (sunOverlay == 1) {
        // Calque transparent additif (empilage) : couleur dans rgb, magnitude dans l'alpha.
        FragColor = vec4(col, clamp(fx * gate * 1.6, 0.0, 0.9)) * v_col;
    } else {
        // Additif sur l'image. L'alpha de sortie = max(alpha image, force des rayons) →
        // les rayons s'affichent AUSSI dans les zones transparentes du calque (autour du
        // perso), pas seulement sur le perso. (Pour couvrir tout l'écran : calque plein écran.)
        float energyA = clamp(fx * gate * 2.0, 0.0, 1.0);
        vec3 outc = src.rgb + col * fx * gate * 2.0;
        FragColor = vec4(outc, max(src.a, energyA)) * v_col;
    }
}
#endif
