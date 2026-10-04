// HyperBat Particles — système de particules procédural UNIFIÉ, façon "pétales" mais
// avec un PRESET au choix et un modèle de MOUVEMENT réglable. Grille de cellules + hash
// par cellule, voisinage 5×5, taille écran découplée du nombre (comme les pétales).
// Les explosions utilisent un moteur radial à part. ⚠ pas de mots réservés ES.
//   particlePreset : 0 Étoiles, 1 Étoiles 1, 2 Étoiles+filantes, 3 Étoiles Mario, 4 Bulles,
//                    5 Bulles 2, 6 Nuages 1, 7 Explosion 1, 8 Explosion 2, 9 Explosion 3,
//                    10 Flocon 1, 11 Flocon 2, 12 Nuages 2
//   particleMotion : 0 Auto(preset), 1 Chute, 2 Montée, 3 Flottement, 4 Statique, 5 Radial
//   particleCount/Size/Speed/Wind/Sway/Spin/Tumble + 2 couleurs = jeu commun à TOUS.

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

uniform int particlePreset;
uniform int particleMotion;
uniform COMPAT_PRECISION float particleIntensity;
uniform COMPAT_PRECISION float particleCount;
uniform COMPAT_PRECISION float particleSize;
uniform int particleScaleMode;
uniform COMPAT_PRECISION float particleScaleMin;
uniform COMPAT_PRECISION float particleScaleMax;
uniform COMPAT_PRECISION float particleScaleAnimMin;
uniform COMPAT_PRECISION float particleScaleAnimMax;
uniform COMPAT_PRECISION float particleSpeed;
uniform COMPAT_PRECISION float particleWind;
uniform COMPAT_PRECISION float particleSway;
uniform COMPAT_PRECISION float particleSpin;
uniform COMPAT_PRECISION float particleTumble;
uniform COMPAT_PRECISION float twinkle;
uniform COMPAT_PRECISION float uStarSpike;      // longueur des rayons/pointes des étoiles (0 court → 1 long)
uniform COMPAT_PRECISION vec4  particleColor;
uniform COMPAT_PRECISION vec4  particleColorB;
uniform COMPAT_PRECISION vec2  particleCenter;
uniform COMPAT_PRECISION float shootFreq;
uniform COMPAT_PRECISION float shootLength;
uniform COMPAT_PRECISION float burstLoop;
uniform COMPAT_PRECISION float burstSpread;
uniform COMPAT_PRECISION float burstCount;

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

#define TAU 6.2831853

float pHash(vec2 p)  { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453123); }
float pHash1(float n){ return fract(sin(n * 12.9898) * 43758.5453123); }

// Bruit de valeur + FBM (turbulence) pour les boules de feu / fumée.
float vnoise(vec2 p) {
    vec2 i = floor(p), f = fract(p);
    f = f * f * (3.0 - 2.0 * f);
    float a = pHash(i), b = pHash(i + vec2(1.0, 0.0));
    float c = pHash(i + vec2(0.0, 1.0)), d = pHash(i + vec2(1.0, 1.0));
    return mix(mix(a, b, f.x), mix(c, d, f.x), f.y);
}
float fbm(vec2 p) {
    float v = 0.0, amp = 0.5;
    for (int i = 0; i < 5; i++) { v += amp * vnoise(p); p *= 2.02; amp *= 0.5; }
    return v;
}
// Rampe de feu : 0 sombre/braise → rouge → orange → jaune → blanc incandescent.
vec3 fireRamp(float t) {
    t = clamp(t, 0.0, 1.0);
    vec3 c = mix(vec3(0.04, 0.0, 0.0), vec3(0.85, 0.06, 0.0), smoothstep(0.0, 0.35, t));
    c = mix(c, vec3(1.0, 0.5, 0.05), smoothstep(0.3, 0.6, t));
    c = mix(c, vec3(1.0, 0.85, 0.25), smoothstep(0.58, 0.82, t));
    c = mix(c, vec3(1.0, 1.0, 0.92), smoothstep(0.85, 1.0, t));
    return c;
}

// "Ball Of Fire" (Trisomie21, Shadertoy lsf3RH) : bruit pseudo-3D pour la boule de feu continue.
float snoise3(vec3 uv, float res) {
    const vec3 s = vec3(1e0, 1e2, 1e3);
    uv *= res;
    vec3 uv0 = floor(mod(uv, res)) * s;
    vec3 uv1 = floor(mod(uv + vec3(1.0), res)) * s;
    vec3 f = fract(uv); f = f * f * (3.0 - 2.0 * f);
    vec4 v = vec4(uv0.x + uv0.y + uv0.z, uv1.x + uv0.y + uv0.z,
                  uv0.x + uv1.y + uv0.z, uv1.x + uv1.y + uv0.z);
    vec4 r = fract(sin(v * 1e-1) * 1e3);
    float r0 = mix(mix(r.x, r.y, f.x), mix(r.z, r.w, f.x), f.y);
    r = fract(sin((v + uv1.z - uv0.z) * 1e-1) * 1e3);
    float r1 = mix(mix(r.x, r.y, f.x), mix(r.z, r.w, f.x), f.y);
    return mix(r0, r1, f.z) * 2.0 - 1.0;
}

