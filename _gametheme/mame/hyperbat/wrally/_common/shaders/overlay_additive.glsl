// HyperBat Additive Overlay — rend l'image du calque en CALQUE LUMINEUX additif :
// les zones SOMBRES deviennent transparentes, les zones CLAIRES ajoutent leur lumière
// sur ce qu'il y a en dessous. Idéal pour une texture de god-rays / lueur / particules
// (PNG) posée par-dessus une image. La magnitude lumineuse est portée par l'alpha
// (premultiplié super-lumineux) → compositing additif. ⚠ pas de mots réservés ES 3.00.
//   overlayIntensity : force de la lumière ajoutée

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
vec2 hbFlipV(vec2 p) { return vec2(p.x, 1.0 - p.y); }

uniform COMPAT_PRECISION float overlayIntensity;

void main(void) {
    vec4 src = COMPAT_TEXTURE(u_tex, hbFlipV(v_tex));
    float gain = (overlayIntensity == 0.0) ? 1.0 : overlayIntensity;
    // luminance perçue → sert d'alpha : sombre = transparent, clair = lumineux.
    float lum = dot(src.rgb, vec3(0.299, 0.587, 0.114));
    // rgb = couleur × gain (premultiplié, peut dépasser l'alpha → additif au compositing).
    FragColor = vec4(src.rgb * gain, clamp(lum * src.a, 0.0, 1.0)) * v_col;
}
#endif
