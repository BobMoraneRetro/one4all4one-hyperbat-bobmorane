// HyperBat Étoiles filantes — ciel nocturne RÉALISTE écrit from scratch.
// Conception (photo de ciel réel, pas cartoon) :
//   • Magnitudes en loi de puissance : beaucoup d'étoiles FAIBLES, très peu de brillantes,
//     sur 2 couches de profondeur (fines + brillantes) → aucun motif de grille visible.
//   • Couleurs de corps noir : bleu-blanc (chaudes, rares) → blanc → jaune → orange (froides),
//     désaturées comme à l'œil nu.
//   • Scintillation subtile et IRRÉGULIÈRE (2 fréquences non commensurables), plus visible
//     sur les étoiles brillantes ; pointes de diffraction seulement sur celles-ci.
//   • Voile galactique très léger (FBM en bande) pour la profondeur.
//   • Météores : rares et irréguliers (période aléatoire par cycle), direction ±10°,
//     traînée FINE à décroissance exponentielle, tête blanche chaude + halo, teinte verte
//     (magnésium) en milieu de traînée → chaude en queue, flare aléatoire en fin de course,
//     puis traînée persistante qui s'évanouit.
//   • Composition ADDITIVE : une lumière s'ajoute (invisible sur fond clair, comme en vrai).
// ⚠ pas de mots réservés ES. Uniforms inchangés (spec identique à la v1).
//   fstarIntensity / fstarDensity / fstarSize / fstarTwinkle / fstarSpike
//   fstarColor / fstarColorB / fstarRate / fstarSpeed / fstarLength / fstarAngle

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

uniform COMPAT_PRECISION float fstarIntensity;
uniform COMPAT_PRECISION float fstarDensity;
uniform COMPAT_PRECISION float fstarSize;
uniform COMPAT_PRECISION float fstarTwinkle;
uniform COMPAT_PRECISION float fstarSpike;
uniform COMPAT_PRECISION vec4  fstarColor;
uniform COMPAT_PRECISION vec4  fstarColorB;
uniform COMPAT_PRECISION float fstarRate;
uniform COMPAT_PRECISION float fstarSpeed;
uniform COMPAT_PRECISION float fstarLength;
uniform COMPAT_PRECISION float fstarAngle;

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
float sHash1(float n){ return fract(sin(n * 12.9898) * 43758.5453123); }
// exp(-e) borné : évite l'overflow mediump de l'exposant (grands e → 0 proprement).
float nexp(float e) { return exp(-min(e, 60.0)); }

// Bruit de valeur + FBM léger (3 octaves) pour le voile galactique.
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

// Couleur de corps noir approchée par température normalisée tn∈[0,1] (0 = froide/orange,
// 1 = chaude/bleu-blanc). Volontairement désaturée (vision nocturne).
vec3 starBlackbody(float tn) {
    vec3 cold = vec3(1.0, 0.72, 0.48);     // K/M : orange
    vec3 sun  = vec3(1.0, 0.94, 0.82);     // G   : jaune-blanc
    vec3 wht  = vec3(1.0, 1.0, 1.0);       // A/F : blanc
    vec3 hot  = vec3(0.72, 0.82, 1.0);     // O/B : bleu-blanc
    vec3 c = mix(cold, sun, smoothstep(0.0, 0.38, tn));
    c = mix(c, wht, smoothstep(0.38, 0.7, tn));
    c = mix(c, hot, smoothstep(0.7, 1.0, tn));
    return mix(vec3(dot(c, vec3(0.333))), c, 0.75);   // désaturation légère
}

