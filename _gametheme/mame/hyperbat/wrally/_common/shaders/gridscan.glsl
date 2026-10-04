// HyperBat Grid Scan — port clean-room de "Virtual Grid Scan" (WE 3647377690).
// Grille néon procédurale + balayage lumineux qui défile (style HUD / radar).
// Mono-passe procédural, animé via uTime. ⚠ pas de mots réservés ES 3.00.
//   gridOpacity : opacité de la grille (maître)
//   gridSize    : densité (nb de cellules)
//   gridColor   : couleur des lignes (vec4)
//   gridLine    : épaisseur des lignes
//   scanSpeed   : vitesse du balayage
//   scanWidth   : largeur du balayage

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

uniform COMPAT_PRECISION float gridOpacity;
uniform COMPAT_PRECISION float gridSize;
uniform COMPAT_PRECISION vec4  gridColor;
uniform COMPAT_PRECISION float gridLine;
uniform COMPAT_PRECISION float scanSpeed;
uniform COMPAT_PRECISION float scanWidth;
uniform int gridScanFullArea;   // 1 = la grille s'affiche aussi sur la transparence du calque

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

void main(void) {
    vec4 base = COMPAT_TEXTURE(u_tex, hbFlipV(v_tex));
    float cells = (gridSize <= 0.0) ? 16.0 : gridSize;
    float lineW = (gridLine == 0.0) ? 0.04 : gridLine;
    vec2 res = (textureSize.x > 0.0 && textureSize.y > 0.0) ? textureSize : vec2(1.0, 1.0);
    float aspect = res.x / max(res.y, 1.0);

    // cellules carrées : on étire X par l'aspect
    vec2 gv = vec2(v_tex.x * aspect, v_tex.y) * cells;
    vec2 frac = abs(fract(gv) - 0.5);
    // lignes : lumineux pres des frontieres entieres (frac proche de 0.5)
    float lines = smoothstep(0.5 - lineW, 0.5, max(frac.x, frac.y));

    // balayage horizontal qui défile
    float sw = (scanWidth == 0.0) ? 0.15 : scanWidth;
    float scanPos = fract(uTime * scanSpeed * 0.15);
    float scan = smoothstep(sw, 0.0, abs(v_tex.y - scanPos));

    float glow = clamp(lines + scan * 0.8, 0.0, 1.0);
    float op = clamp(gridOpacity, 0.0, 1.0) * gridColor.a * zoneMask(v_tex);
    vec3 outc = base.rgb + gridColor.rgb * glow * op;
    // Option : alpha de sortie = max(alpha du PNG, couverture de la grille) → la grille s'affiche
    // AUSSI dans les zones transparentes du calque. Sinon (off) elle reste collée au PNG comme avant.
    float gridCov = clamp(glow * op, 0.0, 1.0);
    float outA = (gridScanFullArea == 1) ? max(base.a, gridCov) : base.a;
    FragColor = vec4(outc, outA) * v_col;
}
#endif
