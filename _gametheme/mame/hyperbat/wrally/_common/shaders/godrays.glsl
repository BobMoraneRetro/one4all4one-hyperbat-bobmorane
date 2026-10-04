// HyperBat God Rays Shader
// Rayons divins (l'effet signature des thèmes Saint Seiya : 2270397793,
// 1821615772, 1918678677...). Approximation MONO-PASSE de l'effet
// multi-passes "godrays" de Wallpaper Engine : la passe de cast (30
// échantillons radiaux, pondérés et accumulés) et la passe de composition
// (addition) sont fusionnées dans un seul fragment shader. La passe de flou
// gaussien intermédiaire est omise — l'accumulation de 30 échantillons
// lisse déjà fortement le résultat.
// Effet statique (pas de temps) : les rayons émanent des zones claires de
// l'image ; animer `shader.godraysLength` ou `godraysIntensity` pour les
// faire vivre.
// Compatible ES GLSL shader pipeline.
//
// Uniforms pilotables (storyboard "shader.xxx") — 0 = valeur d'origine WE :
//   godraysCast      : 0 = radial (depuis un point), 1 = directionnel
//   godraysCenter    : centre d'émission (vec2 UV, WE : 0.5 0.5, mode radial)
//   godraysDirection : direction en degrés->radians (WE : 180°, mode directionnel)
//   godraysLength    : longueur des rayons          (WE : 0.5, plage 0.01..1)
//   godraysIntensity : intensité                    (WE : 1, plage 0.01..2)
//   godraysColor     : couleur des rayons (vec4)    (WE : blanc)
//   godraysThreshold : seuil de luminance source (ajout HyperBat : 0 = comme WE,
//                      >0 = seuls les pixels clairs émettent des rayons)
//   godraysBlend     : 0 = addition (WE), 1 = screen, 2 = rayons seuls

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
#define SAMPLE_COUNT 30
#define SAMPLE_DROP 29.0
#define SAMPLE_INTENSITY 0.1

COMPAT_VARYING vec4 v_col;
COMPAT_VARYING vec2 v_tex;

uniform sampler2D u_tex;
vec2 hbFlipV(vec2 p) { return vec2(p.x, 1.0 - p.y); } // HB-FLIPV


uniform int godraysCast;
uniform COMPAT_PRECISION vec2  godraysCenter;
uniform COMPAT_PRECISION float godraysDirection;
uniform COMPAT_PRECISION float godraysLength;
uniform COMPAT_PRECISION float godraysIntensity;
uniform COMPAT_PRECISION vec4  godraysColor;
uniform COMPAT_PRECISION float godraysThreshold;
uniform int godraysBlend;

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

// Un échantillon source, optionnellement filtré par luminance
vec4 raySample(vec2 uv)
{
    vec4 s = COMPAT_TEXTURE(u_tex, hbFlipV(clamp(uv, vec2(0.0), vec2(1.0))));
    if (godraysThreshold > 0.0) {
        float lum = dot(s.rgb, vec3(0.299, 0.587, 0.114));
        s *= smoothstep(godraysThreshold, min(godraysThreshold + 0.2, 1.0), lum);
    }
    return s;
}

void main(void)
{
    vec2 center     = (godraysCenter.x == 0.0 && godraysCenter.y == 0.0)
                      ? vec2(0.5, 0.5) : godraysCenter;
    float rayLength = (godraysLength    == 0.0) ? 0.5 : godraysLength;
    float intensity = (godraysIntensity == 0.0) ? 1.0 : godraysIntensity;
    vec3 rayColor   = (godraysColor.a   == 0.0) ? vec3(1.0, 1.0, 1.0) : godraysColor.rgb;
    float direction = (godraysDirection == 0.0) ? M_PI : godraysDirection;

    vec4 albedo = COMPAT_TEXTURE(u_tex, hbFlipV(v_tex));

    // ── Passe de cast de WE (godrays_cast.frag), fidèle : 30 échantillons
    //    pondérés le long de la direction, accumulés ──
    vec2 texCoords = v_tex;
    vec2 dir;
    if (godraysCast == 1) {
        dir = rotateVec2(vec2(0.0, -0.5), direction - M_PI);
    } else {
        dir = center - texCoords;
    }

    float dist = length(dir);
    dir /= max(dist, 1e-5);

    dist *= rayLength;
    texCoords += dir * dist;

    vec2 stepUV = dir * dist / SAMPLE_DROP;
    vec4 rays = vec4(0.0);
    for (int i = 0; i < SAMPLE_COUNT; ++i)
    {
        rays += raySample(texCoords) * (float(i) / SAMPLE_DROP);
        texCoords -= stepUV;
    }
    rays.rgb *= rayColor;
    rays = vec4(intensity * SAMPLE_INTENSITY * rays.rgb,
                clamp(intensity * SAMPLE_INTENSITY * rays.a, 0.0, 1.0));
    rays *= zoneMask(v_tex);

    // ── Passe de composition de WE (godrays_combine.frag) ──
    if (godraysBlend == 1) {
        // screen
        albedo.rgb = vec3(1.0) - (vec3(1.0) - albedo.rgb) * (vec3(1.0) - clamp(rays.rgb, 0.0, 1.0));
    } else if (godraysBlend == 2) {
        // rayons seuls (BLENDMODE 0 de WE)
        albedo = rays;
    } else {
        // addition (BLENDMODE 9 de WE, défaut) : mix(A, min(A+B,1), alpha)
        albedo.rgb = mix(albedo.rgb, min(albedo.rgb + rays.rgb, vec3(1.0)), rays.a);
    }
    if (godraysBlend != 2) {
        albedo.a = clamp(albedo.a + rays.a, 0.0, 1.0);
    }

    FragColor = albedo * v_col;
}

#endif