// --- Formes & couleurs RÉALISTES par preset (q en repère unitaire ~[-1,1]) ---
vec3 hueWheel(float h) { return 0.5 + 0.5 * cos(TAU * (h + vec3(0.0, 0.33, 0.66))); }

float shpCloud(vec2 q) {
    float d = 1000.0;
    d = min(d, length(q - vec2(-0.55, -0.05)) - 0.5);
    d = min(d, length(q - vec2( 0.0,  0.18)) - 0.62);
    d = min(d, length(q - vec2( 0.55, -0.02)) - 0.46);
    d = min(d, length(q - vec2( 0.0, -0.28)) - 0.5);
    return smoothstep(0.05, -0.12, d);
}
float shpSnow(vec2 q) {                  // flocon 6 branches
    float a = atan(q.y, q.x + 1e-6);
    float r = length(q);
    float seg = TAU / 6.0;
    a = mod(a, seg) - seg * 0.5;
    vec2 u = vec2(cos(a), sin(a)) * r;
    float arm = smoothstep(0.09, 0.015, abs(u.y)) * smoothstep(1.0, 0.92, u.x) * step(0.0, u.x);
    float branch = smoothstep(0.05, 0.0, abs(abs(u.y) - (u.x - 0.45) * 0.55)) * smoothstep(0.9, 0.45, u.x) * step(0.42, u.x);
    float tip = smoothstep(0.16, 0.0, length(u - vec2(0.92, 0.0)));
    float core = smoothstep(0.18, 0.04, r);
    return clamp(max(max(max(arm, branch), tip), core * 0.85), 0.0, 1.0);
}
// Nuage cartoon HyperTheme : cumulus LARGE et PLAT (bosses en haut, base aplatie).
float shpCloudToon(vec2 q) {
    vec2 p = q * vec2(0.72, 1.45);          // élargit → plus large que haut
    float d = 1000.0;
    d = min(d, length(p - vec2(-0.72, 0.04)) - 0.42);
    d = min(d, length(p - vec2(-0.26, 0.22)) - 0.5);
    d = min(d, length(p - vec2( 0.3,  0.18)) - 0.48);
    d = min(d, length(p - vec2( 0.74, 0.0)) - 0.4);
    d = min(d, length(p - vec2( 0.0, -0.18)) - 0.56);   // corps
    float cov = smoothstep(0.06, -0.1, d);
    cov *= smoothstep(-0.98, -0.5, p.y);                // base aplatie
    return cov;
}
// Variante 2 : cumulus plus rond/haut (moins étalé).
float shpCloudToon2(vec2 q) {
    vec2 p = q * vec2(0.95, 1.1);
    float d = 1000.0;
    d = min(d, length(p - vec2(-0.5, 0.1)) - 0.46);
    d = min(d, length(p - vec2(-0.05, 0.32)) - 0.5);
    d = min(d, length(p - vec2( 0.42, 0.12)) - 0.46);
    d = min(d, length(p - vec2( 0.0, -0.12)) - 0.6);
    float cov = smoothstep(0.06, -0.1, d);
    cov *= smoothstep(-0.95, -0.45, p.y);
    return cov;
}

// Distance signée à une étoile 5 branches (iq) : r = rayon externe, rf = ratio creux/pointe.
float sdStar5(vec2 p, float r, float rf) {
    const vec2 k1 = vec2(0.809016994375, -0.587785252292);
    const vec2 k2 = vec2(-k1.x, k1.y);
    p.x = abs(p.x);
    p -= 2.0 * max(dot(k1, p), 0.0) * k1;
    p -= 2.0 * max(dot(k2, p), 0.0) * k2;
    p.x = abs(p.x);
    p.y -= r;
    vec2 ba = rf * vec2(-k1.y, k1.x) - vec2(0.0, 1.0);
    float hh = clamp(dot(p, ba) / dot(ba, ba), 0.0, r);
    return length(p - ba * hh) * sign(p.y * ba.x - p.x * ba.y);
}

