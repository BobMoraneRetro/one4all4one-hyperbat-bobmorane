// HyperBat Bounce Shader (rebond / jiggle) — version multi-groupes indépendants.
// Fait rebondir jusqu'à 3 RÉGIONS de l'image (ex. poitrine, fessier, joues…),
// chacune en 1 ou 2 lobes, dans UN SEUL shader (RetroBat n'autorise qu'un
// <shader> par élément). CHAQUE GROUPE est autonome : tailles de lobe (par
// lobe), écart, axe, position ET sa propre animation (vitesse, amplitude,
// fréquence, amortissement, fenêtre, recul élastique, squash, phase).
// Physique : impulsion amortie (ou oscillation continue) + recul élastique
// (overshoot) + fenêtre [start, end] (pause entre rebonds), squash & stretch.
// Le déplacement est maximal au centre d'un lobe et s'éteint en douceur au
// bord (atténuation C1) : AUCUNE couture — le lobe EST sa propre zone.
// Compatible ES GLSL shader pipeline (⚠ pas de mots réservés ES 3.00).
//
// Uniforms GLOBAUX :
//   bounceTime      : temps en s (animer 0 -> 3600 sur 3600000 ms, repeat 0)
//   bounceIntensity : enveloppe maître 0..1 (timeline apparition/disparition)
// Uniforms PAR GROUPE g = 1..3 :
//   bounceG{g}Mode      : 0 = désactivé, 1 = 1 lobe, 2 = 2 lobes
//   bounceG{g}Size1/2   : demi-axes des lobes 1 et 2 (vec2 UV)
//   bounceG{g}Sep       : écart des 2 lobes (mode 2 lobes)
//   bounceG{g}Dir       : axe du mouvement (radians)
//   bounceG{g}Splay     : divergence des 2 lobes (radians, ±)
//   bounceG{g}Center    : centre du groupe (vec2 UV)
//   bounceG{g}AnimMode  : 0 = amorti, 1 = oscillation continue
//   bounceG{g}Speed/Amount/Freq/Damp/Start/End/Overshoot/Squash : courbe
//   bounceG{g}Phase     : déphasage 0..1 (désync entre groupes)

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
    vec2 hbTexCoord = vec2(TexCoord.x, 1.0 - TexCoord.y); // HB-FLIPV: ES texcoords -> espace effet
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
uniform COMPAT_PRECISION float bounceIntensity;

