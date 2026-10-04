// HyperBat Pétales — pétales de CERISIER DU JAPON (sakura) et de ROSE, réalistes. v3.
// Retours Xavier : sakura VALIDÉ (forme, teintes, chute) — ne pas y toucher ; le
// retournement faisait un aller-retour (mise à plat) au lieu d'un vrai 360° ; les roses
// (rendu + chute) à retravailler.
//   • RETOURNEMENT 360° VRAI : largeur = |cos| MAIS la face ARRIÈRE est visible quand
//     cos < 0 (miroir horizontal + dos plus clair — le dos d'un pétale de rose est
//     nettement plus pâle, celui du sakura à peine). Rotation continue, plus de ping-pong.
//     petalSpin (« Voltige ») règle la VITESSE des retournements (0 = à plat).
//   • ROSES sur leur PROPRE grille : chute « feuille morte » — plus rapide (plus lourdes),
//     glisse latérale AMPLE et lente, inclinaison qui suit la glisse, retournements lents
//     et majestueux, moins sensibles au vent.
//   • Pétale de rose redessiné : éventail plus large au froissé marqué (bord extérieur),
//     creux au sommet, PLI DU BORD ROULÉ (bande claire en parabole), fort dégradé velours
//     (base très sombre → liseré clair), stries radiales, reflet satiné bombé.
//   • Sakura : obovale asymétrique + encoche variable, pointe quasi blanche → base magenta,
//     stries longitudinales, balancement pendulaire + rebond de portance (inchangé).
//   • FEUILLE (automne, demande Xavier avec captures) : feuille d'érable stylisée (lobes
//     pointus polaires + serrations + pétiole brun), face en dégradé radial ambre → orange
//     (variation rouge/jaune par feuille), DOS BRUN SOMBRE. Mouvement signature : elle
//     BASCULE, revient, bascule… puis SE RETOURNE (rock sinusoïdal + demi-tours π
//     périodiques lissés). Teinte via petalColorC (blanc = naturel).
//   • Bords translucides ; 2 couches de profondeur ;
//     petalType 0 Cerisier / 1 Rose / 2 Mélange (cerisier+rose) / 3 Feuille (automne).
// Espace v_tex du projet : y+ vers le BAS (chute = +y ⇒ scroll.y -= t, conv. particles).
// ⚠ pas de mots réservés ES, divisions gardées. Uniforms compat thèmes (+ petalColorC).

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

uniform COMPAT_PRECISION float petalIntensity;
uniform int petalType;
uniform COMPAT_PRECISION float petalCount;
uniform COMPAT_PRECISION float petalSize;
uniform COMPAT_PRECISION float petalSpeed;
uniform COMPAT_PRECISION float petalWind;
uniform COMPAT_PRECISION float petalSway;
uniform COMPAT_PRECISION float petalSpin;
uniform COMPAT_PRECISION vec4  petalColor;
uniform COMPAT_PRECISION vec4  petalColorB;
uniform COMPAT_PRECISION vec4  petalColorC;

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
float sHash(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453123); }
float nexp(float e) { return exp(-min(e, 60.0)); }

// Pétale de cerisier : OBOVALE (plus large vers la pointe y-), encoche en V variable,
// asymétrie par pétale. Approx SDF suffisante pour un bord anti-aliasé. (VALIDÉ — ne pas toucher.)
float sdSakura(vec2 q, float h) {
    q.x += q.y * (h - 0.5) * 0.25;                       // cisaillement (asymétrie)
    q.y *= 0.92 + 0.18 * fract(h * 5.3);                 // élancement variable
    float w = 0.30 + 0.14 * smoothstep(0.45, -0.30, q.y);// obovale : large vers la pointe
    float d = (length(vec2(q.x / max(w, 1e-3), q.y / 0.50)) - 1.0) * 0.30;
    float nw = 0.09 + 0.07 * fract(h * 7.7);             // encoche : profondeur variable
    float notch = (length((q - vec2(0.0, -0.52)) / vec2(nw, 0.18)) - 1.0) * nw;
    return max(d, -notch);
}

// Pétale de rose v3 : éventail large, froissé marqué sur le bord extérieur (haut),
// creux au sommet (cœur), fortement pincé vers la base.
float sdRose(vec2 q, float h) {
    q.x += q.y * (h - 0.5) * 0.18;                       // asymétrie
    float a = atan(q.x, -q.y);
    float d = (length(q / vec2(0.50, 0.38)) - 1.0) * 0.38;
    float ruf = 0.022 * sin(a * 5.0 + h * TAU) + 0.012 * sin(a * 9.0 + h * 9.7);
    d += ruf * smoothstep(0.35, -0.15, q.y);             // froissé surtout en haut
    float dip = (length((q - vec2(0.0, -0.44)) / vec2(0.10, 0.09)) - 1.0) * 0.09;
    d = max(d, -dip);                                    // creux au sommet
    d = max(d, abs(q.x) - (0.60 - 0.62 * q.y));          // pincement vers la base
    return d;
}

