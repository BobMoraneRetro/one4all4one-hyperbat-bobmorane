// HyperBat Rays (combiné) — un seul effet de rayons réunissant les deux styles :
//   • ORGANIQUE  : faisceaux striés/animés (façon god-rays "Rayons lumineux"),
//   • RADIAL NET : spokes nets (façon "Rayons de soleil"),
//   • LES DEUX   : mélange des deux.
// Tout en polaire depuis un centre, avec ROTATION lente, halo doux (lueur), dégradé de
// couleur et estompage avec la distance. Additif + mode overlay. ⚠ pas de mots réservés ES.
//   raysIntensity : intensité globale (maître, 0 = off)
//   raysStyle     : 0 organique, 1 radial net, 2 les deux
//   raysCenter    : centre d'émission (vec2 UV, clic gauche)
//   raysRotation  : vitesse de rotation lente
//   raysDensity   : nombre / densité des rayons
//   raysSharpness : netteté (bas = doux/larges, haut = fins/nets)
//   raysGlow      : halo doux autour des rayons
//   raysFalloff   : portée (estompage avec la distance)
//   raysVariation : variation organique des largeurs/luminosités
//   raysColor / raysColorEdge : dégradé centre → bord

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

uniform COMPAT_PRECISION float raysIntensity;
uniform int raysStyle;
uniform COMPAT_PRECISION vec2  raysCenter;
uniform COMPAT_PRECISION float raysRotation;
uniform COMPAT_PRECISION float raysDensity;
uniform COMPAT_PRECISION float raysSharpness;
uniform COMPAT_PRECISION float raysGlow;
uniform COMPAT_PRECISION float raysFalloff;
uniform COMPAT_PRECISION float raysVariation;
uniform COMPAT_PRECISION vec4  raysColor;
uniform COMPAT_PRECISION vec4  raysColorEdge;
uniform int raysOverlay;

uniform int maskMode;
uniform COMPAT_PRECISION vec2  maskCenter;
uniform COMPAT_PRECISION vec2  maskSize;
uniform COMPAT_PRECISION float maskSoftness;
uniform int maskInvert;
float zoneMask(vec2 uv) {
    if (maskMode == 0) return 1.0;
    vec2 size = (maskSize.x == 0.0 && maskSize.y == 0.0) ? vec2(0.5, 0.5) : maskSize;
    vec2 dd = abs(uv - maskCenter) / max(size * 0.5, vec2(1e-5));
    float dist = (maskMode == 2) ? length(dd) : max(dd.x, dd.y);
    float soft = max(maskSoftness, 1e-4);
    float m = 1.0 - smoothstep(1.0 - soft, 1.0 + soft, dist);
    return (maskInvert == 1) ? 1.0 - m : m;
}

float rmHash(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453123); }
float rmNoise(vec2 p) {
    vec2 i = floor(p); vec2 f = fract(p);
    f = f * f * (3.0 - 2.0 * f);
    float a = rmHash(i), b = rmHash(i + vec2(1.0, 0.0));
    float c = rmHash(i + vec2(0.0, 1.0)), d = rmHash(i + vec2(1.0, 1.0));
    return mix(mix(a, b, f.x), mix(c, d, f.x), f.y);
}
float rmHash1(float n) { return fract(sin(n) * 43758.5453123); }

// Motif de rayons à un "angle" donné (en tours, 0..1) et une netteté donnée.
float rayPattern(float ang01, float r, float density, float sharp, float varAmt, float t, int style) {
    // ORGANIQUE : bruit le long de l'angle, qui s'écoule le long du rayon.
    float n1 = rmNoise(vec2(ang01 * density, r * 2.0 + t * 0.4));
    float n2 = rmNoise(vec2(ang01 * density * 1.7 + 5.0, r * 2.6 - t * 0.55));
    float organic = pow(smoothstep(0.18, 0.62, n1 * n2), sharp);
    // RADIAL NET : spokes sinusoïdaux, largeurs/luminosités variées.
    float a = ang01 * 6.2831853;
    float nv = rmNoise(vec2(a * 1.5, 0.0));
    float spoke = 0.5 + 0.5 * sin(a * density + (nv - 0.5) * varAmt * 6.2831853);
    float radial = pow(clamp(spoke, 0.0, 1.0), sharp);
    radial *= mix(1.0, 0.45 + 0.55 * rmHash1(floor(ang01 * density)), varAmt);
    if (style == 1) return radial;
    if (style == 2) return max(organic, radial * 0.85);
    return organic;
}

void main(void) {
    vec4 src = COMPAT_TEXTURE(u_tex, hbFlipV(v_tex));
    float intensity = clamp(raysIntensity, 0.0, 1.0);
    vec2 center = (raysCenter.x == 0.0 && raysCenter.y == 0.0) ? vec2(0.5, 0.0) : raysCenter;
    float density = (raysDensity <= 0.0) ? 16.0 : raysDensity;
    float sharp = (raysSharpness == 0.0) ? 2.0 : raysSharpness;
    float falloff = (raysFalloff == 0.0) ? 0.7 : raysFalloff;

    vec2 res = (textureSize.x > 0.0 && textureSize.y > 0.0) ? textureSize : vec2(1.0, 1.0);
    float aspect = res.x / max(res.y, 1.0);
    vec2 d = (v_tex - center) * vec2(aspect, 1.0);
    float r = length(d);
    float ang01 = atan(d.y, d.x) / 6.2831853 + 0.5 + uTime * raysRotation * 0.1;   // rotation lente

    float t = uTime;
    // Cœur des rayons (net).
    float rays = rayPattern(ang01, r, density, sharp, raysVariation, t, raysStyle);
    // Halo doux : même motif avec une netteté basse → enrobe les rayons d'une lueur.
    float glow = rayPattern(ang01, r, density, max(sharp * 0.35, 0.4), raysVariation, t, raysStyle);
    float fx = max(rays, glow * clamp(raysGlow, 0.0, 1.0));

    // Estompage avec la distance + fondu au centre (pas de singularité).
    float fade = pow(clamp(1.0 - r * falloff, 0.0, 1.0), 1.5) * smoothstep(0.0, 0.05, r);
    fx *= fade;

    vec3 col = mix(raysColorEdge.rgb, raysColor.rgb, fade);
    float gate = intensity * zoneMask(v_tex);

    if (raysOverlay == 1) {
        // Calque transparent additif (empilage).
        FragColor = vec4(col, clamp(fx * gate * 1.6, 0.0, 0.9)) * v_col;
    } else {
        // Additif. L'alpha porte les rayons → visibles aussi sur le transparent du calque.
        float energyA = clamp(fx * gate * 2.0, 0.0, 1.0);
        vec3 outc = src.rgb + col * fx * gate * 2.0;
        FragColor = vec4(outc, max(src.a, energyA)) * v_col;
    }
}
#endif
