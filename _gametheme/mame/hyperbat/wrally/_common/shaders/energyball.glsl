// HyperBat Energy Ball — boule d'énergie procédurale (DBZ / Saint Seiya / jeux vidéo).
// Cœur plasma turbulent + lueur colorée + éclairs (arcs électriques crépitants) qui
// jaillissent autour de l'orbe. Additif sur l'image, placé à un centre. Animé via uTime.
// L'intensité (maître) module tout → 0 = image intacte. ⚠ pas de mots réservés ES 3.00.
//   ballIntensity  : intensité globale (maître, 0 = off)
//   ballCenter     : position de la boule (vec2 UV, clic gauche)
//   ballRadius     : taille du cœur
//   ballColor      : couleur du cœur
//   ballGlowColor  : couleur de la lueur (halo)
//   ballGlow       : rayon / portée de la lueur
//   ballLightning  : intensité des éclairs
//   ballTurbulence : agitation du plasma interne
//   ballSpeed      : vitesse d'animation

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

uniform COMPAT_PRECISION float ballIntensity;
uniform COMPAT_PRECISION vec2  ballCenter;
uniform COMPAT_PRECISION float ballRadius;
uniform COMPAT_PRECISION vec4  ballColor;
uniform COMPAT_PRECISION vec4  ballGlowColor;
uniform COMPAT_PRECISION float ballOpacity;   // opacité du cœur (0 = translucide, 1 = plein)
uniform int ballCoreStyle;   // 0 = disque plein (alpha), 1 = lueur additive douce (ancien)
uniform COMPAT_PRECISION float ballGlow;
uniform COMPAT_PRECISION float ballLightning;
uniform int ballLightningMode;   // 0 arcs, 1 couronne, 2 filaments, 3 etincelles
uniform COMPAT_PRECISION float ballTurbulence;
uniform COMPAT_PRECISION float ballSpeed;

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

float ebHash(float n) { return fract(sin(n) * 43758.5453123); }
float ebNoise(vec2 p) {
    vec2 i = floor(p); vec2 f = fract(p);
    f = f * f * (3.0 - 2.0 * f);
    float a = ebHash(dot(i, vec2(1.0, 57.0)));
    float b = ebHash(dot(i + vec2(1.0, 0.0), vec2(1.0, 57.0)));
    float c = ebHash(dot(i + vec2(0.0, 1.0), vec2(1.0, 57.0)));
    float d = ebHash(dot(i + vec2(1.0, 1.0), vec2(1.0, 57.0)));
    return mix(mix(a, b, f.x), mix(c, d, f.x), f.y);
}
float ebFbm(vec2 p) {
    float v = 0.0, amp = 0.5;
    for (int i = 0; i < 4; i++) { v += amp * ebNoise(p); p *= 2.0; amp *= 0.5; }
    return v;
}

// ── Éclairs, plusieurs styles ──────────────────────────────────────────────
// 0 — ARCS : quelques bolts jaillissant de l'orbe, jaggés et crépitants.
float ebArcs(vec2 p, float r, float radius, float t) {
    float a = atan(p.y, p.x);
    float acc = 0.0;
    for (int i = 0; i < 4; i++) {
        float seed = floor(t * 11.0) + float(i) * 23.0;     // saut discret = crépitement
        float ba = (ebHash(seed) * 2.0 - 1.0) * 3.14159265;  // angle du bolt
        float dl = atan(sin(a - ba), cos(a - ba));           // écart angulaire signé (wrap)
        float jag = (ebFbm(vec2(r * 13.0, seed * 0.31)) - 0.5) * 0.6;  // serpentement
        float perp = (dl + jag) * r;
        float reach = radius * (1.6 + ebHash(seed + 5.0) * 1.6);
        float beam = smoothstep(0.028, 0.0, abs(perp));
        beam *= smoothstep(reach, radius, r) * step(r, reach);
        acc += beam * (0.55 + 0.45 * ebHash(seed + float(i)));
    }
    return acc;
}
// 1 — COURONNE : anneau électrique qui ondule et tourne autour de l'orbe.
float ebRing(vec2 p, float r, float radius, float t) {
    float a = atan(p.y, p.x);
    float ringR = radius * 1.5;
    float wob = (ebFbm(vec2(a * 3.0 + t * 1.5, t * 0.5)) - 0.5) * radius * 0.7;
    float band = smoothstep(0.035, 0.0, abs(r - ringR - wob));
    float crackle = 0.35 + 0.65 * ebNoise(vec2(a * 10.0 - t * 4.0, t * 6.0));
    return band * crackle;
}
// 2 — FILAMENTS : corona dense, fins filaments radiaux qui scintillent.
float ebFilaments(vec2 p, float r, float radius, float t) {
    float a = atan(p.y, p.x);
    float warp = (ebFbm(vec2(r * 8.0 - t * 2.0, a * 2.0)) - 0.5) * 0.8;
    float strands = abs(fract((a + warp) * (12.0 / 6.28318530718)) - 0.5);
    float fil = smoothstep(0.12, 0.0, strands);
    fil *= smoothstep(radius * 2.4, radius * 0.7, r) * step(radius * 0.6, r);
    fil *= 0.4 + 0.6 * ebNoise(vec2(a * 22.0, t * 8.0));
    return fil;
}
// 3 — ÉTINCELLES : petits éclats qui sautillent autour de l'orbe.
float ebSparks(vec2 p, float r, float radius, float t) {
    float acc = 0.0;
    for (int i = 0; i < 6; i++) {
        float fi = float(i);
        float seed = floor(t * 7.0 + fi * 13.0);
        float ang = ebHash(seed) * 6.28318530718;
        float rad = radius * (1.2 + ebHash(seed + 2.0) * 1.3);
        vec2 sp = vec2(cos(ang), sin(ang)) * rad;
        float d = length(p - sp);
        acc += smoothstep(0.025, 0.0, d) * (0.6 + 0.4 * ebHash(seed + fi));
    }
    return acc;
}
float ebLightning(vec2 p, float r, float radius, float t, int mode) {
    if (mode == 1) return ebRing(p, r, radius, t);
    if (mode == 2) return ebFilaments(p, r, radius, t);
    if (mode == 3) return ebSparks(p, r, radius, t);
    return ebArcs(p, r, radius, t);
}

