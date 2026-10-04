// HyperBat Shimmer Shader
// Reflet lumineux balayant l'image (effet "sheen"), porté de l'effet
// "shimmer" de Wallpaper Engine. La gradient map est remplacée par une bande
// lumineuse procédurale : aucune texture externe requise.
// Compatible ES GLSL shader pipeline.
//
// Uniforms pilotables (storyboard "shader.xxx") — 0 = valeur d'origine WE :
//   shimmerTime      : temps en secondes (animer 0 -> 3600 sur 3600000 ms, repeat 0)
//   shimmerMode      : 0 = balayage linéaire, 1 = aller-retour (miroir)
//   shimmerDirection : direction du balayage en radians (WE : 1.5708 = vertical)
//   shimmerScale     : granularité                  (WE : 1, plage 1..5)
//   shimmerSpeed     : vitesse                      (WE : 1, plage 0..5)
//   shimmerDelay     : pause entre deux balayages   (WE : 2, plage 1..5)
//   shimmerWidth     : amplitude (mode miroir)      (WE : 1, plage 0..5)
//   shimmerAmount    : luminosité de l'effet        (WE : 1, plage 0..5)
//   shimmerOffset    : décalage                     (WE : 0, plage -1..1)
//   shimmerColor     : couleur du reflet (vec4, alpha 0 = blanc)

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


uniform COMPAT_PRECISION float shimmerTime;
uniform int shimmerMode;
uniform COMPAT_PRECISION float shimmerDirection;
uniform COMPAT_PRECISION float shimmerScale;
uniform COMPAT_PRECISION float shimmerSpeed;
uniform COMPAT_PRECISION float shimmerDelay;
uniform COMPAT_PRECISION float shimmerWidth;
uniform COMPAT_PRECISION float shimmerAmount;
uniform COMPAT_PRECISION float shimmerOffset;
uniform COMPAT_PRECISION vec4  shimmerColor;

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

// Remplace la gradient map "gradient_ferro_fluid" de WE :
// bande lumineuse douce centrée, noire ailleurs.
float gradientBand(float x) {
    return smoothstep(0.15, 0.5, x) * smoothstep(0.85, 0.5, x);
}

void main(void)
{
    float scale  = (shimmerScale  == 0.0) ? 1.0 : shimmerScale;
    float speed  = (shimmerSpeed  == 0.0) ? 1.0 : shimmerSpeed;
    float delay  = (shimmerDelay  == 0.0) ? 2.0 : shimmerDelay;
    float width  = (shimmerWidth  == 0.0) ? 1.0 : shimmerWidth;
    float amount = (shimmerAmount == 0.0) ? 1.0 : shimmerAmount;
    float direction = (shimmerDirection == 0.0) ? 1.57079632679 : shimmerDirection;
    vec3  color  = (shimmerColor.a == 0.0) ? vec3(1.0, 1.0, 1.0) : shimmerColor.rgb;

    vec4 albedo = COMPAT_TEXTURE(u_tex, hbFlipV(v_tex));

    vec2 shimmerCoord = rotateVec2(v_tex, -direction + 1.57079632679) * scale;
    if (shimmerMode == 1) {
        shimmerCoord.x += shimmerOffset + width * sin(speed * shimmerTime);
    } else {
        shimmerCoord.x += shimmerOffset + speed * shimmerTime;
    }
    shimmerCoord.x = clamp(fract(shimmerCoord.x / (scale * delay)) * scale * delay, 0.0, 1.0);

    vec3 shimmerBand = vec3(gradientBand(fract(shimmerCoord.x)));
    vec3 effectAlbedo = shimmerBand * color;

    // Blending 32 de WE : A + A*B (reflet modulé par l'image)
    effectAlbedo = albedo.rgb + albedo.rgb * effectAlbedo;
    albedo.rgb = mix(albedo.rgb, effectAlbedo,
                     clamp(shimmerBand * amount, 0.0, 1.0) * zoneMask(v_tex));

    FragColor = albedo * v_col;
}

#endif
