// HyperBat Explosion 4 — explosion RÉALISTE écrite from scratch (aucun code des presets 1/2/3).
// Physique simulée (référence : films/documentaires, pas cartoon) :
//   • Flash initial sur-exposé (<0,1 s) qui éclaire brièvement la scène autour.
//   • Boule de feu en expansion Sedov-Taylor (R ∝ t^0.4) : violente au départ, puis freinée.
//     Refroidissement de corps noir : blanc → jaune → orange → rouge → braises sombres ;
//     volutes turbulentes (FBM advecté vers le haut) qui se chargent de SUIE en refroidissant
//     → le roulis noir/orange classique.
//   • Onde de choc : anneau de RÉFRACTION (le fond est réellement déformé), plus rapide que
//     la boule, à peine surligné.
//   • Étincelles balistiques : vitesse initiale + traînée aérodynamique + gravité (y+ = bas),
//     élongation selon la vitesse instantanée, scintillement de braise, refroidissement individuel.
//   • Fumée : champignon qui s'élève (buoyancy, tête + colonne discrète), éclairé de
//     l'intérieur tant que le feu vit, puis suie sombre qui OCCULTE le fond (alpha) et se dissipe.
//   • Chaque cycle re-tire position/taille/volutes/étincelles → deux explosions jamais identiques.
// Compo : fumée en alpha PUIS lumières en screen additif. Espace v_tex du projet : y+ vers le BAS.
// ⚠ pas de mots réservés ES, pas de pow(négatif), exposants d'exp bornés (nexp).
//   fboomIntensity / fboomCenter / fboomSize / fboomPeriod / fboomSpeed / fboomFlash
//   fboomTurbulence / fboomColor / fboomSmoke / fboomColorB / fboomSparks / fboomShockwave

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

uniform COMPAT_PRECISION float fboomIntensity;
uniform COMPAT_PRECISION vec2  fboomCenter;
uniform COMPAT_PRECISION float fboomSize;
uniform COMPAT_PRECISION float fboomPeriod;
uniform COMPAT_PRECISION float fboomSpeed;
uniform COMPAT_PRECISION float fboomFlash;
uniform COMPAT_PRECISION float fboomTurbulence;
uniform COMPAT_PRECISION vec4  fboomColor;
uniform COMPAT_PRECISION float fboomSmoke;
uniform COMPAT_PRECISION vec4  fboomColorB;
uniform COMPAT_PRECISION float fboomSparks;
uniform COMPAT_PRECISION float fboomShockwave;

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
float sHash(vec2 p)  { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453123); }
// exp(-e) borné : évite l'overflow mediump de l'exposant (grands e → 0 proprement).
float nexp(float e) { return exp(-min(e, 60.0)); }

// Bruit de valeur + FBM (3 octaves) pour les volutes de feu et de fumée.
float vnoise(vec2 p) {
    vec2 i = floor(p), f = fract(p);
    f = f * f * (3.0 - 2.0 * f);
    float a = sHash(i), b = sHash(i + vec2(1.0, 0.0));
    float c = sHash(i + vec2(0.0, 1.0)), d = sHash(i + vec2(1.0, 1.0));
    return mix(mix(a, b, f.x), mix(c, d, f.x), f.y);
}
float fbm3(vec2 p) {
    float v = 0.5 * vnoise(p);
    v += 0.25 * vnoise(p * 2.13 + 7.7);
    v += 0.125 * vnoise(p * 4.31 + 3.1);
    return v / 0.875;
}

// Corps noir d'un feu : braise sombre → rouge profond → orange → jaune → blanc.
// Légèrement > 1 en haut de rampe pour garder du punch après le screen-blend.
vec3 fireBlackbody(float t) {
    t = clamp(t, 0.0, 1.0);
    vec3 c = mix(vec3(0.02, 0.005, 0.0), vec3(0.45, 0.04, 0.005), smoothstep(0.0, 0.18, t));
    c = mix(c, vec3(1.0, 0.28, 0.02), smoothstep(0.18, 0.42, t));
    c = mix(c, vec3(1.0, 0.62, 0.10), smoothstep(0.42, 0.62, t));
    c = mix(c, vec3(1.05, 0.90, 0.45), smoothstep(0.62, 0.82, t));
    c = mix(c, vec3(1.10, 1.05, 0.98), smoothstep(0.82, 1.0, t));
    return c;
}

