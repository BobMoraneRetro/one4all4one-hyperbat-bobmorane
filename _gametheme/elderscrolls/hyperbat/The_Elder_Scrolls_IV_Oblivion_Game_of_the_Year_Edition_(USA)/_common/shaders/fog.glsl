// HyperBat Fog Shader
// Nappes de fumée/brouillard dérivant sur l'image, inspiré du système de
// particules "fog2" du thème Wallpaper Engine 1405112278 "Jurassic Park"
// (grands sprites de fumée blancs très transparents, dérive gauche -> droite,
// blending additif). Version mono-passe : bruit fractal procédural qui défile,
// aucune texture externe requise. Compatible ES GLSL shader pipeline.
//
// Uniforms pilotables (storyboard "shader.xxx") — 0 = valeur par défaut :
//   fogTime      : temps en secondes (animer 0 -> 3600 sur 3600000 ms, repeat 0)
//   fogSpeed     : vitesse de dérive            (défaut : 0.08)
//   fogAmount    : densité/opacité de la fumée  (défaut : 0.35)
//   fogScale     : échelle des nappes           (défaut : 2, plus grand = nappes plus petites)
//   fogDirection : direction de dérive en radians (0 = de gauche à droite, comme le thème)
//   fogColor     : couleur de la fumée (vec4, alpha 0 = blanc)

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

void main(void)
{
    vec2 hbTexCoord = vec2(TexCoord.x, 1.0 - TexCoord.y); // HB-FLIPV: ES texcoords -> espace effet (toutes varyings géométriques conjuguées)
    gl_Position = MVPMatrix * vec4(VertexCoord.xy, 0.0, 1.0);
    v_tex       = hbTexCoord;
    v_col       = COLOR;
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
vec2 hbFlipV(vec2 p) { return vec2(p.x, 1.0 - p.y); } // HB-FLIPV


uniform COMPAT_PRECISION float fogTime;
uniform COMPAT_PRECISION float fogSpeed;
uniform COMPAT_PRECISION float fogAmount;
uniform COMPAT_PRECISION float fogScale;
uniform COMPAT_PRECISION float fogDirection;
uniform COMPAT_PRECISION vec4  fogColor;

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

// Pseudo-random hash function (identique à tvnoise.glsl)
float hash(vec2 p) {
    p = fract(p * vec2(443.8975, 397.2973));
    p += dot(p, p.yx + 19.19);
    return fract(p.x * p.y);
}

// Smooth noise based on hash (identique à tvnoise.glsl)
float noise(vec2 uv) {
    vec2 i = floor(uv);
    vec2 f = fract(uv);
    f = f * f * (3.0 - 2.0 * f);

    float a = hash(i);
    float b = hash(i + vec2(1.0, 0.0));
    float c = hash(i + vec2(0.0, 1.0));
    float d = hash(i + vec2(1.0, 1.0));

    return mix(mix(a, b, f.x), mix(c, d, f.x), f.y);
}

// Bruit fractal 4 octaves : nappes vaporeuses
float fbm(vec2 uv) {
    float v = 0.0;
    float a = 0.5;
    for (int i = 0; i < 4; i++) {
        v += noise(uv) * a;
        uv = uv * 2.13 + vec2(17.7, 9.2);
        a *= 0.5;
    }
    return v / 0.9375;
}

vec2 rotateVec2(vec2 v, float r)
{
    vec2 cs = vec2(cos(r), sin(r));
    return vec2(v.x * cs.x - v.y * cs.y, v.x * cs.y + v.y * cs.x);
}

void main(void)
{
    float speed  = (fogSpeed  == 0.0) ? 0.08 : fogSpeed;
    float amount = (fogAmount == 0.0) ? 0.35 : fogAmount;
    float scale  = (fogScale  == 0.0) ? 2.0  : fogScale;
    vec3  color  = (fogColor.a == 0.0) ? vec3(1.0, 1.0, 1.0) : fogColor.rgb;

    vec4 albedo = COMPAT_TEXTURE(u_tex, hbFlipV(v_tex));

    // Dérive : 0 rad = de gauche à droite (comme le thème d'origine)
    vec2 dir = rotateVec2(vec2(1.0, 0.0), fogDirection);
    float t = fogTime * speed;

    // Nappes plus larges que hautes, deux couches à vitesses différentes
    vec2 uv = v_tex * vec2(scale, scale * 1.5);
    float f1 = fbm(uv * 1.5 - dir * t * 1.5);
    float f2 = fbm(uv * 2.6 - dir * t * 2.4 + vec2(7.31, 2.58));
    float fog = f1 * 0.65 + f2 * 0.35;

    // Seuillage doux : ne garde que les volutes denses, très transparentes
    fog = smoothstep(0.30, 0.85, fog) * amount * zoneMask(v_tex);

    // Additif, comme le matériau fog2 de WE
    albedo.rgb += color * fog;

    FragColor = albedo * v_col;
}

#endif