// — Groupe 1 —
uniform int bounceG1Mode; uniform COMPAT_PRECISION vec2 bounceG1Size1; uniform COMPAT_PRECISION vec2 bounceG1Size2;
uniform COMPAT_PRECISION float bounceG1Sep; uniform COMPAT_PRECISION float bounceG1Dir; uniform COMPAT_PRECISION float bounceG1Splay;
uniform COMPAT_PRECISION vec2 bounceG1Center; uniform int bounceG1AnimMode;
uniform COMPAT_PRECISION float bounceG1Speed; uniform COMPAT_PRECISION float bounceG1Amount; uniform COMPAT_PRECISION float bounceG1Freq;
uniform COMPAT_PRECISION float bounceG1Damp; uniform COMPAT_PRECISION float bounceG1Start; uniform COMPAT_PRECISION float bounceG1End;
uniform COMPAT_PRECISION float bounceG1Overshoot; uniform COMPAT_PRECISION float bounceG1Squash; uniform COMPAT_PRECISION float bounceG1Phase;
// — Groupe 2 —
uniform int bounceG2Mode; uniform COMPAT_PRECISION vec2 bounceG2Size1; uniform COMPAT_PRECISION vec2 bounceG2Size2;
uniform COMPAT_PRECISION float bounceG2Sep; uniform COMPAT_PRECISION float bounceG2Dir; uniform COMPAT_PRECISION float bounceG2Splay;
uniform COMPAT_PRECISION vec2 bounceG2Center; uniform int bounceG2AnimMode;
uniform COMPAT_PRECISION float bounceG2Speed; uniform COMPAT_PRECISION float bounceG2Amount; uniform COMPAT_PRECISION float bounceG2Freq;
uniform COMPAT_PRECISION float bounceG2Damp; uniform COMPAT_PRECISION float bounceG2Start; uniform COMPAT_PRECISION float bounceG2End;
uniform COMPAT_PRECISION float bounceG2Overshoot; uniform COMPAT_PRECISION float bounceG2Squash; uniform COMPAT_PRECISION float bounceG2Phase;
// — Groupe 3 —
uniform int bounceG3Mode; uniform COMPAT_PRECISION vec2 bounceG3Size1; uniform COMPAT_PRECISION vec2 bounceG3Size2;
uniform COMPAT_PRECISION float bounceG3Sep; uniform COMPAT_PRECISION float bounceG3Dir; uniform COMPAT_PRECISION float bounceG3Splay;
uniform COMPAT_PRECISION vec2 bounceG3Center; uniform int bounceG3AnimMode;
uniform COMPAT_PRECISION float bounceG3Speed; uniform COMPAT_PRECISION float bounceG3Amount; uniform COMPAT_PRECISION float bounceG3Freq;
uniform COMPAT_PRECISION float bounceG3Damp; uniform COMPAT_PRECISION float bounceG3Start; uniform COMPAT_PRECISION float bounceG3End;
uniform COMPAT_PRECISION float bounceG3Overshoot; uniform COMPAT_PRECISION float bounceG3Squash; uniform COMPAT_PRECISION float bounceG3Phase;
// Douceur du bord des lobes (1 = fondu depuis le centre = défaut ; 0 = bord net)
uniform COMPAT_PRECISION float bounceG1Soft;
uniform COMPAT_PRECISION float bounceG2Soft;
uniform COMPAT_PRECISION float bounceG3Soft;

// Courbe d'un groupe : ressort amorti (impulsion) ou sinus continu, avec
// fenêtre [start, end] (pause hors fenêtre) + overshoot (2e harmonique).
float bounceCurveG(float t, int amode, float speed, float freq, float damping,
                   float startW, float endW, float overshoot)
{
    if (amode == 1) {
        return sin(t * speed * M_PI_2);
    }
    float phase = fract(t * speed);
    float wEnd  = (endW == 0.0) ? 1.0 : endW;
    if (phase < startW || phase > wEnd) return 0.0;
    float u = (phase - startW) / max(wEnd - startW, 1e-3);
    float base   = sin(M_PI_2 * freq * u);
    float recoil = overshoot * sin(M_PI_2 * u);
    return exp(-damping * u) * (base + recoil);
}

// Contribution d'un lobe : translation + squash & stretch ANISOTROPE (étire le
// long de l'axe de mouvement, comprime perpendiculairement — vrai jiggle), le
// tout atténué du centre du lobe (max) vers son bord (zéro, C1 — sans couture).
vec2 lobeOffset(vec2 uv, vec2 lobeCenter, vec2 radius, vec2 axis,
                float motion, float amount, float squash, float soft)
{
    vec2 delta = uv - lobeCenter;
    float d = length(delta / max(radius, vec2(1e-5)));
    // soft 1 = fondu depuis le centre (cloche, défaut) ; soft 0 = coeur plein +
    // bord net. `core` = rayon où le fondu commence (toujours une fine bande C1).
    float core = min(0.95, 1.0 - clamp(soft, 0.0, 1.0));
    float w = 1.0 - smoothstep(core, 1.0, d);
    // Translation le long de l'axe.
    vec2 trans = axis * (motion * amount);
    // Squash & stretch : étirement directionnel indépendant de l'amplitude — étire
    // le long de l'axe (along) et comprime perpendiculairement (across), pour que le
    // réglage soit RÉELLEMENT visible (l'ancien terme radial × amount était minuscule).
    vec2 perp = vec2(-axis.y, axis.x);
    float along  = dot(delta, axis);
    float across = dot(delta, perp);
    float s = motion * squash * 0.4;
    vec2 stretch = axis * (along * s) - perp * (across * s);
    return (trans + stretch) * w;
}