// UNE couche d'étoiles : grille jitterée, magnitudes en loi de puissance, scintillation
// irrégulière. `layerScale` = finesse ; `layerAmp` = poids ; `allowSpike` = pointes autorisées.
vec3 starLayer(vec2 uv, float layerScale, float layerAmp, float allowSpike, float t) {
    vec3 acc = vec3(0.0);
    float px = fstarSize / 0.06;                        // 1.0 au défaut, échelle la taille
    vec2 guv = uv * layerScale;
    vec2 id = floor(guv);
    vec2 gv = fract(guv) - 0.5;
    for (int yy = -1; yy <= 1; yy++) {
        for (int xx = -1; xx <= 1; xx++) {
            vec2 o = vec2(float(xx), float(yy));
            vec2 cid = id + o;
            float hPos  = sHash(cid);
            float hMag  = sHash(cid + vec2(5.2, 1.3));
            float hTemp = sHash(cid + vec2(2.7, 9.1));
            float hPh   = sHash(cid + vec2(9.4, 3.8));
            if (sHash(cid + vec2(13.7, 4.2)) > 0.62) continue;      // ~62 % de cellules vides
            vec2 pos = o + vec2(hPos - 0.5, sHash(cid + vec2(1.1, 7.3)) - 0.5) * 0.9;
            vec2 p = gv - pos;
            float r2 = dot(p, p);
            if (r2 > 0.30) continue;                                 // early-out
            // Magnitude : loi de puissance → la plupart des étoiles sont FAIBLES.
            float mag = pow(hMag, 3.4);                              // 0..1, médiane ≈ 0.09
            // Scintillation : irrégulière (2 sinus non commensurables), surtout les brillantes.
            float ph = hPh * TAU;
            float sc1 = sin(t * 6.3 + ph) * 0.5 + sin(t * 14.7 + ph * 2.7) * 0.28;
            float tw = 1.0 + clamp(fstarTwinkle, 0.0, 1.0) * (0.25 + 0.55 * mag) * sc1;
            tw = max(tw, 0.25);
            // Cœur gaussien FIN (une étoile est un point) ; halo discret ∝ magnitude.
            float sigma = (0.012 + 0.035 * mag) * px;
            float core = nexp(r2 / max(2.0 * sigma * sigma, 1e-6));
            float halo = nexp(sqrt(r2) * 9.0) * 0.10 * mag;
            float lum = (core + halo) * (0.10 + 0.90 * mag) * tw;
            // Pointes de diffraction : SEULEMENT les plus brillantes, réglées par fstarSpike.
            float spikeGate = smoothstep(0.55, 0.9, mag) * clamp(fstarSpike, 0.0, 1.0) * allowSpike;
            if (spikeGate > 0.001) {
                float sLen = mix(30.0, 7.0, clamp(fstarSpike, 0.0, 1.0));
                float sx = nexp(abs(p.y) * 220.0 + abs(p.x) * sLen);
                float sy = nexp(abs(p.x) * 220.0 + abs(p.y) * sLen);
                lum += (sx + sy) * 0.35 * spikeGate * tw;
            }
            vec3 tint = mix(fstarColor.rgb, fstarColorB.rgb, hTemp);
            acc += starBlackbody(hTemp) * tint * lum * layerAmp;
        }
    }
    return acc;
}

