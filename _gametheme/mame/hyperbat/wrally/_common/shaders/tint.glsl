// HyperBat Tint Shader
// Teinte l'image avec une couleur, porté de l'effet "tint" du projet
// razer_bedroom de Wallpaper Engine. Effet statique (pas de temps).
// Compatible ES GLSL shader pipeline.
//
// Uniforms pilotables (storyboard "shader.xxx") — 0 = valeur d'origine WE :
//   tintColor : couleur de teinte (vec4)   (WE : rouge "1 0 0")
//   tintAlpha : force du mélange           (WE : 1, plage 0..1)
//   tintMode  : 0 = teinte (BLENDMODE 30 de WE : canal max * couleur),
//               1 = multiplication, 2 = remplacement (mix simple)

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


uniform COMPAT_PRECISION vec4  tintColor;
uniform COMPAT_PRECISION float tintAlpha;
uniform int tintMode;

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
    vec3 color  = (tintColor.a == 0.0) ? vec3(1.0, 0.0, 0.0) : tintColor.rgb;
    float alpha = (tintAlpha == 0.0) ? 1.0 : tintAlpha;

    vec4 albedo = COMPAT_TEXTURE(u_tex, hbFlipV(v_tex));

    vec3 tinted;
    if (tintMode == 1) {
        tinted = albedo.rgb * color;                                  // multiplication
    } else if (tintMode == 2) {
        tinted = color;                                               // remplacement
    } else {
        // BlendTint de WE : luminance (canal max) * couleur
        tinted = vec3(max(albedo.r, max(albedo.g, albedo.b))) * color;
    }
    albedo.rgb = mix(albedo.rgb, tinted, clamp(alpha, 0.0, 1.0) * zoneMask(v_tex));

    FragColor = albedo * v_col;
}

#endif
