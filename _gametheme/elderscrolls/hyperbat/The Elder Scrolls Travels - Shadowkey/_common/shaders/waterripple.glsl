// HyperBat Water Ripple Shader
// Ondulations d'eau animées, porté de l'effet "waterripple" de Wallpaper Engine.
// La texture de normales d'eau est remplacée par des normales procédurales
// (dérivées d'un bruit de valeur) : aucune texture externe requise.
// Compatible ES GLSL shader pipeline.
//
// Uniforms pilotables (storyboard "shader.xxx") — 0 = valeur d'origine WE :
//   rippleTime       : temps en secondes (animer 0 -> 3600 sur 3600000 ms, repeat 0)
//   rippleSpeed      : vitesse d'animation        (WE : 0.15, plage 0..0.5)
//   rippleScale      : échelle des ondulations    (WE : 1, plage 0..10)
//   rippleStrength   : force de distorsion        (WE : 0.1, plage 0..1)
//   rippleRatio      : ratio vertical             (WE : 1, plage 0..10)
//   scrollSpeed      : vitesse de défilement      (WE : 0, plage 0..0.5)
//   scrollDirection  : direction du défilement en radians (WE : 0)
//   specularStrength : reflet spéculaire, 0 = désactivé (WE : combo off)
//   specularPower    : exposant du spéculaire     (WE : 1, plage 0..100)
//   specularColor    : couleur du spéculaire (vec4, alpha 0 = blanc)
//
// Le moteur doit fournir textureSize (déjà le cas dans le pipeline HyperBat).

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
COMPAT_VARYING   vec4 v_ripple;

uniform COMPAT_PRECISION vec2 textureSize;
uniform COMPAT_PRECISION float rippleTime;
uniform COMPAT_PRECISION float rippleSpeed;
uniform COMPAT_PRECISION float rippleScale;
uniform COMPAT_PRECISION float rippleRatio;
uniform COMPAT_PRECISION float scrollSpeed;
uniform COMPAT_PRECISION float scrollDirection;

vec2 rotateVec2(vec2 v, float r)
{
    vec2 cs = vec2(cos(r), sin(r));
    return vec2(v.x * cs.x - v.y * cs.y, v.x * cs.y + v.y * cs.x);
}

void main(void)
{
    vec2 hbTexCoord = vec2(TexCoord.x, 1.0 - TexCoord.y); // HB-FLIPV: ES texcoords -> espace effet (toutes varyings géométriques conjuguées)
    gl_Position = MVPMatrix * vec4(VertexCoord.xy, 0.0, 1.0);
    v_tex       = hbTexCoord;
    v_col       = COLOR;

    float speed = (rippleSpeed == 0.0) ? 0.15 : rippleSpeed;
    float scale = (rippleScale == 0.0) ? 1.0  : rippleScale;
    float ratio = (rippleRatio == 0.0) ? 1.0  : rippleRatio;

    vec2 scroll = rotateVec2(vec2(0.0, 1.0), scrollDirection) * scrollSpeed * scrollSpeed * rippleTime;

    // Deux couches d'ondulations à échelles différentes, défilant en sens opposés
    v_ripple.xy = hbTexCoord + rippleTime * speed * speed + scroll;
    v_ripple.zw = hbTexCoord * 1.333 - rippleTime * speed * speed + scroll;
    v_ripple *= scale;

    float aspect = (textureSize.y == 0.0) ? 1.0 : (textureSize.x / textureSize.y);
    v_ripple.xz *= aspect;
    v_ripple.yw *= ratio;
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
COMPAT_VARYING vec4 v_ripple;

uniform sampler2D u_tex;
vec2 hbFlipV(vec2 p) { return vec2(p.x, 1.0 - p.y); } // HB-FLIPV


uniform COMPAT_PRECISION float rippleStrength;
uniform COMPAT_PRECISION float specularStrength;
uniform COMPAT_PRECISION float specularPower;
uniform COMPAT_PRECISION vec4  specularColor;

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

// Hauteur de l'eau : 2 octaves de bruit
float waterHeight(vec2 uv) {
    return noise(uv) * 0.7 + noise(uv * 2.3) * 0.3;
}

// Remplace la texture de normales "waterripplenormal" de Wallpaper Engine :
// normale dérivée du bruit par différences finies. 20.0 = fréquence des vaguelettes.
vec3 waterNormal(vec2 uv) {
    uv *= 20.0;
    float e = 0.6;
    float h  = waterHeight(uv);
    float hx = waterHeight(uv + vec2(e, 0.0));
    float hy = waterHeight(uv + vec2(0.0, e));
    return vec3((vec2(hx, hy) - h) * 3.5, 1.0);
}

void main(void)
{
    float strength = (rippleStrength == 0.0) ? 0.1 : rippleStrength;

    vec3 n1 = waterNormal(v_ripple.xy);
    vec3 n2 = waterNormal(v_ripple.zw);
    vec3 normal = normalize(vec3(n1.xy + n2.xy, n1.z));

    vec2 texCoord = v_tex + normal.xy * strength * strength * zoneMask(v_tex);
    texCoord = clamp(texCoord, vec2(0.0), vec2(1.0));

    vec4 color = COMPAT_TEXTURE(u_tex, hbFlipV(texCoord));

    // Reflet spéculaire optionnel (combo SPECULAR de WE)
    if (specularStrength > 0.0) {
        float power = (specularPower == 0.0) ? 1.0 : specularPower;
        vec3 specColor = (specularColor.a == 0.0) ? vec3(1.0, 1.0, 1.0) : specularColor.rgb;

        vec2 direction = normalize(vec2(0.5, 0.0) - v_tex);
        float specular = max(0.0, dot(normal.xy, direction)) * max(0.0, dot(direction, vec2(0.0, -1.0)));
        specular = pow(specular, power) * specularStrength;
        color.rgb += specular * specColor * color.a;
    }

    FragColor = color * v_col;
}

#endif
