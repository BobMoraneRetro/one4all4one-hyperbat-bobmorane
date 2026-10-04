// HyperBat Shake Shader
// Secousse de l'image (utilisé par Ryu Hadouken 1918678677, Saint Seiya...),
// porté de l'effet "shake" de Wallpaper Engine. La direction map peinte de
// WE est remplacée par une direction uniforme. L'oscillation conserve la
// courbe de friction de WE (rebond doux/dur réglable par côté).
// Compatible ES GLSL shader pipeline.
//
// Uniforms pilotables (storyboard "shader.xxx") — 0 = valeur d'origine WE :
//   shakeTime      : temps en secondes (animer 0 -> 3600 sur 3600000 ms, repeat 0)
//   shakeSpeed     : vitesse                  (WE : 1, plage 0..10)
//   shakeStrength  : amplitude                (WE : 0.1, plage 0.01..0.5)
//   shakeFriction  : friction aller/retour (vec2) (WE : 1 1, plage 0.01..10)
//   shakeDirection : direction de la secousse en radians (0 = horizontale)
//   shakeNoise     : 1 = oscillation à 4 harmoniques (combo NOISE de WE)
//   shakeMode      : 0 = centre (va-et-vient), 1 = gauche, 2 = droite
//   shakeBounds    : bornes de l'oscillation (vec2) (WE : 0 1)

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

#define M_PI_2 6.28318530718

COMPAT_VARYING vec4 v_col;
COMPAT_VARYING vec2 v_tex;

uniform sampler2D u_tex;
vec2 hbFlipV(vec2 p) { return vec2(p.x, 1.0 - p.y); } // HB-FLIPV


uniform COMPAT_PRECISION float shakeTime;
uniform COMPAT_PRECISION float shakeSpeed;
uniform COMPAT_PRECISION float shakeStrength;
uniform COMPAT_PRECISION vec2  shakeFriction;
uniform COMPAT_PRECISION float shakeDirection;
uniform int shakeNoise;
uniform int shakeMode;
uniform COMPAT_PRECISION vec2  shakeBounds;

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

vec2 rotateVec2(vec2 v, float r)
{
    vec2 cs = vec2(cos(r), sin(r));
    return vec2(v.x * cs.x - v.y * cs.y, v.x * cs.y + v.y * cs.x);
}

void main(void)
{
    float speed    = (shakeSpeed    == 0.0) ? 1.0 : shakeSpeed;
    float strength = (shakeStrength == 0.0) ? 0.1 : shakeStrength;
    vec2 friction  = (shakeFriction.x == 0.0) ? vec2(1.0, 1.0) : shakeFriction;
    vec2 bounds    = (shakeBounds.x == 0.0 && shakeBounds.y == 0.0) ? vec2(0.0, 1.0) : shakeBounds;

    // Remplace la direction map peinte de WE : direction uniforme
    vec2 flowMask = rotateVec2(vec2(1.0, 0.0), shakeDirection);

    float offset;
    if (shakeNoise == 1) {
        // 4 harmoniques (combo NOISE de WE)
        vec4 sines = fract(speed * shakeTime / M_PI_2
                           * vec4(1.0, -0.16161616, 0.0083333, -0.00019841)) * M_PI_2;
        vec4 csines = cos(sines);
        sines = sin(sines);
        vec4 base = step(0.0, csines);
        sines = sines * 0.498 + 0.5;
        sines = mix(vec4(1.0) - pow(vec4(1.0) - sines, vec4(friction.x)),
                    pow(sines, vec4(friction.y)), base);
        offset = dot(vec4(0.5), sines);
    } else {
        float t = speed * shakeTime;
        offset = sin(fract(t / M_PI_2) * M_PI_2);
        offset = offset * 0.498 + 0.5;
        float base = step(0.0, cos(t));
        offset = mix(1.0 - pow(1.0 - offset, friction.x), pow(offset, friction.y), base);
    }
    offset = clamp((offset - bounds.x) / max(bounds.y - bounds.x, 1e-5), 0.0, 1.0);

    if (shakeMode == 0) {
        offset = offset * 2.0 - 1.0;       // centre : va-et-vient
    } else if (shakeMode == 2) {
        offset = offset - 1.0;             // droite
    }                                      // gauche : offset inchangé (0..1)

    vec2 texCoordOffset = offset * strength * strength * flowMask * zoneMask(v_tex);
    vec2 texCoord = clamp(texCoordOffset + v_tex, vec2(0.0), vec2(1.0));
    FragColor = COMPAT_TEXTURE(u_tex, hbFlipV(texCoord)) * v_col;
}

#endif
