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
COMPAT_VARYING   vec2 v_pos;

void main(void)                                     
{                                                   
    gl_Position = MVPMatrix * vec4(VertexCoord.xy, 0.0, 1.0);
    v_tex       = TexCoord;                           
    v_col       = COLOR;                           
    v_pos       = VertexCoord;
}

#elif defined(FRAGMENT)

// fwidth() requis pour l'antialiasing des bordures (GLSL ES 1.0)
#extension GL_OES_standard_derivatives : enable

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

COMPAT_VARYING   vec4      v_col;
COMPAT_VARYING   vec2      v_tex;
COMPAT_VARYING   vec2      v_pos;

uniform sampler2D u_tex;
uniform vec2 resolution;
uniform vec2 textureSize;
uniform vec2 outputSize;
uniform vec2 outputOffset;

// Bordure 1
uniform float borderSize;
uniform vec4  borderColor;
uniform vec4  borderColorStart;
uniform vec4  borderColorEnd;

// Bordure 2
uniform float borderSize2;
uniform vec4  borderColor2;
uniform vec4  borderColorStart2;
uniform vec4  borderColorEnd2;

// Bordure 3
uniform float borderSize3;
uniform vec4  borderColor3;
uniform vec4  borderColorStart3;
uniform vec4  borderColorEnd3;

// Autres paramètres
uniform float cornerRadius;
uniform float innerShadowSize;
uniform vec4  innerShadowColor;
uniform float outerShadowSize;
uniform vec4  outerShadowColor;
uniform float saturation;
uniform int    gradientMode;
uniform bool   bilinearFiltering;

vec4 sampleTexture(sampler2D tex, vec2 texCoord) {
    return COMPAT_TEXTURE(tex, texCoord);
}

float getComputedValue(float value, float defaultValue) {
    if (value == 0.0)
        return defaultValue;
    if (value < 1.0)
        return abs(outputSize.y) * value;
    return value;
}

vec4 getGradientColor(vec4 c1, vec4 c2, vec2 uv) {
    float t;
    if (gradientMode == 1) {
        t = uv.x;
    } else if (gradientMode == 2) {
        t = (uv.x + uv.y) * 0.5;
    } else if (gradientMode == 3) {
        t = (uv.x + (1.0 - uv.y)) * 0.5;
    } else if (gradientMode == 4) {
        vec2 center = vec2(0.5);
        float dist = distance(uv, center);
        t = dist * 1.414;
    } else {
        t = uv.y;
    }
    return mix(c1, c2, clamp(t, 0.0, 1.0));
}

// Poids d'un anneau SDF entre deux seuils (outer = côté silhouette, inner = plus profond)
float ringWeight(float d, float outer, float inner, float aa) {
    float wShallow = 1.0 - smoothstep(outer - aa, outer + aa, d);
    float wDeep    = smoothstep(inner - aa, inner + aa, d);
    return wShallow * wDeep;
}

vec4 evalOuterShadow(float d, float os) {
    vec4 c = outerShadowColor * v_col;
    if (os > 0.0)
        c.a *= clamp(1.0 - (os + d) / os, 0.0, 1.0);
    return c;
}

vec4 evalInnerShadow(vec4 content, float d, float b1, float b2, float b3, float os, float is) {
    float val = abs(b1 + b2 + b3 + os + d) / is;
    val = clamp(val, 0.0, 1.0);
    return mix(content, innerShadowColor * v_col, innerShadowColor.a * (1.0 - val));
}

vec4 evalBorder1(vec2 gradUV) {
    vec4 c = (borderColorStart != borderColorEnd)
        ? getGradientColor(borderColorStart, borderColorEnd, gradUV)
        : borderColor;
    return c * v_col;
}

vec4 evalBorder2(vec2 gradUV) {
    vec4 c = (borderColorStart2 != borderColorEnd2)
        ? getGradientColor(borderColorStart2, borderColorEnd2, gradUV)
        : borderColor2;
    return c * v_col;
}

vec4 evalBorder3(vec2 gradUV) {
    vec4 c = (borderColorStart3 != borderColorEnd3)
        ? getGradientColor(borderColorStart3, borderColorEnd3, gradUV)
        : borderColor3;
    return c * v_col;
}

