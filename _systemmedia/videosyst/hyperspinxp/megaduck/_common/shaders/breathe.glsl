// HyperBat Breathe Shader (respiration / pulsation élastique)
// Gonflement-dégonflement périodique d'une région de l'image : respiration
// d'un personnage, pulsation d'un logo, battement de coeur... Le déplacement
// est nul au centre ET s'éteint en douceur au bord de la région (atténuation
// C1 intégrée) : AUCUNE couture possible, quels que soient les réglages —
// contrairement à un effet de distorsion limité par un masque à bord dur.
// Compatible ES GLSL shader pipeline.
//
// Uniforms pilotables (storyboard "shader.xxx") — 0 = valeur par défaut :
//   breatheTime    : temps en secondes (animer 0 -> 3600 sur 3600000 ms, repeat 0)
//   breatheSpeed   : respirations par seconde      (défaut : 0.3)
//   breatheAmount  : amplitude du gonflement       (défaut : 0.06 = 6 %)
//   breatheCenter  : centre de la région (vec2 UV, défaut 0.5 0.5 — clic gauche
//                    dans le studio)
//   breatheRadius  : demi-axes de la région (vec2 UV, défaut 0.25 0.25)
//   breatheAxes    : pondération x/y du mouvement (défaut 1 1 ;
//                    ex. "0.3 1" = surtout vertical)
//   breatheWobble  : seconde harmonique organique (0..1, défaut 0 = sinus pur)
//   + masque de zone commun (multiplie l'effet, défaut partout)

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


uniform COMPAT_PRECISION float breatheTime;
uniform COMPAT_PRECISION float breatheSpeed;
uniform COMPAT_PRECISION float breatheAmount;
uniform COMPAT_PRECISION vec2  breatheCenter;
uniform COMPAT_PRECISION vec2  breatheRadius;
uniform COMPAT_PRECISION vec2  breatheAxes;
uniform COMPAT_PRECISION float breatheWobble;

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
    float speed  = (breatheSpeed  == 0.0) ? 0.3  : breatheSpeed;
    float amount = (breatheAmount == 0.0) ? 0.06 : breatheAmount;
    vec2 center  = (breatheCenter.x == 0.0 && breatheCenter.y == 0.0)
                   ? vec2(0.5, 0.5) : breatheCenter;
    vec2 radius  = (breatheRadius.x == 0.0 && breatheRadius.y == 0.0)
                   ? vec2(0.25, 0.25) : breatheRadius;
    vec2 axes    = (breatheAxes.x == 0.0 && breatheAxes.y == 0.0)
                   ? vec2(1.0, 1.0) : breatheAxes;

    // Distance elliptique normalisée au centre, atténuation douce (C1) :
    // 1 au centre -> 0 au bord de la région. Pas de couture possible.
    vec2 delta = v_tex - center;
    float d = length(delta / max(radius, vec2(1e-5)));
    float w = 1.0 - smoothstep(0.0, 1.0, d);

    // Respiration : sinus + seconde harmonique optionnelle pour l'organique
    float s = sin(breatheTime * speed * M_PI_2);
    s += breatheWobble * 0.35 * sin(breatheTime * speed * M_PI_2 * 2.7 + 1.7);

    // Gonflement : on échantillonne vers le centre quand s > 0 (dilatation).
    // Déplacement nul au centre (delta -> 0) et au bord (w -> 0).
    vec2 offset = delta * axes * (s * amount) * w * zoneMask(v_tex);

    vec2 texCoord = clamp(v_tex - offset, vec2(0.0), vec2(1.0));
    FragColor = COMPAT_TEXTURE(u_tex, hbFlipV(texCoord)) * v_col;
}

#endif