// VRAIE feuille d'érable (réf. photo Xavier) : un CORPS LARGE ET PLEIN dont les lobes
// partagent la surface — l'inverse des « doigts » fins (type cannabis). Construction :
// enveloppe large − SINUS étroits entaillés + pointes de lobes + dentelures + base cordée.
// Pointe vers y-, pétiole y+.
float sdLeafBody(vec2 q, float h) {
    q.x += q.y * (h - 0.5) * 0.10;                       // asymétrie légère
    vec2 b = q - vec2(0.0, 0.03);
    float a = atan(b.x, -b.y);                           // 0 = pointe
    float aa = abs(a);
    // corps large qui se resserre vers la base (silhouette validée en préview offline v5)
    float R = mix(0.40, 0.18, smoothstep(1.6, 2.6, aa));
    // sinus profonds et étroits entre les lobes — le corps reste plein
    R -= 0.20 * nexp((aa - 0.45) * (aa - 0.45) / 0.005);
    R -= 0.20 * nexp((aa - 1.18) * (aa - 1.18) / 0.006);
    R -= 0.13 * nexp((aa - 1.95) * (aa - 1.95) / 0.010);
    // pointes ACÉRÉES : exponentielle de |écart| → cusp — 5 lobes SEULEMENT
    // (la paire basale supplémentaire lisait comme « une branche en trop »)
    R += 0.10 * nexp(aa / 0.045);
    R += 0.08 * nexp(abs(aa - 0.80) / 0.045);
    R += 0.07 * nexp(abs(aa - 1.55) / 0.05);
    // échancrure discrète à la base (cordée) + dentelures marquées sur les lobes
    R -= 0.05 * nexp((aa - 3.14159) * (aa - 3.14159) / 0.02);
    R += 0.024 * pow(abs(cos(a * 14.0 + h * 3.0)), 0.35) * smoothstep(2.5, 1.9, aa);
    R *= 0.94 + 0.12 * fract(h * 3.7);                   // gabarit par feuille
    return length(b) - R;
}
// Pétiole : fin, COURT et rattaché à la base de la feuille.
float sdLeafStem(vec2 q) {
    return max(abs(q.x) - 0.016, abs(q.y - 0.31) - 0.17);
}

