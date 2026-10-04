// HyperBat Nuages (cartoon) — refonte from scratch (remplace les presets 6/12 des Particules).
// Demande Xavier : les nuages ne doivent PAS tourner sur eux-mêmes.
// Design cartoon (aplat type BD/Mario) :
//   • Un nuage = union de 5 lobes circulaires + base plate coupée → silhouette BD classique,
//     bord net anti-aliasé, aplat blanc, OMBRAGE plat sous le ventre + léger assombrissement
//     du bord (liseré).
//   • 1 à 3 COUCHES de profondeur (parallaxe) : les lointains sont plus petits, plus lents
//     et plus transparents.
//   • Mouvement : dérive horizontale PURE (vitesse signée) + flottement vertical sinusoïdal
//     doux. AUCUNE rotation (ni sur soi, ni d'orbite), aucun basculement.
//   • Forme, taille, hauteur et trous re-tirés par nuage (grille 1D jitterée par couche).
//   • Composition : les nuages OCCULTENT le fond (alpha), pas d'additif.
// Espace v_tex du projet : y+ vers le BAS. ⚠ pas de mots réservés ES, divisions gardées.
//   fpuffIntensity / fpuffDensity / fpuffSize / fpuffShade / fpuffColor / fpuffColorB
//   fpuffLayers / fpuffSpeed / fpuffBob

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

uniform COMPAT_PRECISION float fpuffIntensity;
uniform COMPAT_PRECISION float fpuffDensity;
uniform COMPAT_PRECISION float fpuffSize;
uniform COMPAT_PRECISION float fpuffShade;
uniform COMPAT_PRECISION vec4  fpuffColor;
uniform COMPAT_PRECISION vec4  fpuffColorB;
uniform COMPAT_PRECISION float fpuffLayers;
uniform COMPAT_PRECISION float fpuffSpeed;
uniform COMPAT_PRECISION float fpuffBob;

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

float sHash(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453123); }

// Silhouette BD : 5 lobes (2 corps + 1 dôme + 2 petits côtés) coupés par une base plate.
// q : coordonnées locales normalisées (y+ = bas), h : hash de forme (varie les rayons).
float cloudShape(vec2 q, float h) {
    float r1 = 0.42 * (0.90 + 0.20 * fract(h * 7.13));
    float r2 = 0.40 * (0.90 + 0.20 * fract(h * 3.71));
    float r3 = 0.55 * (0.90 + 0.20 * fract(h * 5.37));
    float r4 = 0.26 * (0.85 + 0.30 * fract(h * 9.19));
    float d = length(q - vec2(-0.48, 0.02)) - r1;
    d = min(d, length(q - vec2(0.48, 0.04)) - r2);
    d = min(d, length(q - vec2(0.0, -0.22)) - r3);
    d = min(d, length(q - vec2(-0.92, 0.16)) - r4);
    d = min(d, length(q - vec2(0.92, 0.18)) - r4 * 0.9);
    d = max(d, q.y - 0.34);                              // base plate (y+ = bas)
    return d;
}

void main(void) {
    vec4 src = COMPAT_TEXTURE(u_tex, hbFlipV(v_tex));
    vec2 res = (textureSize.x > 0.0 && textureSize.y > 0.0) ? textureSize : vec2(1.0, 1.0);
    float aspect = res.x / max(res.y, 1.0);
    vec2 uv = v_tex * vec2(aspect, 1.0);
    float mask = zoneMask(v_tex) * clamp(fpuffIntensity, 0.0, 1.0);

    float dens = (fpuffDensity <= 0.0) ? 6.0 : fpuffDensity;
    float sizeP = (fpuffSize <= 0.0) ? 0.16 : fpuffSize;
    float nl = (fpuffLayers < 1.0) ? 2.0 : floor(min(fpuffLayers, 3.0) + 0.5);
    float shadeAmt = clamp(fpuffShade, 0.0, 1.0);
    float bobAmt = clamp(fpuffBob, 0.0, 1.0);

    vec3 col = src.rgb;
    float accA = 0.0;

    // couches lointaines d'abord (li=0), proches par-dessus
    for (int li = 0; li < 3; li++) {
        float lf = float(li);
        if (lf >= nl) break;
        float depth = (nl <= 1.5) ? 1.0 : lf / max(nl - 1.0, 1.0);
        float scaleL = mix(0.55, 1.0, depth);            // lointain = plus petit
        float spdF = mix(0.35, 1.0, depth);              // lointain = plus lent
        float alphaF = mix(0.50, 0.96, depth);           // lointain = plus transparent
        float sL = sizeP * scaleL;
        float cellW = max(aspect / dens, sL * 1.35);
        // dérive horizontale pure, signée ; offset par couche pour désaligner les grilles
        float sx = uv.x + uTime * fpuffSpeed * 0.04 * spdF + sHash(vec2(lf, 4.2)) * 9.0;
        float ci = floor(sx / cellW);
        for (int n = -1; n <= 1; n++) {
            float cell = ci + float(n);
            vec2 seed = vec2(cell, lf * 13.7 + 2.0);
            if (sHash(seed + vec2(7.7, 0.0)) > 0.78) continue;      // trous dans la flotte
            float hy = sHash(seed + vec2(3.1, 0.0));
            float hs = sHash(seed + vec2(5.5, 0.0));
            float hx = sHash(seed + vec2(9.3, 0.0));
            float s = sL * (0.75 + 0.5 * hs);
            float cx = (cell + 0.5 + (hx - 0.5) * 0.4) * cellW;
            // flottement vertical doux — translation seule, jamais de rotation
            float cy = 0.14 + 0.72 * hy
                     + bobAmt * 0.018 * sin(uTime * (0.5 + 0.4 * hs) + hy * 41.0);
            vec2 q = vec2(sx - cx, uv.y - cy) / max(s, 1e-4);
            if (abs(q.x) > 1.6 || abs(q.y) > 1.2) continue;         // early-out
            float d = cloudShape(q, hs);
            float cov = 1.0 - smoothstep(-0.035, 0.035, d);         // bord net cartoon (AA)
            if (cov < 0.003) continue;
            // ombrage plat sous le ventre + liseré discret au bord
            float sh = smoothstep(-0.05, 0.28, q.y) * shadeAmt;
            float rim = smoothstep(-0.14, -0.02, d) * 0.10 * shadeAmt;
            vec3 cTop = fpuffColor.rgb;
            vec3 cSh  = fpuffColor.rgb * vec3(0.80, 0.85, 0.96) * fpuffColorB.rgb;
            vec3 cc = mix(cTop, cSh, clamp(sh, 0.0, 1.0)) * (1.0 - rim);
            float a = cov * alphaF * mask;
            col = mix(col, cc, a);
            accA = accA + a * (1.0 - accA);
        }
    }
    FragColor = vec4(col, max(src.a, accA)) * v_col;
}
#endif
