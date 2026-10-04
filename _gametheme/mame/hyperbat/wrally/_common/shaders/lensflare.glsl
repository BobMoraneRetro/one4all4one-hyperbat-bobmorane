// HyperBat Lens Flare — halo d'objectif de caméra : depuis une source lumineuse (clic
// gauche), un cœur éclatant + un halo annulaire + des "ghosts" colorés alignés sur l'axe
// source→centre + un streak horizontal anamorphique, avec aberration chromatique. Additif.
// ⚠ pas de mots réservés ES 3.00.
//   flareIntensity : intensité globale (maître, 0 = off)
//   flareCenter    : position de la source (vec2 UV, clic gauche)
//   flareColor     : teinte principale
//   flareGhosts    : force/nombre des ghosts (cercles secondaires)
//   flareHalo      : force du halo annulaire
//   flareStreak    : force du trait horizontal (anamorphique)

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

uniform COMPAT_PRECISION float flareIntensity;
uniform COMPAT_PRECISION vec2  flareCenter;
uniform COMPAT_PRECISION vec2  flareEnd;
uniform COMPAT_PRECISION vec4  flareColor;
uniform COMPAT_PRECISION float flareSize;
uniform COMPAT_PRECISION float flareFlicker;
uniform COMPAT_PRECISION float flareGhosts;
uniform COMPAT_PRECISION float flareHalo;
uniform COMPAT_PRECISION float flareStreak;
uniform COMPAT_PRECISION float flareRainbow;
uniform COMPAT_PRECISION float flareBand;
uniform COMPAT_PRECISION float flareGhostFill;
uniform int flareOverlay;

// Spectre arc-en-ciel pour une position 0..1 dans l'épaisseur de l'anneau.
vec3 rainbowHue(float h) {
    return 0.5 + 0.5 * cos(6.2831853 * (clamp(h, 0.0, 1.0) + vec3(0.0, 0.33, 0.66)));
}

// "Ghost" d'objectif façon HALO : disque doux SEMI-TRANSPARENT (cœur blanc léger) avec
// une COULEUR sur le contour — par défaut la teinte propre du ghost, et vers le prisme
// complet quand rainbow monte. + fin liseré irisé tout au bord.
vec3 ghost(vec2 p, vec2 c, float radius, float soft, float rainbow, float fill, vec3 gcol) {
    float rn = length(p - c) / max(radius, 1e-4);   // rayon normalisé (1 = bord)
    // Corps : disque doux, un peu plus marqué vers le bord → look "halo".
    float body = smoothstep(1.0 + soft, 0.0, rn);
    float edge = smoothstep(0.5, 0.92, rn) * (1.0 - smoothstep(0.95, 1.12, rn));
    // REMPLISSAGE interne paramétrable (fill) : 0 = anneau CREUX (juste le contour coloré),
    // 1 = film blanc doux au centre. Le contour coloré, lui, est toujours présent.
    vec3 col = vec3(body * 0.28 * fill);   // cœur blanc (film interne réglable)
    col += gcol * edge * 1.2;              // contour coloré
    // Option arc-en-ciel : le contour devient un prisme complet au lieu d'une seule teinte.
    vec3 prism = rainbowHue((rn - 0.5) / 0.45) * edge * 1.5;
    col = mix(col, vec3(body * 0.18 * fill) + prism, clamp(rainbow, 0.0, 1.0) * 0.7);
    // Fin liseré (quelques px) dont la couleur tourne autour du contour (irisation).
    // +1e-6 sur x : évite atan(0,0) (indéfini → NaN possible) au pixel exact du centre.
    float ang = atan(p.y - c.y, (p.x - c.x) + 1e-6) / 6.2831853 + 0.5;
    float fine = smoothstep(0.93, 0.99, rn) * (1.0 - smoothstep(0.99, 1.05, rn));
    col += rainbowHue(fract(ang * 3.0 + rn)) * fine * clamp(rainbow, 0.0, 1.0) * 0.5;
    return col;
}