// Œil de l'étoile Mario : pilule verticale NOIRE avec reflet chrome (bande argentée haut-centre
// + petit rebond bas). Renvoie (masque, intensité chrome : 0 = noir, 1 = argent).
vec2 marioEye(vec2 q, vec2 ctr, float sx, float sy) {
    vec2 r = q - ctr;
    float ex = r.x / sx, ey = r.y / sy;
    float dd = length(vec2(ex, ey)) - 1.0;
    float m  = smoothstep(0.09, -0.05, dd);
    float band = smoothstep(0.8, 0.0, abs(ex));               // colonne centrale
    float vert = smoothstep(-0.4, 0.55, ey);                  // plus fort en haut
    float hot  = smoothstep(0.7, 0.0, length(vec2(ex / 0.45, (ey - 0.45) / 0.5)));
    float chrome = clamp(band * vert * 0.85 + hot * 0.7, 0.0, 1.0);
    chrome = max(chrome, smoothstep(0.55, 0.0, abs(ex)) * smoothstep(-0.95, -0.6, ey) * 0.3);
    return vec2(m, chrome);
}

// Renvoie (rgb, couverture) réalistes du preset à la position q, teintés par `tint`.
vec4 particleShade(int preset, vec2 q, float h, float h2, vec3 tint) {
    float r = length(q);
    if (preset == 0 || preset == 2) {               // ÉTOILE RÉALISTE : point net, luminosité variée,
        // température de couleur (bleu → blanc → jaune/orange) ; les pointes de diffraction ne
        // sont visibles que sur les étoiles les plus brillantes (comme un vrai ciel).
        float bright = h2;                                        // luminosité propre de l'étoile
        float tight = mix(15.0, 5.0, bright);                     // faibles = points serrés
        float core = exp(-r * r * tight);
        float xf = mix(9.0, 1.3, clamp(uStarSpike, 0.0, 1.0));    // x-falloff : grand = rayon court
        float sx = exp(-abs(q.y) * 48.0) * exp(-abs(q.x) * xf);
        float sy = exp(-abs(q.x) * 48.0) * exp(-abs(q.y) * xf);
        float spike = (sx + sy) * smoothstep(0.5, 0.95, bright);  // pointes : étoiles brillantes seules
        float glow = exp(-r * 3.8) * 0.16 * bright;               // halo discret
        float cov = clamp(core + spike * 0.5 + glow, 0.0, 1.0);
        vec3 c = mix(vec3(0.62, 0.74, 1.0), vec3(1.0), smoothstep(0.0, 0.45, h));   // bleu-blanc → blanc
        c = mix(c, vec3(1.0, 0.85, 0.6), smoothstep(0.62, 1.0, h));                 // → jaune/orange
        return vec4(c * tint, cov);
    }
    if (preset == 3) {                              // ÉTOILE MARIO 3D (Power Star), d'après etoile.webp :
        // étoile GONFLÉE (volume) : hauteur tirée du SDF, normale via son gradient → chaque branche
        // devient un tube arrondi avec arête lumineuse + spéculaire ; yeux ovales noirs brillants.
        const float R = 0.82, RF = 0.47;
        float d = sdStar5(q, R, RF) - 0.06;                                          // silhouette dodue
        float body = smoothstep(0.03, -0.025, d);
        if (body < 0.003) return vec4(0.0);                                          // hors étoile : early-out
        // normale 3D : gradient du SDF (différences centrées) → galbe latéral DOUX des branches.
        float e = 0.03;
        float gx = sdStar5(q + vec2(e, 0.0), R, RF) - sdStar5(q - vec2(e, 0.0), R, RF);
        float gy = sdStar5(q + vec2(0.0, e), R, RF) - sdStar5(q - vec2(0.0, e), R, RF);
        vec2 gdir = normalize(vec2(gx, gy) + 1e-5);
        float z = sqrt(clamp(-d * 2.4, 0.0, 1.0));                                   // bombe au centre
        vec3 N = normalize(vec3(gdir * (1.0 - z) * 0.85, z + 0.30));
        vec3 L = normalize(vec3(-0.4, 0.5, 0.78));                                   // lumière haut-gauche
        float ndl = clamp(dot(N, L), 0.0, 1.0);
        float lit = 0.62 + 0.38 * ndl;                                              // ambient haut → reste bien jaune
        float spec = pow(ndl, 42.0);                                                 // reflet glossy serré
        float sheen = pow(ndl, 8.0);                                                 // voile large
        vec3 c = mix(vec3(0.95, 0.72, 0.02), vec3(1.0, 0.88, 0.06), lit);           // jaune vif ombré/éclairé
        c += sheen * vec3(1.0, 0.96, 0.45) * 0.22;
        c += spec * vec3(1.0, 1.0, 0.92) * 0.95;                                     // sheen glossy quasi-blanc
        float edgeDark = smoothstep(-0.05, 0.0, d) * smoothstep(0.02, -0.05, d);     // liseré gold au bord
        c = mix(c, vec3(0.72, 0.52, 0.0), 0.22 * edgeDark);
        vec2 eL = marioEye(q, vec2(-0.16, -0.03), 0.062, 0.185);                     // pilules noires + reflet chrome
        vec2 eR = marioEye(q, vec2( 0.16, -0.03), 0.062, 0.185);
        float em = clamp(eL.x + eR.x, 0.0, 1.0) * body;
        float chrome = (eL.x >= eR.x) ? eL.y : eR.y;                                 // reflet de l'œil courant
        c = mix(c, mix(vec3(0.03, 0.03, 0.04), vec3(0.95, 0.96, 0.99), chrome), em); // NOIR → argent (reflet)
        return vec4(c * tint, clamp(body, 0.0, 1.0));
    }
    if (preset == 4) {                              // BULLE DE SAVON irisée AVEC VOLUME : reprend
        // l'éclairage 3D de Bulles 2 (normale de sphère + lumière directionnelle) mais garde une
        // irisation DOUCE — les couleurs du contour sont fortement atténuées (était trop prononcé).
        float z = sqrt(max(1.0 - r * r, 0.0));
        vec3 N = vec3(q, z);                                       // normale de la sphère → relief
        vec3 L = normalize(vec3(-0.55, 0.6, 0.55));               // lumière haut-gauche
        float ndl = dot(N, L);
        float rim = smoothstep(0.94, 0.99, r) * (1.0 - smoothstep(1.0, 1.04, r));   // liseré fin
        float fres = pow(smoothstep(0.45, 1.0, r), 1.8);          // coquille de verre vers le bord
        float spec = pow(max(ndl, 0.0), 45.0) * 1.2;              // reflet spéculaire
        float soft = pow(max(ndl, 0.0), 6.0) * 0.16;
        float thru = smoothstep(0.62, 1.0, r) * pow(max(-ndl, 0.0), 1.5) * 0.4;     // lumière traversante
        float interior = smoothstep(1.0, 0.0, r) * 0.05;          // centre très transparent
        float disc = smoothstep(1.04, 0.97, r);                   // masque circulaire
        float cov = clamp(rim * 0.95 + fres * 0.28 + spec + soft + thru + interior, 0.0, 1.0) * disc;
        // irisation : film d'interférence, mais mélangé FAIBLEMENT (0.22) et seulement vers le bord.
        float ang = atan(q.y, q.x + 1e-6) / TAU + 0.5;
        vec3 irid = hueWheel(ang * 2.0 + r * 1.5 + h);
        vec3 base = mix(vec3(0.9, 0.93, 1.0), vec3(1.0), clamp(rim + spec + soft, 0.0, 1.0));
        vec3 c = mix(base, irid, fres * 0.22);                    // teinte irisée douce
        return vec4(c * tint, cov);
    }
    if (preset == 6) {                              // NUAGES 1 (HyperTheme) : cumulus plat large
        float cov = shpCloudToon(q);
        vec3 c = vec3(1.0) * (0.82 + 0.18 * smoothstep(-0.5, 0.5, q.y));
        return vec4(c * tint, cov);
    }
    if (preset == 10) {                              // FLOCON 1 (HyperTheme) : point neige DOUX
        float r = length(q);
        float cov = exp(-r * r * 5.0);              // blob gaussien doux
        return vec4(vec3(0.92, 0.96, 1.0) * tint, clamp(cov, 0.0, 1.0));
    }
    if (preset == 5) {                             // BULLES 2 : bulle de savon 3D (normale de
        // sphère + éclairage directionnel) → vrai relief : reflet spéculaire, liseré fresnel,
        // lumière traversante en bas, intérieur translucide.
        float r = length(q);
        float z = sqrt(max(1.0 - r * r, 0.0));
        vec3 N = vec3(q, z);                                       // normale de la sphère
        vec3 L = normalize(vec3(-0.55, 0.6, 0.55));               // lumière haut-gauche
        float ndl = dot(N, L);
        // RIM blanc FIN (~2px) tout au bord — le trait net de la bulle.
        float rim = smoothstep(0.94, 0.99, r) * (1.0 - smoothstep(1.0, 1.04, r));
        // DÉGRADÉ doux vers le bord (coquille de verre) → l'effet de bulle, reste transparent.
        float fres = pow(smoothstep(0.45, 1.0, r), 1.8);
        // reflet spéculaire (haut-gauche) + petit halo + lumière traversante (bas).
        float spec = pow(max(ndl, 0.0), 45.0) * 1.2;
        float soft = pow(max(ndl, 0.0), 6.0) * 0.16;
        float thru = smoothstep(0.62, 1.0, r) * pow(max(-ndl, 0.0), 1.5) * 0.4;
        float interior = smoothstep(1.0, 0.0, r) * 0.05;        // centre TRÈS transparent
        float disc = smoothstep(1.04, 0.97, r);                 // masque circulaire
        float cov = clamp(rim * 0.95 + fres * 0.28 + spec + soft + thru + interior, 0.0, 1.0) * disc;
        vec3 c = mix(vec3(0.9, 0.93, 1.0), vec3(1.0), clamp(rim + spec + soft, 0.0, 1.0));  // bord/reflets blancs
        return vec4(c * tint, cov);
    }
    if (preset == 1) {                             // ÉTOILES 1 (HyperTheme) : sparkle 4 branches
        float r = length(q);
        float core = exp(-r * r * 9.0);
        float xf = mix(7.0, 1.0, clamp(uStarSpike, 0.0, 1.0));    // x-falloff : grand = rayon court
        float sx = exp(-abs(q.y) * 30.0) * exp(-abs(q.x) * xf);
        float sy = exp(-abs(q.x) * 30.0) * exp(-abs(q.y) * xf);
        float glow = exp(-r * 2.6) * 0.22;
        float cov = clamp(core + (sx + sy) * 0.7 + glow, 0.0, 1.0);
        return vec4(vec3(1.0) * tint, cov);
    }
    if (preset == 12) {                             // NUAGES 2 (HyperTheme) : cumulus rond
        float cov = shpCloudToon2(q);
        vec3 c = vec3(1.0) * (0.82 + 0.18 * smoothstep(-0.5, 0.5, q.y));
        return vec4(c * tint, cov);
    }
    if (preset == 11) {                              // NEIGE ronde douce + petit éclat
        float cov = smoothstep(1.0, 0.0, r);
        float spark = exp(-r * r * 10.0) * 0.6;
        return vec4((vec3(0.9, 0.95, 1.0) + spark) * tint, clamp(cov * 0.85 + spark, 0.0, 1.0));
    }
    return vec4(vec3(1.0) * tint, smoothstep(1.0, 0.5, r));   // fallback disque
}