void main(void)
{
    float b1 = getComputedValue(borderSize, 0.0);
    float b2 = getComputedValue(borderSize2, 0.0);
    float b3 = getComputedValue(borderSize3, 0.0);
    float innerShadow = getComputedValue(innerShadowSize, 0.0);
    float outerShadow = getComputedValue(outerShadowSize, 0.0);
    float cornerSize = getComputedValue(cornerRadius, 0.0);

    // --- CORRECTION 1: OPTIMISATION TRANSPARENCE ---
    // Si on sort prématurément, il faut quand même appliquer v_col
    if (sampleTexture(u_tex, vec2(1.0)).a < 0.3 || sampleTexture(u_tex, vec2(0.0)).a < 0.3) {
        FragColor = sampleTexture(u_tex, v_tex) * v_col;
        return;
    }

    // Rétrécir la vidéo/image de la somme des bordures (b1+b2+b3) pour qu'elles
    // s'affichent autour du contenu au lieu de passer par-dessus. L'ombre
    // intérieure reste en overlay sur le bord du contenu (non incluse ici).
    float borderSum = b1 + b2 + b3;

    vec2 decal = vec2(
        borderSum / abs(outputSize.x),
        borderSum / abs(outputSize.y)
    );
    decal = min(decal, vec2(0.49));

    float denomX = max(1.0 - 2.0 * decal.x, 0.02);
    float denomY = max(1.0 - 2.0 * decal.y, 0.02);

    vec2 adjustedTexCoord = vec2(
        (v_tex.x - decal.x) / denomX,
        (v_tex.y - decal.y) / denomY
    );

    vec2 gradientUV = adjustedTexCoord;

    vec4 sampledColor = sampleTexture(u_tex, adjustedTexCoord);

    if (bilinearFiltering)
    {
        vec2 texelSize = 1.0 / textureSize;
        vec2 uv_coord = adjustedTexCoord;
        vec2 f = fract(uv_coord);

        vec4 texel00 = sampleTexture(u_tex, uv_coord);
        vec4 texel10 = sampleTexture(u_tex, uv_coord + vec2(texelSize.x, 0.0));
        vec4 texel01 = sampleTexture(u_tex, uv_coord + vec2(0.0, texelSize.y));
        vec4 texel11 = sampleTexture(u_tex, uv_coord + texelSize);

        sampledColor = mix(
            mix(texel00, texel10, f.x),
            mix(texel01, texel11, f.x),
            f.y
        );
    }

    if (saturation != 1.0) {
        vec3 gray = vec3(dot(sampledColor.rgb, vec3(0.34, 0.55, 0.11)));
        vec3 blend = mix(gray, sampledColor.rgb, saturation);
        sampledColor = vec4(blend, sampledColor.a);
    }

    // --- CORRECTION 2: APPLICATION v_col SUR LE CONTENU ---
    sampledColor *= v_col;

    vec2 middle = vec2(abs(outputSize.x), abs(outputSize.y)) / 2.0;
    vec2 center = abs(v_pos - outputOffset - middle);
    vec2 q = center - middle + cornerSize;
    float distValue = length(max(q, 0.0)) + min(max(q.x, q.y), 0.0) - cornerSize;

    // ── Antialiasing : poids par anneau (silhouette, ombres, bordures, contenu) ──
    float aa = max(fwidth(distValue), 1.0);

    float tSilhouette = 0.0;
    float tOS  = -outerShadow;
    float tB1  = -(b1 + outerShadow);
    float tB2  = -(b1 + b2 + outerShadow);
    float tB3  = -(b1 + b2 + b3 + outerShadow);
    float tIS  = tB3 - innerShadow;

    float contentOuter = (innerShadow > 0.0) ? tIS : tB3;

    float wOS = (outerShadow > 0.0)
        ? ringWeight(distValue, tSilhouette, tOS, aa) : 0.0;
    float outerB1 = (outerShadow > 0.0) ? tOS : tSilhouette;
    float wB1 = (b1 > 0.0)
        ? ringWeight(distValue, outerB1, tB1, aa) : 0.0;
    float wB2 = (b2 > 0.0)
        ? ringWeight(distValue, tB1, tB2, aa) : 0.0;
    float wB3 = (b3 > 0.0)
        ? ringWeight(distValue, tB2, tB3, aa) : 0.0;
    float wIS = (innerShadow > 0.0)
        ? ringWeight(distValue, tB3, tIS, aa) : 0.0;
    float wContent = ringWeight(distValue, contentOuter, contentOuter - 1e6, aa);

    float totalW = wOS + wB1 + wB2 + wB3 + wIS + wContent;
    if (totalW < 0.001) {
        FragColor = vec4(0.0);
        return;
    }

    vec4 result = vec4(0.0);
    if (wOS > 0.0)
        result += evalOuterShadow(distValue, outerShadow) * wOS;
    if (wB1 > 0.0)
        result += evalBorder1(gradientUV) * wB1;
    if (wB2 > 0.0)
        result += evalBorder2(gradientUV) * wB2;
    if (wB3 > 0.0)
        result += evalBorder3(gradientUV) * wB3;
    if (wIS > 0.0)
        result += evalInnerShadow(sampledColor, distValue, b1, b2, b3, outerShadow, innerShadow) * wIS;
    result += sampledColor * wContent;

    FragColor = result;
}
#endif