// Météores réalistes : planification par cycle (période aléatoire), direction ±10°,
// traînée fine exponentielle, tête + flare, traînée persistante après extinction.
vec3 meteors(vec2 uv, float aspect, float t) {
    float rate = clamp(fstarRate, 0.0, 2.0);
    if (rate < 0.004) return vec3(0.0);
    vec3 acc = vec3(0.0);
    float spd = max(fstarSpeed, 0.2);
    vec2 ctr = vec2(0.5 * aspect, 0.5);
    float span = 0.85 * max(aspect, 1.0);
    for (int k = 0; k < 3; k++) {
        float fk = float(k);
        // période propre à chaque météore, re-jitterée à CHAQUE cycle → jamais métronome
        float basePer = (2.6 + sHash1(fk * 13.7) * 3.2) / rate;
        float tt = t / basePer + sHash1(fk * 3.1) * 7.0;
        float cyc = floor(tt);
        float ph = fract(tt);
        float seed  = sHash(vec2(cyc, fk * 7.7));
        float seed2 = sHash(vec2(cyc * 1.7, fk * 3.3));
        float seed3 = sHash(vec2(cyc * 3.9, fk * 5.1));
        // fenêtre de vol courte au début du cycle (vol réel ~0.4-1 s) ; le reste = ciel calme
        float flight = clamp(0.14 * (0.7 + seed * 0.6) / spd, 0.02, 0.55);
        float p = ph / flight;                       // 0..1 pendant le vol, >1 = éteint
        if (p > 2.2) continue;                       // (fenêtre du train persistant incluse)
        // direction : angle de base ± ~10°, par météore et par cycle
        float ang = fstarAngle * TAU / 360.0 + (seed - 0.5) * 0.36;
        vec2 dir = vec2(cos(ang), sin(ang));
        vec2 perp = vec2(-dir.y, dir.x);
        // trajectoire : entre AVANT l'écran, traverse selon `dir`, décalage latéral aléatoire
        vec2 start = ctr + perp * (seed2 - 0.5) * 1.7 * span - dir * span * 1.15;
        float travel = span * 2.3;
        vec2 head = start + dir * min(p, 1.0) * travel;
        vec2 rel = uv - head;
        float x = dot(rel, -dir);                    // distance derrière la tête
        float y = dot(rel, perp);                    // écart latéral
        if (x < -0.03) continue;                     // devant la tête : rien
        float len = fstarLength * (0.7 + seed3 * 0.7);
        // traînée FINE : gaussienne latérale serrée × décroissance exponentielle vers l'arrière
        float sigma = 0.0016 + 0.0012 * seed3;
        float lat = nexp(y * y / (2.0 * sigma * sigma));
        float along = step(0.0, x) * nexp(x / max(len * 0.38, 1e-4));
        // fenêtres temporelles : allumage bref, extinction, puis train persistant qui s'efface
        float ignite = smoothstep(0.0, 0.06, p);
        float alive  = ignite * (1.0 - smoothstep(0.92, 1.0, p));
        float train  = (p > 1.0) ? nexp((p - 1.0) * 3.2) * 0.30 : 0.0;
        // flare aléatoire en fin de course (fragmentation) sur ~1 météore sur 2
        // (carré à la main : pow(négatif, 2.0) est indéfini en GLSL ES)
        float fx = (p - 0.78) / 0.07;
        float flare = 1.0 + step(0.5, seed2) * 1.3 * nexp(fx * fx);
        // tête : cœur blanc chaud + petit halo
        float r2h = dot(rel, rel);
        float headCore = nexp(r2h / 9e-6) * 2.2 + nexp(r2h / 2.5e-4) * 0.35;
        // couleur le long de la traînée : blanc-bleu (tête) → vert magnésium → chaud (queue)
        float u = clamp(x / max(len, 1e-4), 0.0, 1.0);
        vec3 trailCol = mix(vec3(0.92, 0.97, 1.05), vec3(0.72, 1.0, 0.86), smoothstep(0.08, 0.45, u));
        trailCol = mix(trailCol, vec3(1.0, 0.78, 0.55), smoothstep(0.55, 1.0, u));
        vec3 m = trailCol * lat * along * (alive * flare + train)
               + vec3(1.0, 0.98, 0.94) * headCore * alive * flare;
        acc += m * fstarColor.rgb;
    }
    return acc;
}

void main(void) {
    vec4 src = COMPAT_TEXTURE(u_tex, hbFlipV(v_tex));
    float intensity = clamp(fstarIntensity, 0.0, 1.0);

    vec2 res = (textureSize.x > 0.0 && textureSize.y > 0.0) ? textureSize : vec2(1.0, 1.0);
    float aspect = res.x / max(res.y, 1.0);
    vec2 uv = v_tex * vec2(aspect, 1.0);
    float density = (fstarDensity <= 0.0) ? 12.0 : fstarDensity;

    // ciel : 2 couches d'étoiles (fines nombreuses + brillantes rares)
    vec3 light = starLayer(uv, density * 2.1, 0.55, 0.0, uTime);   // fond fin, sans pointes
    light += starLayer(uv, density, 1.0, 1.0, uTime + 37.0);        // couche principale
    // voile galactique très léger, en bande diagonale fixe (carré manuel : dot peut être négatif)
    float bd = dot(uv - vec2(0.5 * aspect, 0.5), normalize(vec2(-0.45, 1.0)));
    float band = nexp(bd * bd * 5.5);
    light += fbm3(uv * 2.4) * band * 0.045 * vec3(0.62, 0.70, 0.92) * fstarColorB.rgb;
    // météores par-dessus
    light += meteors(uv, aspect, uTime);

    light *= intensity * zoneMask(v_tex);
    // Composition ADDITIVE douce (une lumière s'ajoute ; soft-clamp anti-écrêtage)
    vec3 outc = 1.0 - (1.0 - src.rgb) * (1.0 - clamp(light, 0.0, 1.0));
    float lum = clamp(max(max(light.r, light.g), light.b), 0.0, 1.0);
    FragColor = vec4(outc, max(src.a, lum)) * v_col;
}
#endif