// Repère unitaire d'une particule : rotation sur soi + taille + basculement 3D.
vec2 xform(vec2 p, float rot, float sz, float fore) {
    float s = sin(rot), c = cos(rot);
    p = mat2(c, -s, s, c) * p;
    p /= max(sz, 1e-4);
    p.x /= max(fore, 0.06);
    return p;
}

int resolveMotion(int preset, int motion) {
    if (motion != 0) return motion;
    if (preset == 4 || preset == 5) return 2;                   // bulles montent
    if (preset == 6 || preset == 12) return 3;                   // nuages flottent
    if (preset == 10 || preset == 11) return 1;                    // flocons tombent
    return 4;                                                    // étoiles : statique
}

vec2 motionScroll(int mode, float t, float wind) {
    vec2 sc = vec2(wind * t, 0.0);
    if (mode == 1) sc.y -= t;                                    // chute
    else if (mode == 2) sc.y += t;                               // montée
    else if (mode == 3) { sc.x += 0.15 * sin(t * 0.7); sc.y += 0.1 * cos(t * 0.5); } // flottement
    return sc;                                                   // mode 4 statique = rien
}

// Étoiles filantes : quelques traînées rapides et rares qui traversent l'écran.
vec3 shootingStars(vec2 uv, float t, vec3 tint) {
    vec3 s = vec3(0.0);
    for (int k = 0; k < 4; k++) {
        float fk = float(k);
        float prog = fract(t * max(shootFreq, 0.01) * 0.12 + pHash1(fk * 7.3));
        vec2 start = vec2(pHash1(fk * 2.1) * 1.4 - 0.2, -0.15);
        vec2 dir = normalize(vec2(0.5, 0.85));
        vec2 head = start + dir * prog * 1.8;
        vec2 rel = uv - head;
        float perp = dot(rel, vec2(-dir.y, dir.x));
        float along = dot(rel, -dir);
        float trail = exp(-perp * perp * 900.0) * smoothstep(shootLength, 0.0, along) * step(0.0, along);
        float hd = exp(-dot(rel, rel) * 1200.0);
        float vis = smoothstep(0.0, 0.1, prog) * smoothstep(1.0, 0.8, prog);
        s += (tint * trail * 0.8 + vec3(1.0) * hd) * vis;
    }
    return s;
}

