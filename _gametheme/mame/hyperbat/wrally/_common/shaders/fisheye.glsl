// HyperBat Fisheye Shader
// Distorsion sphérique (loupe/oeil de poisson), porté de l'effet "fisheye"
// de Wallpaper Engine (utilisé par le thème 3735601274 "镜花水月" pour la lune).
// Effet statique : animer `shader.fisheyeDistortion` en storyboard pour un
// effet de zoom/loupe progressif. Compatible ES GLSL shader pipeline.
//
// Uniforms pilotables (storyboard "shader.xxx") — 0 = valeur d'origine WE :
//   fisheyeCenter      : centre de la distorsion (vec2 UV, WE : 0.5 0.5)
//   fisheyeSize        : taille de la sphère     (WE : 1, plage 0.01..1)
//   fisheyeDistortion  : force de la distorsion  (WE : 1, plage 0..2.5,
//                        0.0001 = quasi nulle, >1 = surdistorsion)
//   fisheyeTransparent : 0 = image normale hors de la sphère (WE BACKGROUND=1),
//                        1 = transparent hors de la sphère
//   + masque de zone commun (maskMode/maskCenter/maskSize/maskSoftness/maskInvert)

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

#define M_PI 3.14159265359

COMPAT_VARYING vec4 v_col;
COMPAT_VARYING vec2 v_tex;

uniform sampler2D u_tex;
vec2 hbFlipV(vec2 p) { return vec2(p.x, 1.0 - p.y); } // HB-FLIPV


uniform COMPAT_PRECISION vec2  fisheyeCenter;
uniform COMPAT_PRECISION float fisheyeSize;
uniform COMPAT_PRECISION float fisheyeDistortion;
uniform int fisheyeTransparent;

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
    vec2 center      = (fisheyeCenter.x == 0.0 && fisheyeCenter.y == 0.0)
                       ? vec2(0.5, 0.5) : fisheyeCenter;
    float size       = (fisheyeSize       == 0.0) ? 1.0 : fisheyeSize;
    float distortion = (fisheyeDistortion == 0.0) ? 1.0 : fisheyeDistortion;

    // Projection sphérique (portage fidèle de fisheye.frag de WE)
    float aperture = 178.0;
    float apertureHalf = 0.5 * aperture * (M_PI / 180.0);
    float maxFactor = sin(apertureHalf);

    vec2 uv;
    vec2 xy = (v_tex - center) * 2.0 / size;
    float d = length(xy);
    float alpha = 1.0;
    if (d < (2.0 - maxFactor))
    {
        d = length(xy * maxFactor);
        float z = sqrt(1.0 - d * d);
        float r = atan(d, z) / M_PI;
        float phi = atan(xy.y, xy.x);

        uv.x = r * cos(phi) * size + center.x;
        uv.y = r * sin(phi) * size + center.y;
    }
    else
    {
        uv = v_tex;
        if (fisheyeTransparent == 1) {
            alpha = 0.0;
        }
    }

    float zm = zoneMask(v_tex);
    vec4 albedo = COMPAT_TEXTURE(u_tex, hbFlipV(mix(v_tex, uv, distortion * zm)));
    albedo.a *= mix(1.0, alpha, zm);
    FragColor = albedo * v_col;
}

#endif
