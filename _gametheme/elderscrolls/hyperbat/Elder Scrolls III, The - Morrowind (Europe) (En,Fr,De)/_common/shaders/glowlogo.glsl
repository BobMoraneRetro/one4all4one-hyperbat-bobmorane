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

void main(void)
{
	gl_Position = MVPMatrix * vec4(VertexCoord.xy, 0.0, 1.0);
	v_tex = TexCoord;
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
uniform COMPAT_PRECISION vec2 resolution;
uniform COMPAT_PRECISION vec2 textureSize;
uniform COMPAT_PRECISION vec2 outputSize;

// NOUVEAUX PARAMÈTRES
uniform COMPAT_PRECISION float glowSize; // Rayon du halo (suit glowSize, ~×20 px). 1.0 = bonne base
uniform COMPAT_PRECISION vec4 glowColor; // Couleur RGB normalisée + alpha = intensité (10..100)
uniform COMPAT_PRECISION float glowSolid; // 0 = halo dégradé (défaut, s'estompe), 1 = halo plein/uni
uniform COMPAT_PRECISION float glowOpacity; // multiplie l'opacité du halo (aperçu in-app : anime le glow ; export ES : =1, l'opacité de l'élément anime)
uniform COMPAT_PRECISION float glowSoft; // 1 = DOUX/diffus (gros flou ×22, défaut, = vidéos), 0 = NET/serré (algo original)

vec4 sampleTexture(sampler2D tex, vec2 texCoord)
{
    // Controle les coordonées de la texture entre 0 et 1
    if (texCoord.x >= 0.0 && texCoord.x <= 1.0 && texCoord.y >= 0.0 && texCoord.y <= 1.0)
        return COMPAT_TEXTURE(tex, texCoord);
    
    return vec4(0.0); // Return transparent black for coordinates outside [0, 1]
}

void main(void)
{
    vec2 step = 1.0 / textureSize;
    vec4 texColor = sampleTexture(u_tex, v_tex);

    // glowColor : RGB normalisé + alpha = intensité (≥10). 0 → défaut blanc.
    vec4 effectiveGlowColor = glowColor;
    if (effectiveGlowColor.a == 0.0 && glowSize != 0.0) { effectiveGlowColor = vec4(1.0, 1.0, 1.0, 20.0); }
    float intensity = effectiveGlowColor.a;

    float glowA;
    if (glowSoft >= 0.5) {
        // ════ DOUX / DIFFUS (défaut) — calé sur l'ombre Konva de l'aperçu (la
        // lueur des vidéos de juin) : GROS flou gaussien (rayon ×22, noyau 13×13). ════
        // Échantillonnage en SPIRALE de Vogel (disque) au lieu d'une GRILLE : la
        // grille laissait des marches d'escalier visibles en ES (« pixelisé ») ;
        // la spirale couvre le disque de flou sans motif régulier → dégradé lisse,
        // et avec MOINS d'échantillons (100 vs 289). σ = blurPx/2 inchangé (même
        // taille/opacité que l'ombre Konva de l'aperçu).
        float blurPx = max(2.0, glowSize * 22.0) * (1.0 + max(0.0, intensity - 25.0) / 50.0);
        float sigma = blurPx * 0.5;
        float maxR = 2.5 * sigma;                             // rayon de coupe (texels)
        const int N = 256;
        // Rotation pseudo-aléatoire PAR PIXEL : le motif régulier de la spirale
        // (identique pour tous les pixels) ressort en stries/escaliers en ES ; en
        // le tournant d'un angle différent à chaque pixel, ces stries deviennent un
        // grain fin imperceptible — robuste quelle que soit la résolution de rendu.
        float jitter = fract(sin(dot(v_tex, vec2(12.9898, 78.233))) * 43758.5453) * 6.2831853;
        float totalA = 0.0;
        float wsum = 0.0;
        for (int i = 0; i < N; i++) {
            float fi = float(i);
            float r = sqrt((fi + 0.5) / float(N)) * maxR;     // densité uniforme sur le disque
            float ang = fi * 2.399963 + jitter;               // spirale de Vogel + jitter/pixel
            vec2 d = vec2(cos(ang), sin(ang)) * r;
            float w = exp(-(r * r) / (2.0 * sigma * sigma));  // poids gaussien (rayon réel)
            totalA += sampleTexture(u_tex, v_tex + d * step).a * w;
            wsum += w;
        }
        float a = totalA / max(wsum, 0.0001);
        // Opacité = EXACTEMENT celle de l'ombre Konva de l'aperçu : a × min(1,int/25)
        // (PAS de ×1.5, qui rendait l'ES ~1.5× plus saturé que l'aperçu).
        glowA = clamp(a * min(1.0, intensity / 25.0), 0.0, 1.0);
    } else {
        // ════ NET / SERRÉ — contour dense qui épouse la silhouette. Même machinerie
        // que le Doux (spirale de Vogel + jitter par pixel → LISSE à toutes les
        // tailles, là où l'ancien noyau 5×5 devenait blocky en grossissant), mais
        // RAYON SERRÉ + alpha SATURÉE (bande pleine = bord net), avec pow(1.5). ════
        float reach = max(2.0, glowSize * 2.5);              // rayon serré (texels)
        float sigma = reach * 0.6;
        const int Nn = 80;
        float jitter = fract(sin(dot(v_tex, vec2(12.9898, 78.233))) * 43758.5453) * 6.2831853;
        float totalA = 0.0;
        float wsum = 0.0;
        for (int i = 0; i < Nn; i++) {
            float fi = float(i);
            float r = sqrt((fi + 0.5) / float(Nn)) * reach;
            float ang = fi * 2.399963 + jitter;
            vec2 d = vec2(cos(ang), sin(ang)) * r;
            float w = exp(-(r * r) / (2.0 * sigma * sigma));
            totalA += sampleTexture(u_tex, v_tex + d * step).a * w;
            wsum += w;
        }
        float a = pow(totalA / max(wsum, 0.0001), 1.5);      // transition douce (original)
        glowA = clamp(a * intensity, 0.0, 1.0);              // saturée = bande dense/nette
    }

    // Multiplicateur d'opacité (aperçu : animation du glow). En ES, toujours 1
    // (toujours émis par l'export) → pas d'effet, l'opacité de l'élément anime.
    glowA *= clamp(glowOpacity, 0.0, 1.0);

    vec4 finalGlow = vec4(effectiveGlowColor.rgb, glowA);

    // COMPOSITION FINALE
    // Le logo original par-dessus la lueur
    // Utilisation d'un mélange de type "alpha blend" standard
    FragColor = mix(finalGlow, texColor, texColor.a) * v_col;
}
#endif