// UNE explosion (preset 4 ou 5) centrée en pe=0, à la phase `life`, taille `spread`. `seed`
// décale le bruit → chaque explosion du multi-spawn est unique. Renvoie (rgb, couverture).
vec4 renderExplosion(vec2 pe, float life, float spread, int preset, float seed) {
    vec2 so = vec2(seed * 31.7, seed * 17.3);
    float radius = mix(0.05, spread * 1.15, pow(life, 0.4));
    float rr = length(pe) / radius;
    vec2 fp = pe * (5.5 / spread);
    float n1 = fbm(fp + vec2(0.0, -uTime * 0.6) + so);
    float n2 = fbm(fp * 2.3 + vec2(uTime * 0.3, -uTime * 0.95) + so);
    float billow = 1.0 - abs(2.0 * n1 - 1.0);
    float turb = mix(n1, billow, 0.5) * 0.7 + n2 * 0.3;
    vec3 fire;
    float bodyAlpha = 0.0;
    if (preset == 7) {
        float d3 = fbm(fp * 4.1 - vec2(uTime * 0.5, uTime * 0.75) + so);
        float dens = turb * 0.8 + d3 * 0.2;
        float ball = smoothstep(1.25, 0.0, rr + (dens - 0.5) * 0.9);
        float temp = clamp(dens * 1.35 - rr * 0.6 - life * 0.45 + 0.18, 0.0, 1.0);
        fire = fireRamp(temp);
        fire += vec3(1.0, 0.8, 0.45) * exp(-rr * rr * 2.2) * smoothstep(0.6, 0.0, life) * 0.8;
        fire += vec3(1.0, 0.5, 0.18) * exp(-rr * rr * 2.4) * (1.0 - life) * 0.3;
        bodyAlpha = ball * (1.0 - smoothstep(0.45, 0.95, life));
    } else {
        float body = smoothstep(1.35, 0.05, rr + (turb - 0.5) * 1.0);
        float heat = clamp((1.4 - rr) - life * 0.55 + (turb - 0.5) * 0.6, 0.0, 1.0);
        fire = fireRamp(heat) * body;
        fire += vec3(1.0, 0.5, 0.18) * exp(-rr * rr * 2.4) * (1.0 - life) * 0.4;
    }
    float flash = exp(-rr * rr * 5.0) * smoothstep(0.45, 0.0, life);
    fire += vec3(1.0, 0.96, 0.86) * flash;
    bodyAlpha = max(bodyAlpha, flash);
    float sparkA = 0.0;
    for (int i = 0; i < 64; i++) {
        float fi = float(i) + seed * 53.0;
        float ang = pHash1(fi * 1.7) * TAU;
        float rh = pHash1(fi * 5.3);
        float srad = life * spread * (0.7 + 1.15 * rh);
        vec2 sp = vec2(cos(ang), sin(ang)) * srad;
        if (preset == 8) sp.y -= life * life * spread * 0.5;
        float sd = length(pe - sp);
        float ssz = 0.006 * (spread + 0.3) * (0.6 + 0.8 * pHash1(fi * 2.7));
        float spk = smoothstep(ssz, 0.0, sd) * (1.0 - life) * (0.5 + 0.5 * rh);
        fire += vec3(1.0, 0.85, 0.6) * spk;
        sparkA = max(sparkA, spk);
    }
    float smokeA;
    vec3 smokeCol;
    if (preset == 7) {
        float smokeRad = mix(0.2, spread * 1.7, pow(life, 0.5));
        vec2 pq = pe - vec2(0.0, -smokeRad * 0.2 * life);
        float sr = length(pq) / smokeRad;
        vec2 w1 = vec2(fbm(pe * 1.8 + vec2(uTime * 0.1, 1.0) + so),
                       fbm(pe * 1.8 + vec2(3.0, -uTime * 0.1) + so)) - 0.5;
        vec2 sps = pq + w1 * 0.28 * spread + vec2(0.0, -life * spread * 0.2);
        float dscale = 2.0 / spread;
        float bb = (1.0 - abs(2.0 * fbm(sps * dscale + so) - 1.0)) * 0.55
                 + (1.0 - abs(2.0 * fbm(sps * dscale * 2.0 + 7.0 + so) - 1.0)) * 0.45;
        float edgeN = fbm(sps * (2.6 / spread) + 20.0 + so);
        float rag = sr + (edgeN - 0.5) * 0.7;
        float ball = smoothstep(1.12, 0.0, rag);
        float dens = ball * (0.4 + 0.6 * smoothstep(0.3, 0.8, bb));
        float bbUp = (1.0 - abs(2.0 * fbm((sps + vec2(0.0, 0.05)) * dscale + so) - 1.0)) * 0.55
                   + (1.0 - abs(2.0 * fbm((sps + vec2(0.0, 0.05)) * dscale * 2.0 + 7.0 + so) - 1.0)) * 0.45;
        float densUp = smoothstep(1.12, 0.0, sr + (edgeN - 0.5) * 0.7) * (0.4 + 0.6 * smoothstep(0.3, 0.8, bbUp));
        float shade = clamp(0.55 + (dens - densUp) * 2.3, 0.25, 1.15);
        vec3 base = mix(vec3(0.12, 0.115, 0.11), vec3(0.72, 0.69, 0.66), dens) * shade;
        base += vec3(0.5, 0.26, 0.08) * smoothstep(0.5, 0.0, sr) * dens * 0.28;
        smokeCol = base;
        float sFade = smoothstep(0.1, 0.35, life) * (1.0 - smoothstep(0.78, 1.0, life));
        smokeA = clamp(dens * 2.8, 0.0, 1.0) * sFade;
    } else {
        float smokeRad = mix(0.08, spread * 1.7, life);
        float sr = length(pe) / smokeRad;
        vec2 outFlow = normalize(pe + vec2(1e-4)) * life * 1.6;
        float sn = fbm(pe * (3.5 / spread) - outFlow + vec2(0.0, -uTime * 0.3) + so);
        float sDens = smoothstep(1.15, 0.1, sr + (sn - 0.5) * 0.85);
        float sFade = smoothstep(0.08, 0.3, life) * (1.0 - smoothstep(0.45, 1.0, life));
        smokeA = sDens * sFade * 0.8;
        smokeCol = mix(vec3(0.08, 0.07, 0.06), vec3(0.4, 0.38, 0.35), sn);
    }
    float fade = smoothstep(1.0, 0.85, life);
    fire *= fade * mix(particleColor.rgb, vec3(1.0), 0.5);
    float fc = (preset == 7)
        ? clamp(max(bodyAlpha, sparkA) * fade, 0.0, 1.0)
        : clamp(max(max(fire.r, fire.g), fire.b), 0.0, 1.0);
    vec3 col = mix(smokeCol, fire, fc);
    float cover = max(fc, smokeA * fade);
    return vec4(col, cover);
}

