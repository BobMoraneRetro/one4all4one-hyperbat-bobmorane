// HyperBat Hex Grid — port clean-room de "Hex Grid (MGS2)" (WE 3667892579).
// Grille hexagonale néon (codec / radar MGS2) avec halo doux autour d'un centre.
// Mono-passe procédural, scintillement léger via uTime. ⚠ pas de mots réservés ES 3.00.
//   hexOpacity : opacité (maître)
//   hexCenter  : centre du halo (vec2 UV)
//   hexSize    : taille des cellules (densité)
//   hexColor   : couleur des bords (vec4)
//   hexLine    : épaisseur des bords
//   hexRange   : rayon du halo (0 = plein écran)

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

uniform COMPAT_PRECISION float hexOpacity;
uniform COMPAT_PRECISION vec2  hexCenter;
uniform COMPAT_PRECISION float hexSize;
uniform COMPAT_PRECISION vec4  hexColor;
uniform COMPAT_PRECISION float hexLine;
uniform COMPAT_PRECISION float hexRange;
uniform int hexFullArea;   // 1 = la grille hexa s'affiche aussi sur la transparence du calque

// distance au bord d'une cellule hexagonale (grille pointy-top)
float hexEdge(vec2 p) {
    p = abs(p);
    float c = dot(p, normalize(vec2(1.0, 1.73205)));
    return max(c, p.x);
}

void main(void) {
    vec4 base = COMPAT_TEXTURE(u_tex, hbFlipV(v_tex));
    float dens = (hexSize <= 0.0) ? 14.0 : hexSize;
    float lineW = (hexLine == 0.0) ? 0.08 : hexLine;
    vec2 center = (hexCenter.x == 0.0 && hexCenter.y == 0.0) ? vec2(0.5, 0.5) : hexCenter;
    vec2 res = (textureSize.x > 0.0 && textureSize.y > 0.0) ? textureSize : vec2(1.0, 1.0);
    float aspect = res.x / max(res.y, 1.0);

    // pavage hexagonal : deux candidats de grille décalés, on garde le plus proche
    vec2 uv = vec2(v_tex.x * aspect, v_tex.y) * dens;
    vec2 r = vec2(1.0, 1.73205);
    vec2 a = mod(uv, r) - r * 0.5;
    vec2 b = mod(uv - r * 0.5, r) - r * 0.5;
    vec2 gv = (dot(a, a) < dot(b, b)) ? a : b;
    float ed = hexEdge(gv);
    // contour : lumineux pres de la frontiere de cellule (ed proche de 0.5), sombre au centre
    float edge = smoothstep(0.5 - lineW, 0.5, ed);

    // halo autour du centre + léger scintillement
    vec2 dc = (v_tex - center) * vec2(aspect, 1.0);
    float range = (hexRange == 0.0) ? 0.0 : hexRange;
    float halo = (range <= 0.0) ? 1.0 : (1.0 - smoothstep(range * 0.5, range, length(dc)));
    float flick = 0.85 + 0.15 * sin(uTime * 2.0 + length(dc) * 8.0);

    float op = clamp(hexOpacity, 0.0, 1.0) * hexColor.a * halo * flick;
    vec3 outc = base.rgb + hexColor.rgb * edge * op;
    // Option : afficher la grille aussi sur la transparence du calque (sinon collee au PNG).
    float outA = (hexFullArea == 1) ? max(base.a, clamp(edge * op, 0.0, 1.0)) : base.a;
    FragColor = vec4(outc, outA) * v_col;
}
#endif