// Contribution d'un groupe entier (1 ou 2 lobes, animation propre).
vec2 groupOffset(vec2 uv, int gmode, vec2 center, vec2 size1, vec2 size2,
                 float sep, float gdir, float splay, float phase, float soft,
                 int amode, float speed, float amount, float freq, float damping,
                 float startW, float endW, float overshoot, float squash)
{
    if (gmode < 1) return vec2(0.0);
    float sp = (speed   == 0.0) ? 1.0  : speed;
    float am = (amount  == 0.0) ? 0.03 : amount;
    float fq = (freq    == 0.0) ? 3.0  : freq;
    float dp = (damping == 0.0) ? 4.0  : damping;
    float sq = (squash  == 0.0) ? 0.3  : squash;
    float dir= (gdir    == 0.0) ? 1.57079632679 : gdir;
    vec2  r1 = (size1.x == 0.0 && size1.y == 0.0) ? vec2(0.2, 0.2) : size1;

    float motion = bounceCurveG(bounceTime - phase / max(sp, 0.01),
                                amode, sp, fq, dp, startW, endW, overshoot)
                   * bounceIntensity;        // enveloppe maître

    if (gmode == 1) {
        vec2 axis = vec2(cos(dir), sin(dir));
        return lobeOffset(uv, center, r1, axis, motion, am, sq, soft);
    }
    vec2 r2    = (size2.x == 0.0 && size2.y == 0.0) ? vec2(0.2, 0.2) : size2;
    float s    = (sep == 0.0) ? 0.18 : sep;
    vec2 axisM = vec2(cos(dir), sin(dir));
    vec2 perp  = vec2(axisM.y, -axisM.x);
    vec2 cL    = center - perp * s * 0.5;
    vec2 cR    = center + perp * s * 0.5;
    vec2 axisL = vec2(cos(dir - splay), sin(dir - splay));
    vec2 axisR = vec2(cos(dir + splay), sin(dir + splay));
    return lobeOffset(uv, cL, r1, axisL, motion, am, sq, soft)
         + lobeOffset(uv, cR, r2, axisR, motion, am, sq, soft);
}

void main(void)
{
    vec2 offset =
          groupOffset(v_tex, bounceG1Mode, bounceG1Center, bounceG1Size1, bounceG1Size2, bounceG1Sep, bounceG1Dir, bounceG1Splay, bounceG1Phase, bounceG1Soft, bounceG1AnimMode, bounceG1Speed, bounceG1Amount, bounceG1Freq, bounceG1Damp, bounceG1Start, bounceG1End, bounceG1Overshoot, bounceG1Squash)
        + groupOffset(v_tex, bounceG2Mode, bounceG2Center, bounceG2Size1, bounceG2Size2, bounceG2Sep, bounceG2Dir, bounceG2Splay, bounceG2Phase, bounceG2Soft, bounceG2AnimMode, bounceG2Speed, bounceG2Amount, bounceG2Freq, bounceG2Damp, bounceG2Start, bounceG2End, bounceG2Overshoot, bounceG2Squash)
        + groupOffset(v_tex, bounceG3Mode, bounceG3Center, bounceG3Size1, bounceG3Size2, bounceG3Sep, bounceG3Dir, bounceG3Splay, bounceG3Phase, bounceG3Soft, bounceG3AnimMode, bounceG3Speed, bounceG3Amount, bounceG3Freq, bounceG3Damp, bounceG3Start, bounceG3End, bounceG3Overshoot, bounceG3Squash);

    vec2 texCoord = clamp(v_tex - offset, vec2(0.0), vec2(1.0));
    FragColor = COMPAT_TEXTURE(u_tex, hbFlipV(texCoord)) * v_col;
}

#endif
