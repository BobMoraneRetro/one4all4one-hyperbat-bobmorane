// HyperBat Stage Spotlight — port clean-room de "Advanced Stage Spotlight"
// (WE 3637407909). Un projecteur circulaire : l'intérieur est éclairé, l'extérieur
// est assombri vers une couleur de masque. Centre/rayon/douceur réglables.
// Mono-passe procédural (pas de texture de halo). ⚠ pas de mots réservés ES 3.00.
//   spotIntensity  : luminosité du faisceau (maître)
//   spotCenter     : centre du spot (vec2 UV)
//   spotRadius     : rayon du spot
//   spotSoftness   : douceur du bord
//   spotMaskColor  : couleur de l'ombre (vec4, alpha ignoré)
//   spotMaskOpacity: force de l'assombrissement extérieur

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

uniform COMPAT_PRECISION float spotIntensity;   // maitre : application globale (0 = off)
uniform COMPAT_PRECISION vec2  spotCenter;
uniform COMPAT_PRECISION float spotRadius;
uniform COMPAT_PRECISION float spotSoftness;
uniform COMPAT_PRECISION float spotShadow;      // assombrissement exterieur
uniform COMPAT_PRECISION float spotGlow;        // boost lumineux interieur
uniform COMPAT_PRECISION vec4  spotMaskColor;

void main(void) {
    vec4 albedo = COMPAT_TEXTURE(u_tex, hbFlipV(v_tex));
    float amt = clamp(spotIntensity, 0.0, 1.0);
    vec2 center = (spotCenter.x == 0.0 && spotCenter.y == 0.0) ? vec2(0.5, 0.5) : spotCenter;
    float radius = (spotRadius == 0.0) ? 0.35 : spotRadius;
    float soft = max(spotSoftness, 1e-3);
    float glow = (spotGlow == 0.0) ? 1.0 : spotGlow;

    // aspect-correct distance so the spot stays circular
    vec2 res = (textureSize.x > 0.0 && textureSize.y > 0.0) ? textureSize : vec2(1.0, 1.0);
    vec2 d = (v_tex - center) * vec2(res.x / max(res.y, 1.0), 1.0);
    float dist = length(d);
    float circle = 1.0 - smoothstep(radius - soft, radius + soft, dist);

    vec3 shadow = mix(albedo.rgb, spotMaskColor.rgb, clamp(spotShadow, 0.0, 1.0));
    vec3 lit = albedo.rgb * glow;
    vec3 spotted = mix(shadow, lit, circle);
    // le maitre fond tout l'effet vers l'image d'origine -> 0 = vraiment eteint
    FragColor = vec4(mix(albedo.rgb, spotted, amt), albedo.a) * v_col;
}
#endif
