// HyperBat Pulse Shader
// Pulsation de couleur/luminosité, porté de l'effet "pulse" de Wallpaper
// Engine (utilisé par razer_bedroom, virgo no shaka 945419863, Ryu 1918678677).
// Le bruit "util/noise" est remplacé par un bruit procédural.
// Compatible ES GLSL shader pipeline.
//
// Uniforms pilotables (storyboard "shader.xxx") — 0 = valeur d'origine WE :
//   pulseTime    : temps en secondes (animer 0 -> 3600 sur 3600000 ms, repeat 0)
//   pulseSpeed   : vitesse de pulsation        (WE : 3, plage 0..10)
//   pulsePhase   : déphasage                   (WE : 0, plage 0..6.28)
//   pulseAmount  : intensité de la pulsation   (WE : 1, plage 0..2)
//   pulseBounds  : bornes du seuillage (vec2)  (WE : 0 1)
//   noiseSpeed   : vitesse du scintillement    (WE : 0.1)
//   noiseAmount  : quantité de scintillement   (WE : 0, plage 0..2)
//   pulsePower   : exposant                    (WE : 1, plage 0..4)
//   tintLow      : teinte au repos (vec4)      (WE : blanc)
//   tintHigh     : teinte au pic (vec4)        (WE : blanc — mettre une couleur !)
//   pulseAlpha   : 1 = la pulsation module aussi l'alpha (combo PULSEALPHA)
//   pulseBlend   : 0 = addition (WE), 1 = normal, 2 = screen

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


uniform COMPAT_PRECISION float pulseTime;
uniform COMPAT_PRECISION float pulseSpeed;
uniform COMPAT_PRECISION float pulsePhase;
uniform COMPAT_PRECISION float pulseAmount;
uniform COMPAT_PRECISION vec2  pulseBounds;
uniform COMPAT_PRECISION float noiseSpeed;
uniform COMPAT_PRECISION float noiseAmount;
uniform COMPAT_PRECISION float pulsePower;
uniform COMPAT_PRECISION vec4  tintLow;
uniform COMPAT_PRECISION vec4  tintHigh;
uniform int pulseAlpha;
uniform int pulseBlend;

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

void main(void)
{
    float speed  = (pulseSpeed  == 0.0) ? 3.0 : pulseSpeed;
    float amount = (pulseAmount == 0.0) ? 1.0 : pulseAmount;
    float power  = (pulsePower  == 0.0) ? 1.0 : pulsePower;
    float nSpeed = (noiseSpeed  == 0.0) ? 0.1 : noiseSpeed;
    vec2 bounds  = (pulseBounds.x == 0.0 && pulseBounds.y == 0.0) ? vec2(0.0, 1.0) : pulseBounds;
    vec3 cLow    = (tintLow.a  == 0.0) ? vec3(1.0, 1.0, 1.0) : tintLow.rgb;
    vec3 cHigh   = (tintHigh.a == 0.0) ? vec3(1.0, 1.0, 1.0) : tintHigh.rgb;

    vec4 albedo = COMPAT_TEXTURE(u_tex, hbFlipV(v_tex));
    vec4 baseColor = albedo;

    float pulse = smoothstep(bounds.x, bounds.y,
                             sin(pulseTime * speed + pulsePhase) * 0.5 + 0.5) * amount;
    // Scintillement : remplace la texture util/noise de WE
    pulse += noise(vec2(pulseTime, pulseTime * 0.333) * nSpeed * 256.0) * noiseAmount;
    pulse = pow(max(pulse, 0.0), power);

    vec3 low  = albedo.rgb * cLow;
    vec3 high = albedo.rgb * cHigh;

    // Modes de fusion : 0 = addition (BLENDMODE 9 de WE), 1 = normal, 2 = screen
    vec3 blended;
    if (pulseBlend == 1) {
        blended = high;
    } else if (pulseBlend == 2) {
        blended = vec3(1.0) - (vec3(1.0) - low) * (vec3(1.0) - high);
    } else {
        blended = min(low + high, vec3(1.0));
    }
    albedo.rgb = clamp(mix(low, blended, clamp(pulse, 0.0, 1.0)), 0.0, 1.0);

    if (pulseAlpha == 1) {
        albedo.a *= clamp(pulse, 0.0, 1.0);
    }

    // équivalent du "mix(sample, albedo, mask)" de WE
    albedo = mix(baseColor, albedo, zoneMask(v_tex));

    FragColor = albedo * v_col;
}

#endif