void main(void) {
    // ---------- horloge du cycle : ts = secondes écoulées depuis la détonation ----------
    float spd = (fboomSpeed <= 0.0) ? 1.0 : fboomSpeed;
    float per = (fboomPeriod <= 0.0) ? 5.0 : max(fboomPeriod, 0.5);
    float tt  = uTime / per;
    float cyc = floor(tt);
    float ts  = fract(tt) * per * spd;

    // seeds du cycle : chaque explosion est unique (position, taille, volutes, étincelles)
    float sA = sHash(vec2(cyc, 3.7));
    float sB = sHash(vec2(cyc, 8.1));
    float sC = sHash(vec2(cyc, 5.9));

    vec2 res = (textureSize.x > 0.0 && textureSize.y > 0.0) ? textureSize : vec2(1.0, 1.0);
    float aspect = res.x / max(res.y, 1.0);
    vec2 uv = v_tex * vec2(aspect, 1.0);
    vec2 ctr = (fboomCenter.x == 0.0 && fboomCenter.y == 0.0) ? vec2(0.5, 0.45) : fboomCenter;
    float size = ((fboomSize <= 0.0) ? 0.35 : fboomSize) * (0.82 + 0.36 * sA);
    vec2 c0 = vec2(ctr.x * aspect, ctr.y) + (vec2(sB, sC) - 0.5) * size * 0.16;

    float mask = zoneMask(v_tex) * clamp(fboomIntensity, 0.0, 1.0);
    float turb = clamp(fboomTurbulence, 0.0, 1.0);

    vec2 pc0 = uv - c0;
    float r0 = length(pc0);
    vec2 nrm = pc0 / max(r0, 1e-4);

    // ---------- onde de choc : anneau de réfraction plus rapide que la boule ----------
    float ringA = 0.0;
    float shock = clamp(fboomShockwave, 0.0, 1.0);
    if (shock > 0.001 && ts < 1.6) {
        float Rs = size * 2.6 * pow(max(ts, 1e-4) / 0.8, 0.62);
        float w = size * (0.05 + 0.16 * ts);
        float dd = (r0 - Rs) / max(w, 1e-4);
        ringA = nexp(dd * dd) * nexp(ts / 0.5) * shock;
    }
    vec2 refr = nrm * ringA * 0.030 * (size / 0.35) * mask;
    vec4 src = COMPAT_TEXTURE(u_tex, hbFlipV(v_tex + refr / vec2(aspect, 1.0)));

    vec3 light = vec3(0.0);

    // ---------- boule de feu : Sedov-Taylor + corps noir + suie croissante ----------
    float R = size * min(pow(max(ts, 1e-4) / 0.8, 0.4), 1.0);
    float nF = fbm3(pc0 * (3.2 / size) + vec2(cyc * 17.3, cyc * 9.1) + vec2(0.0, ts * 0.85));
    float cool = nexp(ts / 0.55);
    float edgeF = R * (1.0 + turb * (nF - 0.5) * 0.85);
    float dens = 1.0 - smoothstep(edgeF * 0.45, edgeF, r0);
    float fireEnv = nexp(max(ts - 0.75, 0.0) / 0.45);
    if (dens > 0.001 && fireEnv > 0.003) {
        // poches de suie : quasi absentes à chaud, envahissantes en refroidissant
        float sootM = turb * smoothstep(0.55 + 0.4 * cool, 0.98, nF);
        // température locale : cœur > bord, sur-blanc au tout début (boule optiquement épaisse)
        float tloc = clamp(cool * (0.42 + 0.75 * dens) * (1.0 - 0.8 * sootM)
                         + nexp(ts / 0.09) * 0.55, 0.0, 1.0);
        float fb = dens * (0.30 + 2.0 * cool) * fireEnv * (1.0 - 0.85 * sootM);
        light += fireBlackbody(tloc) * fb * fboomColor.rgb;
    }

    // ---------- flash initial : éclaire brièvement la scène ----------
    float flashAmp = clamp(fboomFlash, 0.0, 1.0);
    if (flashAmp > 0.001) {
        light += vec3(1.0, 0.96, 0.88) * nexp(ts / 0.05) * flashAmp * 2.4 * nexp(r0 / (size * 1.9));
    }

    // ---------- étincelles balistiques : drag aéro + gravité, élongation ∝ vitesse ----------
    float sparkN = clamp(fboomSparks, 0.0, 26.0);
    if (sparkN >= 1.0 && ts < 2.4) {
        for (int i = 0; i < 26; i++) {
            if (float(i) >= sparkN) break;
            float fi = float(i);
            float h1 = sHash(vec2(fi * 1.93, cyc * 1.17 + 4.2));
            float h2 = sHash(vec2(fi * 3.71, cyc * 2.31 + 8.8));
            float h3 = sHash(vec2(fi * 7.13, cyc * 0.57 + 1.9));
            float h4 = sHash(vec2(fi * 5.37, cyc * 3.73 + 6.1));
            float tf = ts - 0.02;
            if (tf <= 0.0) continue;
            float aA = h1 * TAU;
            vec2 dirS = vec2(cos(aA), sin(aA));
            float v0 = size * (2.2 + 3.0 * h2);          // vitesse initiale (unités/s)
            float tdrag = 0.32 + 0.30 * h3;              // constante de freinage aéro
            float g0 = 0.9 * (0.6 + 0.5 * h4);           // gravité (y+ = bas), indép. de la taille
            vec2 sp = c0 + dirS * v0 * tdrag * (1.0 - nexp(tf / tdrag))
                    + vec2(0.0, 0.5 * g0 * tf * tf);
            vec2 q = (uv - sp) / size;                   // coordonnées locales normalisées
            if (dot(q, q) > 0.09) continue;              // early-out
            vec2 vel = dirS * v0 * nexp(tf / tdrag) + vec2(0.0, g0 * tf);
            float vn = length(vel) / size;
            vec2 vd = vel / max(length(vel), 1e-4);
            float lon = dot(q, vd), lat = dot(q, vec2(-vd.y, vd.x));
            float sw = 0.006 * (0.7 + 0.6 * h4);
            float sl = min(sw * (1.0 + vn * 3.0), 0.12); // braise étirée par la vitesse
            float body = nexp(lat * lat / (2.0 * sw * sw + 1e-5) + lon * lon / (2.0 * sl * sl + 1e-5));
            float life = 0.4 + 0.7 * h3;
            float fade = nexp(tf / life) * (1.0 - smoothstep(life * 1.6, life * 2.2, tf));
            float flick = 0.72 + 0.28 * sin(tf * (34.0 + 26.0 * h2) + h1 * TAU);
            float emberT = clamp(0.75 * nexp(tf / 0.8) + 0.10, 0.0, 1.0);
            light += fireBlackbody(emberT) * body * fade * flick * 1.7 * fboomColor.rgb;
        }
    }

    // léger surlignage de l'onde de choc (la réfraction fait l'essentiel)
    light += vec3(0.9, 0.95, 1.0) * ringA * 0.10;

    // ---------- fumée : champignon buoyant qui occulte puis se dissipe ----------
    float smkAmp = clamp(fboomSmoke, 0.0, 1.0);
    float smkA = 0.0;
    vec3 smkCol = vec3(0.0);
    if (smkAmp > 0.001) {
        float rise = size * (0.20 * ts + 0.034 * ts * ts);          // montée accélérée (buoyancy)
        vec2 cS = c0 + vec2((sB - 0.5) * 0.05 * ts, -rise);
        float Rk = size * (0.5 + 0.55 * pow(max(ts, 1e-4) / 1.4, 0.4));
        vec2 phS = uv - cS;
        // volutes : FBM domain-warpé, advecté vers le haut
        float w1 = fbm3(phS * (2.0 / size) + vec2(cyc * 23.1, ts * 0.5));
        float nS = fbm3(phS * (2.6 / size) + vec2(w1 * 1.4, cyc * 11.7 + ts * 0.35));
        float rS = length(phS);
        float edgeS = Rk * (0.72 + 0.56 * (nS - 0.3) * (0.4 + 0.6 * turb));
        float dS = 1.0 - smoothstep(edgeS * 0.35, edgeS, rS);
        // colonne discrète entre l'origine et la tête (silhouette champignon)
        float colW = max(Rk * 0.34, 1e-3);
        float below = smoothstep(cS.y, cS.y + rise + size * 0.2, uv.y);
        float dCol = nexp(pc0.x * pc0.x / (2.0 * colW * colW + 1e-5)) * below
                   * (1.0 - smoothstep(c0.y + size * 0.25, c0.y + size * 0.45, uv.y))
                   * smoothstep(0.9, 1.6, ts) * 0.55 * (0.4 + 0.6 * nS);
        float dSm = max(dS, dCol);
        // n'apparaît que quand le feu décline, puis se dissipe
        float envS = smoothstep(0.22, 0.9, ts) * nexp(max(ts - 2.4, 0.0) / 1.5);
        smkA = smkAmp * dSm * envS * mask;
        // éclairée de l'intérieur au début (feu résiduel), puis suie neutre en volutes
        float lit = clamp(nexp(ts / 0.8) * 1.3 * dS, 0.0, 0.85);
        vec3 soot = vec3(0.13, 0.125, 0.12) * (0.6 + 0.8 * nS);
        smkCol = mix(soot, fireBlackbody(0.32) * 0.8, lit) * fboomColorB.rgb;
    }

    // ---------- composition : fumée (alpha) puis lumières (screen additif) ----------
    smkA = clamp(smkA, 0.0, 0.92);
    vec3 baseC = mix(src.rgb, smkCol, smkA);
    vec3 lightC = clamp(light * mask, 0.0, 1.0);
    vec3 outc = 1.0 - (1.0 - baseC) * (1.0 - lightC);
    float lum = max(max(lightC.r, lightC.g), lightC.b);
    FragColor = vec4(outc, max(src.a, max(smkA, lum))) * v_col;
}
#endif
