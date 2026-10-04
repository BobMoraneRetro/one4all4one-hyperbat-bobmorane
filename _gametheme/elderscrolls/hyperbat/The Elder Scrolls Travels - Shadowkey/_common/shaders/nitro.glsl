// HyperBat Nitro Shader
// Aura d'énergie turbulente (utilisé par virgo no shaka 945419863 et les
// thèmes Saint Seiya), porté de l'effet "nitro" de Wallpaper Engine.
// La texture de nuages "util/clouds_256" est remplacée par un bruit fractal
// procédural ; le paramètre smoothness (LOD de mip-map dans WE) atténue les
// octaves fines. Compatible ES GLSL shader pipeline.
//
// Uniforms pilotables (storyboard "shader.xxx") — 0 = valeur d'origine WE :
//   nitroTime       : temps en secondes (animer 0 -> 3600 sur 3600000 ms, repeat 0)
//   nitroSpeed1     : défilement couche 1 (vec2)  (WE : -0.1 0.7)
//   nitroSpeed2     : défilement couche 2 (vec2)  (WE : 0.1 -0.5)
//   nitroScales     : échelles des couches (vec2) (WE : 1 2)
//   nitroMultiply   : intensité                   (WE : 1, plage 0.01..10)
//   nitroColorStart : couleur de base (vec4)      (WE : bleu "0 0.5 1")
//   nitroColorEnd   : couleur du coeur (vec4)     (WE : blanc)
//   nitroBounds     : bornes du seuillage (vec2)  (WE : 0.3 0.25)
//   nitroSmoothness : lissage (0..5)              (WE : 1)
//   nitroBlend      : 0 = glow (BLENDMODE 22 WE), 1 = addition, 2 = screen
//
// Le moteur doit fournir textureSize (ratio d'aspect des couches).

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
COMPAT_VARYING   vec4 v_nitro;

uniform COMPAT_PRECISION vec2 textureSize;
uniform COMPAT_PRECISION float nitroTime;
uniform COMPAT_PRECISION vec2 nitroSpeed1;
uniform COMPAT_PRECISION vec2 nitroSpeed2;
uniform COMPAT_PRECISION vec2 nitroScales;

void main(void)
{
    vec2 hbTexCoord = vec2(TexCoord.x, 1.0 - TexCoord.y); // HB-FLIPV: ES texcoords -> espace effet (toutes varyings géométriques conjuguées)
    gl_Position = MVPMatrix * vec4(VertexCoord.xy, 0.0, 1.0);
    v_tex       = hbTexCoord;
    v_col       = COLOR;

    vec2 speed1 = (nitroSpeed1.x == 0.0 && nitroSpeed1.y == 0.0) ? vec2(-0.1, 0.7) : nitroSpeed1;
    vec2 speed2 = (nitroSpeed2.x == 0.0 && nitroSpeed2.y == 0.0) ? vec2(0.1, -0.5) : nitroSpeed2;
    vec2 scales = (nitroScales.x == 0.0) ? vec2(1.0, 2.0) : nitroScales;

    float aspect = (textureSize.y == 0.0) ? 1.0 : (textureSize.x / textureSize.y);

    v_nitro.xy = hbTexCoord * scales.x + nitroTime * speed1;
    v_nitro.zw = hbTexCoord * scales.y + nitroTime * speed2;
    v_nitro.xz *= aspect;
    // la seconde couche est tournée de 90° (comme WE)
    v_nitro.zw = vec2(-v_nitro.w, v_nitro.z);
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
COMPAT_VARYING vec4 v_nitro;

uniform sampler2D u_tex;
vec2 hbFlipV(vec2 p) { return vec2(p.x, 1.0 - p.y); } // HB-FLIPV


uniform COMPAT_PRECISION float nitroMultiply;
uniform COMPAT_PRECISION vec4  nitroColorStart;
uniform COMPAT_PRECISION vec4  nitroColorEnd;
uniform COMPAT_PRECISION vec2  nitroBounds;
uniform COMPAT_PRECISION float nitroSmoothness;
uniform int nitroBlend;

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

// Remplace "util/clouds_256" : bruit fractal dont les octaves fines
// s'estompent avec lod (équivalent du texSample2DLod de WE).
float clouds(vec2 uv, float lod) {
    uv *= 6.0;
    float octave2 = clamp(1.0 - lod / 2.5, 0.0, 1.0);
    float octave3 = clamp(1.0 - lod / 1.2, 0.0, 1.0);
    float v = noise(uv) * 0.55
            + noise(uv * 2.31) * 0.30 * octave2
            + noise(uv * 5.17) * 0.15 * octave3;
    return v / (0.55 + 0.30 * octave2 + 0.15 * octave3);
}

void main(void)
{
    float multiply = (nitroMultiply == 0.0) ? 1.0 : nitroMultiply;
    vec3 color0 = (nitroColorStart.a == 0.0) ? vec3(0.0, 0.5, 1.0) : nitroColorStart.rgb;
    vec3 color1 = (nitroColorEnd.a   == 0.0) ? vec3(1.0, 1.0, 1.0) : nitroColorEnd.rgb;
    vec2 bounds = (nitroBounds.x == 0.0 && nitroBounds.y == 0.0) ? vec2(0.3, 0.25) : nitroBounds;
    float lod   = (nitroSmoothness == 0.0) ? 1.0 : nitroSmoothness;

    vec4 albedo = COMPAT_TEXTURE(u_tex, hbFlipV(v_tex));

    float nitro0 = clouds(v_nitro.xy, lod);
    float nitro1 = clouds(v_nitro.zw, lod);
    float remap  = clouds(v_tex, 0.0);

    float coreNoise = smoothstep(nitro0, nitro1, 0.1 + remap * 0.8);
    float nitro = smoothstep(bounds.y, bounds.x, nitro0 * nitro1)
                * smoothstep(bounds.x, bounds.y, nitro0 * nitro1);
    nitro = coreNoise * nitro * 4.0;

    vec3 nitroColor = mix(color0, color1, clamp(nitro, 0.0, 1.0));
    float blend = clamp(nitro * multiply, 0.0, 1.0) * zoneMask(v_tex);

    vec3 result;
    if (nitroBlend == 1) {
        result = min(albedo.rgb + nitroColor, vec3(1.0));                // addition
    } else if (nitroBlend == 2) {
        result = vec3(1.0) - (vec3(1.0) - albedo.rgb) * (vec3(1.0) - nitroColor);  // screen
    } else {
        // BlendGlow de WE (BLENDMODE 22) : Reflect(blend, base) par canal
        vec3 b = clamp(albedo.rgb, 0.0, 0.999);
        result = min(nitroColor * nitroColor / (vec3(1.0) - b), vec3(1.0));
    }
    albedo.rgb = max(mix(albedo.rgb, result, blend), 0.0);

    FragColor = albedo * v_col;
}

#endif