void main(void) {
    vec4 src = COMPAT_TEXTURE(u_tex, hbFlipV(v_tex));
    float intensity = clamp(flareIntensity, 0.0, 1.0);
    vec2 center = (flareCenter.x == 0.0 && flareCenter.y == 0.0) ? vec2(0.28, 0.25) : flareCenter;
    vec2 endp = (flareEnd.x == 0.0 && flareEnd.y == 0.0) ? vec2(0.5, 0.5) : flareEnd;
    vec3 tint = (flareColor.a == 0.0) ? vec3(1.0, 0.9, 0.7) : flareColor.rgb;

    vec2 res = (textureSize.x > 0.0 && textureSize.y > 0.0) ? textureSize : vec2(1.0, 1.0);
    float aspect = res.x / max(res.y, 1.0);
    vec2 asp = vec2(aspect, 1.0);
    vec2 p = (v_tex - 0.5) * asp;            // espace écran centré, aspect-correct
    vec2 src2 = (center - 0.5) * asp;        // source (clic gauche)
    vec2 end2 = (endp - 0.5) * asp;          // finalisation (clic droit)
    float distToSrc = length(p - src2);
    float sz = (flareSize <= 0.0) ? 1.0 : flareSize;   // TAILLE globale du flare
    float dS = distToSrc / sz;               // distance "mise à l'échelle" (taille)

    vec3 light = vec3(0.0);

    // 1) Cœur éclatant à la source + glow.
    float core = exp(-dS * 14.0) + exp(-dS * 3.5) * 0.5;
    light += tint * core * 1.4;

    float rainbow = clamp(flareRainbow, 0.0, 1.0);

    // 2) Halo annulaire autour de la source — son CONTOUR vire à l'arc-en-ciel.
    float ringR = 0.35 * sz;
    float ringD = abs(distToSrc - ringR);
    float ring = smoothstep(0.06 * sz, 0.0, ringD) * flareHalo;
    // teinte de l'anneau : blanc d'origine → spectre selon la position dans l'épaisseur.
    vec3 haloCol = mix(tint, rainbowHue((distToSrc - ringR) / (0.06 * sz) * 0.5 + 0.5) * 1.4, rainbow);
    light += haloCol * ring * 0.6;

    // 3) Ghosts : anneaux répartis le long de l'axe source→finalisation.
    vec2 axis = (end2 - src2);               // de la source vers le point de finalisation
    for (int i = 1; i <= 6; i++) {
        float fi = float(i);
        float tpos = fi / 6.0;
        vec2 gc = src2 + axis * (tpos * 2.2 - 0.2);   // au-delà du centre aussi
        float rad = (0.03 + 0.08 * fract(fi * 0.37)) * sz;   // disques doux un peu plus gros
        float soft = 0.6;
        // Chaque ghost a SA propre couleur de contour (palette qui défile : vert, doré,
        // cyan, orange, bleu...) — comme les halos secondaires de Halo.
        vec3 gcol = rainbowHue(fract(fi * 0.21 + 0.15));
        vec3 g = ghost(p, gc, rad, soft, rainbow, clamp(flareGhostFill, 0.0, 1.0), gcol);
        light += g * (0.45 + 0.4 * fract(fi * 0.27)) * flareGhosts;
    }

    // 4) Streak horizontal anamorphique (trait lumineux à travers la source).
    float streak = exp(-abs(p.y - src2.y) * 130.0) * exp(-abs(p.x - src2.x) * 1.5 / sz);
    light += mix(tint, vec3(0.7, 0.85, 1.0), 0.4) * streak * flareStreak * 1.2;

    // 5) Bande arc-en-ciel DIFFUSE le long de l'axe source→finalisation : une "fuite de
    //    lumière" prismatique large et douce qui traverse l'image (voile coloré subtil).
    float bandAmt = clamp(flareBand, 0.0, 1.0);
    if (bandAmt > 0.0) {
        vec2 adir = normalize(axis + vec2(1e-5));
        vec2 aperp = vec2(-adir.y, adir.x);
        float along = dot(p - src2, adir);
        float perp  = dot(p - src2, aperp);
        float bandW = 0.22 * sz;                              // largeur de la bande
        float band  = exp(-(perp * perp) / (bandW * bandW));  // gaussienne perpendiculaire
        // plancher : si finalisation == source (axe nul), évite des bords de smoothstep
        // égaux → division par zéro → NaN sur tout le flare (drivers stricts).
        float alen  = max(length(axis), 1e-3);
        // limitée le long de l'axe (de la source jusqu'un peu au-delà de la finalisation)
        band *= smoothstep(-0.15, 0.15, along) * smoothstep(alen * 1.5, alen * 0.5, along);
        // les couleurs se succèdent EN TRAVERS de la bande (rouge→vert→bleu) = prisme.
        vec3 bandCol = rainbowHue(perp / (bandW * 2.2) + 0.5);
        light += bandCol * band * bandAmt * 0.35;
    }

    // Oscillation (scintillement) : vitesse réglable ; 0 = figé (intensité constante).
    float osc = (flareFlicker <= 0.0) ? 1.0 : (0.9 + 0.1 * sin(uTime * flareFlicker));
    light *= intensity * osc;

    if (flareOverlay == 1) {
        FragColor = vec4(light, clamp(max(max(light.r, light.g), light.b), 0.0, 0.92)) * v_col;
    } else {
        vec3 outc = src.rgb + light;   // additif
        FragColor = vec4(outc, max(src.a, clamp(max(max(light.r, light.g), light.b), 0.0, 1.0))) * v_col;
    }
}
#endif
