// HyperBat Bounce Shader (rebond / jiggle)
// Rebond élastique d'une région de l'image : poitrine, fesses, joues, logo
// qui retombe... Physique de ressort : une impulsion périodique suivie
// d'oscillations amorties (ou oscillation continue), avec squash & stretch
// optionnel. Le déplacement est maximal au centre de la région et s'éteint
// en douceur au bord (atténuation C1) : AUCUNE couture possible.
// Compatible ES GLSL shader pipeline.
//
// Uniforms pilotables (storyboard "shader.xxx") — 0 = valeur par défaut :
//   bounceTime      : temps en secondes (animer 0 -> 3600 sur 3600000 ms, repeat 0)
//   bounceSpeed     : rebonds par seconde            (défaut : 1)
//   bounceAmount    : amplitude du déplacement (UV)  (défaut : 0.03)
//   bounceFreq      : oscillations par rebond        (défaut : 3)
//   bounceDamping   : amortissement (plus grand = s'arrête plus vite, défaut : 4)
//   bounceMode      : 0 = rebond amorti (impulsions), 1 = oscillation continue
//   bounceDirection : axe du mouvement en radians    (défaut : 90° = vertical)
//   bounceCenter    : centre de la région (vec2 UV, défaut 0.5 0.5 — clic gauche
//                     dans le studio)
//   bounceRadius    : demi-axes de la région (vec2 UV, défaut 0.2 0.2)
//   bounceSquash    : squash & stretch (0..1, défaut 0.3 — gonflement synchrone
//                     qui rend le rebond charnu plutôt que glissant)
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


uniform COMPAT_PRECISION float bounceTime;
uniform COMPAT_PRECISION float bounceSpeed;
uniform COMPAT_PRECISION float bounceAmount;
uniform COMPAT_PRECISION float bounceFreq;
uniform COMPAT_PRECISION float bounceDamping;
uniform int bounceMode;
uniform COMPAT_PRECISION float bounceDirection;
uniform COMPAT_PRECISION vec2  bounceCenter;
uniform COMPAT_PRECISION vec2  bounceRadius;
uniform COMPAT_PRECISION float bounceSquash;
uniform int bounceDual;                       // 1 = deux lobes (poitrine/fesses)
uniform COMPAT_PRECISION float bounceSeparation;  // écart entre les lobes (UV, 0 = 0.18)
uniform COMPAT_PRECISION float bounceDesync;      // déphasage du second lobe (0..1)
uniform COMPAT_PRECISION float bounceStagger;     // décalage du 2e lobe le long de l'axe
                                                  // (>0 = lobe droit plus haut, 0 = alignés)
uniform COMPAT_PRECISION float bounceMiddle;      // oscillation centrale 0..1 (comble le
                                                  // creux quand les lobes sont écartés)

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

// Courbe de rebond : ressort amorti (impulsion périodique) ou sinus continu
float bounceCurve(float t, float speed, float freq, float damping)
{
    if (bounceMode == 1) {
        return sin(t * speed * M_PI_2);
    }
    float phase = fract(t * speed);                  // 0..1 par rebond
    return exp(-damping * phase) * sin(M_PI_2 * freq * phase);
}

// Contribution d'un lobe : translation + gonflement (squash & stretch),
// atténuée du centre du lobe (max) vers son bord (zéro, C1 — sans couture)
vec2 lobeOffset(vec2 uv, vec2 lobeCenter, vec2 radius, vec2 axis,
                float motion, float amount, float squash)
{
    vec2 delta = uv - lobeCenter;
    float d = length(delta / max(radius, vec2(1e-5)));
    float w = 1.0 - smoothstep(0.0, 1.0, d);
    return (axis * (motion * amount)
          + delta * (motion * amount * squash * 1.5)) * w;
}

void main(void)
{
    float speed   = (bounceSpeed   == 0.0) ? 1.0  : bounceSpeed;
    float amount  = (bounceAmount  == 0.0) ? 0.03 : bounceAmount;
    float freq    = (bounceFreq    == 0.0) ? 3.0  : bounceFreq;
    float damping = (bounceDamping == 0.0) ? 4.0  : bounceDamping;
    float dirRad  = (bounceDirection == 0.0) ? 1.57079632679 : bounceDirection;
    vec2 center   = (bounceCenter.x == 0.0 && bounceCenter.y == 0.0)
                    ? vec2(0.5, 0.5) : bounceCenter;
    vec2 radius   = (bounceRadius.x == 0.0 && bounceRadius.y == 0.0)
                    ? vec2(0.2, 0.2) : bounceRadius;
    float squash  = (bounceSquash == 0.0) ? 0.3 : bounceSquash;

    vec2 axis = vec2(cos(dirRad), sin(dirRad));
    vec2 offset;

    if (bounceDual == 1) {
        // ── Deux lobes (poitrine/fesses) : chacun a son propre centre de
        // mouvement et de gonflement, séparés perpendiculairement à l'axe
        // du rebond, avec un léger déphasage entre eux ──
        float sep = (bounceSeparation == 0.0) ? 0.18 : bounceSeparation;
        vec2 perp = vec2(axis.y, -axis.x);
        // décalage le long de l'axe : un lobe plus haut que l'autre
        vec2 cL = center - perp * sep * 0.5 - axis * bounceStagger * 0.5;
        vec2 cR = center + perp * sep * 0.5 + axis * bounceStagger * 0.5;

        float mL = bounceCurve(bounceTime, speed, freq, damping);
        float mR = bounceCurve(bounceTime - bounceDesync * 0.25 / max(speed, 0.01),
                               speed, freq, damping);

        offset = lobeOffset(v_tex, cL, radius, axis, mL, amount, squash)
               + lobeOffset(v_tex, cR, radius, axis, mR, amount, squash);

        // oscillation centrale optionnelle : suit la moyenne des deux lobes,
        // comble le creux immobile quand les lobes sont très écartés
        if (bounceMiddle > 0.0) {
            float mM = (mL + mR) * 0.5;
            offset += lobeOffset(v_tex, center, radius, axis,
                                 mM, amount * bounceMiddle, squash);
        }
    } else {
        float motion = bounceCurve(bounceTime, speed, freq, damping);
        offset = lobeOffset(v_tex, center, radius, axis, motion, amount, squash);
    }

    offset *= zoneMask(v_tex);

    vec2 texCoord = clamp(v_tex - offset, vec2(0.0), vec2(1.0));
    FragColor = COMPAT_TEXTURE(u_tex, hbFlipV(texCoord)) * v_col;
}

#endif
