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
uniform int   gradientMode;
uniform bool  bilinearFiltering;

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

void main(void)
{
    float b1 = getComputedValue(borderSize, 0.0);
    float b2 = getComputedValue(borderSize2, 0.0);
    float b3 = getComputedValue(borderSize3, 0.0);
    float innerShadow = getComputedValue(innerShadowSize, 0.0);
    float outerShadow = getComputedValue(outerShadowSize, 0.0);
    float cornerSize = getComputedValue(cornerRadius, 0.0);

    // Détection transparence (optimisation)
    if (sampleTexture(u_tex, vec2(1.0)).a < 0.3 || sampleTexture(u_tex, vec2(0.0)).a < 0.3) {
        FragColor = sampleTexture(u_tex, v_tex);
        return;
    }

    // Décalage texture (bordures et ombres)
    float totalPadding = b1 + outerShadow;
    if (b2 > 0.0) totalPadding += b2;
    if (b3 > 0.0) totalPadding += b3;

    vec2 decal = vec2(
        (b1 / 2.0 + outerShadow) / abs(outputSize.x),
        (b1 / 2.0 + outerShadow) / abs(outputSize.y)
    );

    vec2 adjustedTexCoord = vec2(
        v_tex.x / (1.0 - 2.0 * decal.x) - decal.x,
        v_tex.y * (1.0 + 2.0 * decal.y) - decal.y
    );

    vec2 gradientUV = vec2(
        (v_tex.x - decal.x) / (1.0 - 2.0 * decal.x),
        (v_tex.y - decal.y) / (1.0 - 2.0 * decal.y)
    );

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

        vec4 interpolatedColor = mix(
            mix(texel00, texel10, f.x),
            mix(texel01, texel11, f.x),
            f.y
        );

        sampledColor = interpolatedColor;
    }

    if (saturation != 1.0) {
        vec3 gray = vec3(dot(sampledColor.rgb, vec3(0.34, 0.55, 0.11)));
        vec3 blend = mix(gray, sampledColor.rgb, saturation);
        sampledColor = vec4(blend, sampledColor.a);
    }

    sampledColor *= v_col;

    vec2 middle = vec2(abs(outputSize.x), abs(outputSize.y)) / 2.0;
    vec2 center = abs(v_pos - outputOffset - middle);
    vec2 q = center - middle + cornerSize;
    float distance = length(max(q, 0.0)) + min(max(q.x, q.y), 0.0) - cornerSize;

    float totalBorder = b1 + b2 + b3 + innerShadow + outerShadow;
    float effectiveBorder = b1 + outerShadow;

    if (distance > 0.0) {
        discard;
    } 
    else if (distance > -totalBorder) {
        if (outerShadow > 0.0 && distance > -outerShadow) {
            sampledColor = outerShadowColor;
            sampledColor.a *= (1.0 - (outerShadow + distance) / outerShadow) * v_col.a;
        } 
        else if (distance > -(b1 + outerShadow)) {
            sampledColor = (borderColorStart != borderColorEnd)
                ? getGradientColor(borderColorStart, borderColorEnd, gradientUV)
                : borderColor;
            sampledColor.a *= v_col.a;
        } 
        else if (distance > -(b1 + b2 + outerShadow)) {
            sampledColor = (borderColorStart2 != borderColorEnd2)
                ? getGradientColor(borderColorStart2, borderColorEnd2, gradientUV)
                : borderColor2;
            sampledColor.a *= v_col.a;
        } 
        else if (distance > -(b1 + b2 + b3 + outerShadow)) {
            sampledColor = (borderColorStart3 != borderColorEnd3)
                ? getGradientColor(borderColorStart3, borderColorEnd3, gradientUV)
                : borderColor3;
            sampledColor.a *= v_col.a;
        } 
        else if (innerShadow > 0.0 && distance > -(b1 + b2 + b3 + outerShadow + innerShadow)) {
            float val = abs(b1 + b2 + b3 + outerShadow + distance) / innerShadow;
            val = clamp(val, 0.0, 1.0);
            sampledColor = mix(sampledColor, innerShadowColor, innerShadowColor.a * (1.0 - val));
        }
    } 
    else {
        float pixelValue = 1.0 - smoothstep(-0.75, 0.5, distance);
        sampledColor.a *= pixelValue;
        sampledColor.rgb *= pixelValue;
    }

    FragColor = sampledColor;
}
#endif
