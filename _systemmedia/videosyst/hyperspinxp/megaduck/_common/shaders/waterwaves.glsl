// HyperBat Water Waves Shader
// Vagues sinusoïdales animées, porté de l'effet "waterwaves" de Wallpaper Engine.
// Distorsion purement mathématique : aucune texture externe requise.
// Compatible ES GLSL shader pipeline.
//
// Uniforms pilotables (storyboard "shader.xxx") — 0 = valeur d'origine WE :
//   wavesTime       : temps en secondes (animer 0 -> 3600 sur 3600000 ms, repeat 0)
//   wavesSpeed      : vitesse de la vague          (WE : 5, plage 0.01..50)
//   wavesScale      : fréquence de la vague        (WE : 200, plage 0.01..1000)
//   wavesExponent   : exposant (forme de la vague) (WE : 1, plage 0.51..4)
//   wavesStrength   : force de distorsion          (WE : 0.1, plage 0.01..1)
//   wavesDirection  : direction en radians         (WE : 0)
//   dualWaves       : 1 = seconde vague croisée (combo DUALWAVES de WE)
//   wavesSpeed2     : vitesse vague 2              (WE : 3)
//   wavesScale2     : fréquence vague 2            (WE : 66)
//   wavesOffset2    : déphasage vague 2            (WE : 0, plage -5..5)
//   wavesExponent2  : exposant vague 2             (WE : 1)
//   wavesDirection2 : direction vague 2 en radians (WE : 0)

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
COMPAT_VARYING   vec2 v_dir;
COMPAT_VARYING   vec2 v_dir2;

uniform COMPAT_PRECISION float wavesDirection;
uniform COMPAT_PRECISION float wavesDirection2;

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
    v_dir       = rotateVec2(vec2(0.0, 1.0), wavesDirection);
    v_dir2      = rotateVec2(vec2(0.0, 1.0), wavesDirection2);
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
COMPAT_VARYING vec2 v_dir;
COMPAT_VARYING vec2 v_dir2;

uniform sampler2D u_tex;
vec2 hbFlipV(vec2 p) { return vec2(p.x, 1.0 - p.y); } // HB-FLIPV


uniform COMPAT_PRECISION float wavesTime;
uniform COMPAT_PRECISION float wavesSpeed;
uniform COMPAT_PRECISION float wavesScale;
uniform COMPAT_PRECISION float wavesExponent;
uniform COMPAT_PRECISION float wavesStrength;
uniform int dualWaves;
uniform COMPAT_PRECISION float wavesSpeed2;
uniform COMPAT_PRECISION float wavesScale2;
uniform COMPAT_PRECISION float wavesOffset2;
uniform COMPAT_PRECISION float wavesExponent2;

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
    float speed    = (wavesSpeed    == 0.0) ? 5.0   : wavesSpeed;
    float scale    = (wavesScale    == 0.0) ? 200.0 : wavesScale;
    float exponent = (wavesExponent == 0.0) ? 1.0   : wavesExponent;
    float strength = (wavesStrength == 0.0) ? 0.1   : wavesStrength;

    vec2 texCoord = v_tex;
    float zm = zoneMask(v_tex);

    float dist = wavesTime * speed + dot(texCoord, v_dir) * scale;

    strength = strength * strength;

    vec2 offset = vec2(v_dir.y, -v_dir.x);
    float val1 = sin(dist);
    float s1 = sign(val1);
    val1 = pow(abs(val1), exponent);

    if (dualWaves == 1) {
        float speed2    = (wavesSpeed2    == 0.0) ? 3.0  : wavesSpeed2;
        float scale2    = (wavesScale2    == 0.0) ? 66.0 : wavesScale2;
        float exponent2 = (wavesExponent2 == 0.0) ? 1.0  : wavesExponent2;

        float dist2 = (wavesTime + wavesOffset2) * speed2 + dot(texCoord, v_dir2) * scale2;
        float val2 = sin(dist2);
        float s2 = sign(val2);
        val2 = pow(abs(val2), exponent2);

        texCoord += val1 * s1 * val2 * s2 * offset * strength * zm;
    } else {
        texCoord += val1 * s1 * offset * strength * zm;
    }

    texCoord = clamp(texCoord, vec2(0.0), vec2(1.0));
    FragColor = COMPAT_TEXTURE(u_tex, hbFlipV(texCoord)) * v_col;
}

#endif