void main(void) {
    vec4 src = COMPAT_TEXTURE(u_tex, hbFlipV(v_tex));
    float intensity = clamp(particleIntensity, 0.0, 1.0);
    int preset = particlePreset;

    vec2 res = (textureSize.x > 0.0 && textureSize.y > 0.0) ? textureSize : vec2(1.0, 1.0);
    float aspect = res.x / max(res.y, 1.0);
    vec2 uv = v_tex * vec2(aspect, 1.0);
    float mask = zoneMask(v_tex);

    vec3 col = vec3(0.0);
    float cover = 0.0;

    if (preset == 7 || preset == 8) {
        // ----- EXPLOSIONS : une seule (au clic) ou MULTI-SPAWN aléatoire (façon HyperTheme) -----
        float loopT = max(burstLoop, 0.2);
        float spread0 = max(burstSpread, 0.05);
        float bn = clamp(burstCount, 1.0, 16.0);
        if (bn <= 1.5) {
            vec2 ctr = (particleCenter.x == 0.0 && particleCenter.y == 0.0) ? vec2(0.5, 0.4) : particleCenter;
            vec2 pe = (v_tex - ctr) * vec2(aspect, 1.0);
            vec4 ex = renderExplosion(pe, fract(uTime / loopT), spread0, preset, 0.0);
            col = ex.rgb; cover = ex.a;
        } else {
            // N "émetteurs" : chacun rejoue une explosion, mais à une NOUVELLE position/taille
            // ALÉATOIRE À CHAQUE CYCLE de respawn (le hasard dépend du n° de cycle) → ça pète
            // partout au fil du temps, comme l'émetteur ppm de HyperTheme (plus de spot figé).
            int N = int(bn + 0.5);
            for (int i = 0; i < 16; i++) {
                if (i >= N) break;
                float fi = float(i);
                float lp = loopT * (0.7 + pHash1(fi * 7.1) * 0.8);              // période propre (désynchro)
                float tt = uTime / lp + pHash1(fi * 3.3);
                float cyc = floor(tt);                                          // n° de respawn (incrémente)
                float life = fract(tt);
                float seed = pHash1(fi * 2.1 + cyc * 13.37);                    // re-tiré à CHAQUE cycle
                vec2 ec = vec2(pHash1(seed * 7.0 + 0.3), pHash1(seed * 11.0 + 1.1));  // NOUVELLE position
                // CHOIX : taille ALÉATOIRE par explosion, OU échelle ANIMÉE sur la vie.
                float esp = spread0 * ((particleScaleMode == 1)
                    ? mix(particleScaleAnimMin, particleScaleAnimMax, life)
                    : mix(particleScaleMin, particleScaleMax, pHash1(seed * 5.0)));
                vec2 pe = (v_tex - ec) * vec2(aspect, 1.0);
                if (length(pe) > esp * 2.4) continue;                           // gate perf : loin → skip
                vec4 ex = renderExplosion(pe, life, esp, preset, seed * 53.0);
                col = mix(col, ex.rgb, ex.a);
                cover = max(cover, ex.a);
            }
        }
    } else if (preset == 9) {
        // ----- BOULE DE FEU continue ("Ball Of Fire", Trisomie21) : bruit polaire multi-octave -----
        vec2 ctr = (particleCenter.x == 0.0 && particleCenter.y == 0.0) ? vec2(0.5, 0.5) : particleCenter;
        vec2 pbf = (v_tex - ctr) * vec2(aspect, 1.0) / max(burstSpread, 0.1);   // taille via "portee"
        float c = 3.0 - 3.0 * length(2.0 * pbf);
        vec3 cd = vec3(atan(pbf.x, pbf.y) / TAU + 0.5, length(pbf) * 0.4, 0.5);
        for (int i = 1; i <= 7; i++) {
            float power = pow(2.0, float(i));
            c += (1.5 / power) * snoise3(cd + vec3(0.0, -uTime * 0.05, uTime * 0.01), power * 16.0);
        }
        vec3 bof = vec3(c, pow(max(c, 0.0), 2.0) * 0.4, pow(max(c, 0.0), 3.0) * 0.15);
        col = bof * mix(particleColor.rgb, vec3(1.0), 0.5);     // teinte optionnelle
        cover = clamp(c, 0.0, 1.0);                             // transparent hors de la boule
    } else {
        // ----- moteur grille -----
        int motion = resolveMotion(preset, particleMotion);
        float count = max(particleCount, 1.0);
        float baseSize = (particleSize <= 0.0) ? 0.08 : particleSize;
        float speed = (particleSpeed == 0.0) ? 0.3 : particleSpeed;
        float t = uTime * speed;
        float sc = count;
        vec2 scroll = motionScroll(motion, t, particleWind);
        vec2 guv = uv * sc + scroll;
        vec2 id = floor(guv);
        vec2 gv = fract(guv) - 0.5;
        for (int yy = -2; yy <= 2; yy++) {
            for (int xx = -3; xx <= 3; xx++) {       // ±3 en X : laisse place au fort balancement
                vec2 o = vec2(float(xx), float(yy));
                vec2 cid = id + o;
                float h  = pHash(cid);
                float h2 = pHash(cid + vec2(5.2, 1.3));
                float h3 = pHash(cid + vec2(2.7, 9.1));
                float present = step(0.55, pHash(cid + vec2(13.7, 4.2)));
                vec2 pos = o + vec2((h - 0.5) * 0.7 + particleSway * 1.0 * sin(t * 1.3 + h * TAU),
                                    (h2 - 0.5) * 0.7);
                vec2 p = gv - pos;
                float spinDir = (h2 < 0.5) ? -1.0 : 1.0;
                float rate = (0.5 + h) * spinDir * particleSpin;
                float rot = uTime * rate + h * TAU;
                float flip = uTime * rate * 0.7 + h3 * TAU;
                float fore = mix(1.0, abs(cos(flip)), clamp(particleTumble, 0.0, 1.0));
                // CHOIX (comme HyperTheme) : taille ALÉATOIRE par particule, OU échelle ANIMÉE
                // (pulsation sinus). Le mode décide lequel s'applique.
                float sizeMul = (particleScaleMode == 1)
                    ? mix(particleScaleAnimMin, particleScaleAnimMax, 0.5 + 0.5 * sin(uTime * 0.6 + h * TAU))
                    : mix(particleScaleMin, particleScaleMax, h3);
                float sz = baseSize * sc * sizeMul;
                // Pas de basculement 3D pour les bulles (sphères : une sphère vue de tranche reste
                // un disque) NI pour les nuages → fore forcé à 1. La rotation sur soi reste active.
                bool noTumble = (preset == 4 || preset == 5 || preset == 6 || preset == 12);
                vec2 q = xform(p, rot, sz, noTumble ? 1.0 : fore);
                vec3 tint = mix(particleColor.rgb, particleColorB.rgb, h2);
                vec4 sh = particleShade(preset, q, h, h2, tint);
                float a = sh.a; vec3 pc = sh.rgb;
                float tw = (preset == 0 || preset == 2 || preset == 1)
                    ? mix(1.0, 0.35 + 0.65 * (0.5 + 0.5 * sin(uTime * 3.0 + h * TAU)), clamp(twinkle, 0.0, 1.0))
                    : 1.0;
                a *= present * (0.6 + 0.4 * h) * tw;
                col = mix(col, pc, clamp(a, 0.0, 1.0));
                cover = max(cover, a);
            }
        }
        if (preset == 2) {                                  // étoiles filantes par-dessus
            vec3 ss = shootingStars(uv, uTime, particleColor.rgb);
            col += ss;
            cover = max(cover, clamp(max(max(ss.r, ss.g), ss.b), 0.0, 1.0));
        }
        // La boucle a accumulé du PRÉMULTIPLIÉ (mix sur fond noir) ; le moteur attend de
        // l'alpha DROIT → on dé-prémultiplie, sinon les particules translucides (bulles) sont
        // assombries (centre gris-noir). Les particules opaques (cover≈1) ne changent pas.
        if (cover > 0.001) col /= cover;
    }

    float alpha = clamp(cover, 0.0, 1.0) * intensity * mask;
    // Composite alpha (le feu vif remplace, la fumée sombre assombrit le fond).
    vec3 outc = mix(src.rgb, col, alpha);
    FragColor = vec4(outc, max(src.a, alpha)) * v_col;
}
#endif
