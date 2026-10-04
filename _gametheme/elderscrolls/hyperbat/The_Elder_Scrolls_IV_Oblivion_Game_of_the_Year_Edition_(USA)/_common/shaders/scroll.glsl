// HyperBat Scroll Shader
// Défilement infini de la texture (avec répétition), porté de l'effet
// "scroll" du projet razer_bedroom de Wallpaper Engine.
// Compatible ES GLSL shader pipeline.
//
// Uniforms pilotables (storyboard "shader.xxx") — 0 = valeur d'origine WE :
//   scrollTime   : temps en secondes (animer 0 -> 3600 sur 3600000 ms, repeat 0)
//   scrollSpeedX : vitesse horizontale (WE : 0.2, plage -2..2 ; le signe donne le sens)
//   scrollSpeedY : vitesse verticale   (WE : 0.2, plage -2..2)
//   scrollRepeat : répétitions de la texture (vec2, WE : 1 1)
//
// NB : comme dans WE, la vitesse effective est speed^2 (signe conservé) pour
// un réglage fin des basses vitesses. La texture doit être tileable pour un
// défilement sans couture (sinon le repeat coupera aux bords).

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

uniform   mat4 MVPMatrix;
COMPAT_ATTRIBUTE vec2 VertexCoord;
COMPAT_ATTRIBUTE vec2 TexCoord;
COMPAT_ATTRIBUTE vec4 COLOR;
COMPAT_VARYING   vec2 v_tex;
COMPAT_VARYING   vec4 v_col;
COMPAT_VARYING   vec2 v_scroll;

uniform COMPAT_PRECISION float scrollTime;
uniform COMPAT_PRECISION float scrollSpeedX;
uniform COMPAT_PRECISION float scrollSpeedY;

void main(void)
{
    vec2 hbTexCoord = vec2(TexCoord.x, 1.0 - TexCoord.y); // HB-FLIPV: ES texcoords -> espace effet (toutes varyings géométriques conjuguées)
    gl_Position = MVPMatrix * vec4(VertexCoord.xy, 0.0, 1.0);
    v_tex       = hbTexCoord;
    v_col       = COLOR;

    float sx = (scrollSpeedX == 0.0 && scrollSpeedY == 0.0) ? 0.2 : scrollSpeedX;
    float sy = (scrollSpeedX == 0.0 && scrollSpeedY == 0.0) ? 0.2 : scrollSpeedY;

    // vitesse^2 avec signe conservé, comme WE
    vec2 scroll = vec2(sign(sx) * sx * sx, sign(sy) * sy * sy);
    v_scroll = scroll * scrollTime;
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
COMPAT_VARYING vec2 v_scroll;

uniform sampler2D u_tex;
vec2 hbFlipV(vec2 p) { return vec2(p.x, 1.0 - p.y); } // HB-FLIPV

uniform COMPAT_PRECISION vec2 scrollRepeat;

// ── Masque de zone (placement de l'effet, équivalent du masque peint WE) ──
uniform int maskMode;                        // 0 = partout, 1 = rectangle, 2 = ellipse
uniform COMPAT_PRECISION vec2  maskCenter;   // centre de la zone (UV)
uniform COMPAT_PRECISION vec2  maskSize;     // taille de la zone (UV, 0 = 0.5 0.5)
uniform COMPAT_PRECISION float maskSoftness; // douceur du bord
uniform int maskInvert;                      // 1 = effet hors de la zone

float zoneMask(vec2 uv) {
    if (maskMode == 0) return 1.0;
    vec2 size = (maskSize.x == 0.0 && maskSize.y == 0.0) ? vec2(0.5, 0.5) : maskSize;
    vec2 d = abs(uv - maskCenter) / max(size * 0.5, vec2(1e-5));
    float dist = (maskMode == 2) ? length(d) : max(d.x, d.y);
    float soft = max(maskSoftness, 1e-4);
    float m = 1.0 - smoothstep(1.0 - soft, 1.0 + soft, dist);
    return (maskInvert == 1) ? 1.0 - m : m;
}

void main(void)
{
    vec2 repeat = (scrollRepeat.x == 0.0) ? vec2(1.0, 1.0) : scrollRepeat;
    vec2 texCoord = fract((v_tex + v_scroll) * repeat);
    vec4 scrolled = COMPAT_TEXTURE(u_tex, hbFlipV(texCoord));
    vec4 base = COMPAT_TEXTURE(u_tex, hbFlipV(v_tex));
    FragColor = mix(base, scrolled, zoneMask(v_tex)) * v_col;
}

#endif