void main(void) {
    vec4 src = COMPAT_TEXTURE(u_tex, hbFlipV(v_tex));
    float intensity = clamp(ballIntensity, 0.0, 1.0);
    vec2 center = (ballCenter.x == 0.0 && ballCenter.y == 0.0) ? vec2(0.5, 0.5) : ballCenter;
    float radius = (ballRadius == 0.0) ? 0.12 : ballRadius;
    float glowAmt = ballGlow;             // 0 = pas de lueur (plus de garde "0 = défaut")
    float lightAmt = ballLightning;       // 0 = pas d'éclairs
    float turb = ballTurbulence;          // 0 = cœur lisse
    float spd = ballSpeed;                // 0 = figé

    vec2 res = (textureSize.x > 0.0 && textureSize.y > 0.0) ? textureSize : vec2(1.0, 1.0);
    float aspect = res.x / max(res.y, 1.0);
    vec2 p = (v_tex - center) * vec2(aspect, 1.0);
    float r = length(p);
    float t = uTime * spd;
    float pulse = 0.85 + 0.15 * sin(t * 5.0);

    float pl = ebFbm(p * (7.0 / max(radius, 1e-3)) + vec2(t, -t * 0.7));
    float bright = (1.0 + (pl - 0.5) * turb) * pulse;   // turb 0 → pas de modulation

    // Lueur (halo) : décroissance douce au-delà du cœur.
    float glowExtent = radius * (1.0 + glowAmt * 5.0);
    float halo = exp(-r / max(glowExtent * 0.4, 1e-3)) * pulse;

    // Éclairs (style sélectionnable).
    float bolts = ebLightning(p, r, radius, t, ballLightningMode) * lightAmt;
    vec3 boltCol = mix(ballColor.rgb, vec3(1.0), 0.6) * bolts * 2.0;

    float opacity = clamp(ballOpacity, 0.0, 1.0);
    float gate = intensity * zoneMask(v_tex);
    vec3 col;
    float ballA = 0.0;   // couverture PROPRE de la boule → reste visible sur le PNG transparent

    if (ballCoreStyle == 1) {
        // ── STYLE LUEUR : lueur additive (blob lumineux translucide), mais DENSE :
        // cœur plus plein (bord à 0.55) + courbe concentrée (pow) → moins diffus à 100 %.
        float soft = smoothstep(radius, radius * 0.55, r);
        soft = pow(soft, 0.55);
        vec3 energy = ballColor.rgb * soft * 2.4 * bright
                    + vec3(1.0) * pow(soft, 3.0) * bright * 0.5   // cœur blanc-chaud concentré
                    + ballGlowColor.rgb * halo * glowAmt * 1.6
                    + boltCol;
        vec3 contrib = energy * gate * opacity;
        col = src.rgb + contrib;
        ballA = clamp(max(max(contrib.r, contrib.g), contrib.b), 0.0, 1.0);
    } else {
        // ── NOUVEAU STYLE : disque PLEIN (opaque sur tout le rayon, bord doux ~18 %).
        // La FORME pilote l'alpha (indépendante du plasma) → vraie boule pleine à 100 %.
        float coreShape = smoothstep(radius, radius * 0.82, r);
        float hotspot   = smoothstep(radius * 0.55, 0.0, r);   // point blanc-chaud central
        float coreA = clamp(coreShape * opacity * gate, 0.0, 1.0);
        vec3 coreCol = ballColor.rgb * (0.9 + 0.6 * coreShape) * bright;
        col = mix(src.rgb, coreCol, coreA);
        // Aura émissive (lueur + éclairs + point chaud), décroît avec l'opacité.
        vec3 aura = ballGlowColor.rgb * halo * glowAmt * 1.6
                  + boltCol
                  + vec3(1.0) * hotspot * bright * 0.7;
        vec3 auraC = aura * gate * (0.2 + 0.8 * opacity);
        col += auraC;
        ballA = clamp(coreA + max(max(auraC.r, auraC.g), auraC.b), 0.0, 1.0);
    }

    // Alpha de sortie = max(alpha du PNG, couverture de la boule) → la boule s'affiche AUSSI
    // dans les zones transparentes du calque (à côté du perso), pas seulement sur le perso.
    // Sur les pixels opaques (src.a = 1) ça reste identique à avant : aucune régression.
    FragColor = vec4(col, max(src.a, ballA)) * v_col;
}
#endif