void main(void) {
    vec4 src = COMPAT_TEXTURE(u_tex, hbFlipV(v_tex));
    vec2 res = (textureSize.x > 0.0 && textureSize.y > 0.0) ? textureSize : vec2(1.0, 1.0);
    float aspect = res.x / max(res.y, 1.0);
    vec2 uv = v_tex * vec2(aspect, 1.0);
    float mask = zoneMask(v_tex) * clamp(petalIntensity, 0.0, 1.0);

    float dens = (petalCount <= 0.0) ? 12.0 : petalCount;
    float sizeP = (petalSize <= 0.0) ? 0.05 : petalSize;
    float fall = (petalSpeed <= 0.0) ? 0.3 : petalSpeed;
    float swayA = clamp(petalSway, 0.0, 2.0) * 0.5;      // 0..1
    float flut = clamp(petalSpin, 0.0, 3.0) / 1.5;       // vitesse de voltige (0 = à plat)
    float flut1 = min(flut, 1.0);
    // l'espacement ne descend jamais sous la taille du pétale (grandes tailles)
    float scg = min(dens, 0.83 / sizeP);
    float t = uTime;

    vec3 col = src.rgb;
    float accA = 0.0;

    // 2 couches (lointaine puis proche) × 2 essences (chacune SA grille et SA chute)
    for (int li = 0; li < 2; li++) {
        float lf = float(li);
        float scaleL = mix(0.62, 1.0, lf);
        float spdL = mix(0.65, 1.0, lf);
        float alphaL = mix(0.50, 0.95, lf);
        for (int pe = 0; pe < 3; pe++) {
            // sélection : 0 Cerisier / 1 Rose / 2 Mélange (cerisier+rose) / 3 Feuille
            if (petalType == 0 && pe != 0) continue;
            if (petalType == 1 && pe != 1) continue;
            if (petalType == 2 && pe == 2) continue;
            if (petalType == 3 && pe != 2) continue;
            float pf = float(pe);
            // réglages par essence : cerisier / rose / feuille
            float fallM = (pe == 0) ? 1.0  : (pe == 1) ? 1.35 : 1.10;
            float windM = (pe == 0) ? 1.0  : (pe == 1) ? 0.7  : 0.85;
            float wSM   = (pe == 0) ? 1.0  : (pe == 1) ? 0.55 : 0.70;
            float swayM = (pe == 0) ? 0.30 : (pe == 1) ? 0.42 : 0.40;
            float bobM  = (pe == 0) ? 1.0  : (pe == 1) ? 0.7  : 0.8;
            float sizeM = (pe == 0) ? 0.85 : (pe == 1) ? 1.30 : 1.70;
            float tiltM = (pe == 0) ? 0.5  : (pe == 1) ? 0.8  : 0.7;
            float opE   = (pe == 0) ? 0.90 : (pe == 1) ? 0.97 : 0.99;
            // en Mélange, densité répartie (~60 % sakura / 40 % roses)
            float fillP = (petalType == 2) ? ((pe == 0) ? 0.40 : 0.25) : 0.62;
            float fallE = fall * fallM;
            vec2 scroll = vec2(petalWind * t * 0.35 * windM, -t * fallE * 1.5) * spdL;
            vec2 guv = uv * scg + scroll + vec2(lf * 37.0 + pf * 61.0, lf * 19.0 + pf * 11.0);
            vec2 id = floor(guv);
            for (int yy = -1; yy <= 1; yy++) {
                for (int xx = -1; xx <= 1; xx++) {
                    vec2 cid = id + vec2(float(xx), float(yy));
                    vec2 seed = cid + vec2(lf * 53.0 + pf * 91.0, 0.0);
                    if (sHash(seed + vec2(11.3, 7.1)) > fillP) continue;
                    float h1 = sHash(seed + vec2(1.7, 9.2));             // position/phase
                    float h2 = sHash(seed + vec2(5.9, 2.4));             // forme/teinte
                    float h3 = sHash(seed + vec2(8.3, 4.6));             // rythme voltige
                    // balancement : sakura pendule vif ; rose/feuille glisse AMPLE et lente
                    float wS = (1.1 + 0.8 * h1) * wSM;
                    float ph = h1 * TAU;
                    float phase = t * wS * spdL + ph;
                    float swing = sin(phase);
                    vec2 pos = vec2((h1 - 0.5) * 0.5 + swayA * swayM * swing,
                                    (h2 - 0.5) * 0.5
                                    // portance : rebond vertical à 2× la fréquence
                                    + swayA * 0.05 * cos(2.0 * phase) * bobM);
                    vec2 p = guv - (cid + 0.5 + pos);
                    // taille : sakura petit, rose plus large, feuille encore plus ; forte variation
                    float s = sizeP * scg * scaleL * (0.7 + 0.6 * h2) * sizeM;
                    // inclinaison = vitesse de la glisse (cos) + penchée au vent
                    float ang = (h2 - 0.5) * TAU
                              + flut1 * tiltM * cos(phase)
                              + petalWind * 0.4;
                    float ca = cos(ang), sa = sin(ang);
                    vec2 q = vec2(ca * p.x - sa * p.y, sa * p.x + ca * p.y) / max(s, 1e-4);
                    // ---- RETOURNEMENT 360° : rotation continue, face arrière visible ----
                    // (feuille : elle BASCULE, revient, bascule… puis se retourne — rock
                    //  sinusoïdal + demi-tours π périodiques lissés)
                    float flipC = 1.0;
                    if (flut > 0.01) {
                        if (pe == 2) {
                            float tt2 = t * (0.08 + 0.08 * h3) * flut * spdL + h2 * 7.0;
                            float turn = 3.14159265 * (floor(tt2) + smoothstep(0.80, 1.0, fract(tt2)));
                            flipC = cos(flut1 * 0.85 * sin(phase * 1.6 + 2.0) + turn);
                        } else {
                            flipC = cos(t * (1.2 + 1.2 * h3) * flut * spdL * ((pe == 1) ? 0.55 : 1.0) + h2 * TAU);
                        }
                    }
                    float fw = abs(flipC);
                    float sgn = (flipC >= 0.0) ? 1.0 : -1.0;
                    q.x = q.x / max(fw, 0.12) * sgn;     // largeur en cos + miroir face arrière
                    if (abs(q.x) > 1.3 || abs(q.y) > 0.9) continue;      // early-out
                    float d;
                    if (pe == 2) {
                        // VOLUME : feuille bombée — la silhouette s'incurve quand elle tourne
                        vec2 qL = q;
                        qL.y += 0.16 * q.x * q.x * (1.0 - fw);
                        d = min(sdLeafBody(qL, h2), sdLeafStem(q));
                    } else {
                        d = (pe == 1) ? sdRose(q, h2) : sdSakura(q, h2);
                    }
                    float cov = 1.0 - smoothstep(-0.045, 0.045, d);
                    if (cov < 0.003) continue;
                    // --- couleur par essence ---
                    float toBase = smoothstep(-0.5, 0.5, q.y);           // 0 pointe → 1 base
                    vec3 cc;
                    if (pe == 0) {
                        // Sakura (VALIDÉ) : pointe quasi blanche → base magenta + stries
                        cc = mix(vec3(0.99, 0.97, 0.98), petalColor.rgb, 0.35 + 0.65 * toBase);
                        cc = mix(cc, petalColor.rgb * vec3(0.95, 0.52, 0.72), smoothstep(0.55, 1.0, toBase));
                        cc *= 1.0 + 0.04 * sin(q.x * 26.0 + h2 * TAU);
                        // dos à peine plus pâle
                        cc = mix(cc, mix(cc, vec3(1.0), 0.18), smoothstep(-0.05, -0.35, flipC));
                    } else if (pe == 1) {
                        // Rose v3 : fort dégradé velours + pli du bord roulé + satin
                        float aR = atan(q.x, -q.y);
                        cc = petalColorB.rgb * mix(1.25, 0.40, toBase);
                        cc *= 1.0 + 0.06 * sin(aR * 16.0 + h2 * TAU);    // stries radiales
                        float fold = q.y + 0.26 - 0.30 * q.x * q.x;      // pli roulé (parabole)
                        cc += petalColorB.rgb * 0.5 * nexp(fold * fold / 0.005) * (1.0 - toBase);
                        float rim = smoothstep(-0.12, -0.02, d);
                        cc = mix(cc, petalColorB.rgb * vec3(1.35, 1.18, 1.22), rim * 0.35);
                        vec2 hc = q - vec2(-0.14 * sgn, -0.08);          // reflet satiné bombé
                        cc += vec3(0.12, 0.05, 0.06) * nexp(dot(hc, hc) / 0.05);
                        // dos nettement plus pâle (caractéristique des roses)
                        vec3 back = mix(petalColorB.rgb, vec3(1.0, 0.85, 0.88), 0.55) * mix(1.05, 0.55, toBase);
                        cc = mix(cc, back, smoothstep(-0.05, -0.35, flipC));
                    } else {
                        // Feuille d'érable : COULEUR PILOTÉE par petalColorC (défaut orange),
                        // dégradé clair (centre) → soutenu (bords), VOLUME (dôme + nervures
                        // + satin), dos et pétiole dérivés de la même teinte
                        float rr = clamp(length(q - vec2(0.0, 0.03)) / 0.50, 0.0, 1.0);
                        vec3 base = petalColorC.rgb;
                        vec3 face = base * mix(1.35, 0.72, smoothstep(0.10, 1.0, rr));
                        // nervures CLAIRES rayonnant vers la pointe de chaque lobe (réf. photo)
                        float aV = abs(atan(q.x, -(q.y - 0.03)));
                        float dv1 = (aV - 0.80) * rr, dv2 = (aV - 1.55) * rr;
                        float veins = nexp(q.x * q.x / 0.0009)
                                    + 0.8 * nexp(dv1 * dv1 / 0.004)
                                    + 0.6 * nexp(dv2 * dv2 / 0.004);
                        veins = clamp(veins, 0.0, 1.0) * smoothstep(1.0, 0.3, rr);
                        face *= 1.0 + 0.16 * veins;
                        // dôme : centre bombé clair, bords qui plongent (fini l'aplat)
                        float dome = 1.0 - rr * rr;
                        face *= 0.76 + 0.34 * dome;
                        // reflet satiné sur le bombé, côté éclairé
                        vec2 hcL = q - vec2(-0.10 * sgn, -0.12);
                        face += base * 0.18 * nexp(dot(hcL, hcL) / 0.03) * fw;
                        // dos : même teinte, sombre et désaturée vers le brun
                        vec3 dos = mix(base * 0.40, vec3(0.32, 0.21, 0.14), 0.35) * (0.75 + 0.30 * dome);
                        dos *= 1.0 - 0.12 * veins;
                        cc = mix(face, dos, smoothstep(-0.03, -0.25, flipC));
                        float stemCov = 1.0 - smoothstep(-0.03, 0.03, sdLeafStem(q));
                        cc = mix(cc, base * 0.30 + vec3(0.12, 0.07, 0.04), stemCov);
                    }
                    // courbure : le côté éclairé alterne avec le retournement
                    cc *= 1.0 + 0.18 * q.x * sgn * fw * flut1;
                    cc *= (0.90 + 0.20 * sHash(seed + vec2(3.3, 6.7)));  // variation par pétale
                    cc *= mix(1.0, 0.45 + 0.55 * fw, flut1);             // tranche assombrie
                    // matière : bord translucide ; sakura diaphane, feuille quasi opaque
                    float aEdge = 0.62 + 0.38 * smoothstep(-0.02, -0.12, d);
                    float a = cov * alphaL * mask * aEdge * opE;
                    col = mix(col, clamp(cc, 0.0, 1.0), a);
                    accA = accA + a * (1.0 - accA);
                }
            }
        }
    }
    FragColor = vec4(col, max(src.a, accA)) * v_col;
}
#endif
