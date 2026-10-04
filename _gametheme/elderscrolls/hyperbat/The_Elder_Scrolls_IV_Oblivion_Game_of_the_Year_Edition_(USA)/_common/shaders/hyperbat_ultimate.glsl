// HyperBat Ultimate Filter Shader
// Combines image filters (brightness, contrast, saturation, grayscale, sepia, pixelate)
// with the legacy border/shadow system from ThemeBat
// Compatible with ES GLSL shader pipeline

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

COMPAT_VARYING vec4 v_col;
COMPAT_VARYING vec2 v_tex;
COMPAT_VARYING vec2 v_pos;

uniform sampler2D u_tex;
uniform vec2 resolution;
uniform vec2 textureSize;
uniform vec2 outputSize;
uniform vec2 outputOffset;

// ── HyperBat Image Filters ──
uniform float filterBrightness;  // 0.0=black, 1.0=normal, >1.0=bright (default 1.0)
uniform float filterContrast;    // 0.0=grey, 1.0=normal, >1.0=high (default 1.0)
uniform float filterSaturation;  // 0.0=grayscale, 1.0=normal, >1.0=vivid (default 1.0)
uniform float filterSepia;       // 0.0=off, 1.0=full sepia (default 0.0)
uniform float filterPixelate;    // 0.0=off, >0=pixel block size (default 0.0)
uniform float filterBlur;        // 0.0=off, >0=blur radius in pixels (default 0.0)

// ── Legacy Border System (ThemeBat) ──
uniform float borderSize;
uniform vec4  borderColor;
uniform vec4  borderColorStart;
uniform vec4  borderColorEnd;

uniform float borderSize2;
uniform vec4  borderColor2;
uniform vec4  borderColorStart2;
uniform vec4  borderColorEnd2;

uniform float borderSize3;
uniform vec4  borderColor3;
uniform vec4  borderColorStart3;
uniform vec4  borderColorEnd3;

uniform float cornerRadius;
uniform float innerShadowSize;
uniform vec4  innerShadowColor;
uniform float outerShadowSize;
uniform vec4  outerShadowColor;
uniform int   gradientMode;
uniform bool  bilinearFiltering;

// ── Helper Functions ──

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

// ── Image Filter Functions ──

vec4 applyPixelate(vec2 uv) {
    if (filterPixelate <= 1.0) {
        return sampleTexture(u_tex, uv);
    }
    vec2 blockSize = vec2(filterPixelate) / textureSize;
    vec2 quantizedUV = floor(uv / blockSize) * blockSize + blockSize * 0.5;
    quantizedUV = clamp(quantizedUV, vec2(0.0), vec2(1.0));
    return sampleTexture(u_tex, quantizedUV);
}

vec4 applyBlur(vec2 uv) {
    if (filterBlur <= 0.0) {
        return applyPixelate(uv);
    }
    // 9-tap Gaussian blur approximation
    vec2 texelSize = vec2(filterBlur) / textureSize;
    vec4 sum = vec4(0.0);
    // Weights for a 3x3 Gaussian kernel (sigma ~1.0)
    float kernel[9];
    kernel[0] = 0.0625; kernel[1] = 0.125; kernel[2] = 0.0625;
    kernel[3] = 0.125;  kernel[4] = 0.25;  kernel[5] = 0.125;
    kernel[6] = 0.0625; kernel[7] = 0.125; kernel[8] = 0.0625;
    int idx = 0;
    for (int y = -1; y <= 1; y++) {
        for (int x = -1; x <= 1; x++) {
            vec2 offset = vec2(float(x), float(y)) * texelSize;
            sum += sampleTexture(u_tex, clamp(uv + offset, vec2(0.0), vec2(1.0))) * kernel[idx];
            idx++;
        }
    }
    return sum;
}

vec3 applyBrightness(vec3 color) {
    if (filterBrightness == 1.0) return color;
    return color * filterBrightness;
}

vec3 applyContrast(vec3 color) {
    if (filterContrast == 1.0) return color;
    return ((color - 0.5) * filterContrast) + 0.5;
}

vec3 applySaturation(vec3 color) {
    if (filterSaturation == 1.0) return color;
    vec3 gray = vec3(dot(color, vec3(0.2126, 0.7152, 0.0722)));
    return mix(gray, color, filterSaturation);
}

vec3 applySepia(vec3 color) {
    if (filterSepia <= 0.0) return color;
    vec3 sepia;
    sepia.r = dot(color, vec3(0.393, 0.769, 0.189));
    sepia.g = dot(color, vec3(0.349, 0.686, 0.168));
    sepia.b = dot(color, vec3(0.272, 0.534, 0.131));
    return mix(color, sepia, filterSepia);
}

// ── Main ──

void main(void)
{
    // 1. Compute border values
    float b1 = getComputedValue(borderSize, 0.0);
    float b2 = getComputedValue(borderSize2, 0.0);
    float b3 = getComputedValue(borderSize3, 0.0);
    float innerShadow = getComputedValue(innerShadowSize, 0.0);
    float outerShadow = getComputedValue(outerShadowSize, 0.0);
    float cornerSize = getComputedValue(cornerRadius, 0.0);

    bool hasBorder = (b1 > 0.0 || b2 > 0.0 || b3 > 0.0 || outerShadow > 0.0 || innerShadow > 0.0 || cornerSize > 0.0);

    // 2. Determine texture coordinates (adjusted for borders if needed)
    vec2 texCoord = v_tex;
    vec2 gradientUV = v_tex;

    if (hasBorder) {
        // Transparency detection for border optimization
        if (sampleTexture(u_tex, vec2(1.0)).a < 0.3 || sampleTexture(u_tex, vec2(0.0)).a < 0.3) {
            // Transparent image corners - skip border processing, just apply filters
            hasBorder = false;
        } else {
            vec2 decal = vec2(
                (b1 / 2.0 + outerShadow) / abs(outputSize.x),
                (b1 / 2.0 + outerShadow) / abs(outputSize.y)
            );
            texCoord = vec2(
                v_tex.x / (1.0 - 2.0 * decal.x) - decal.x,
                v_tex.y * (1.0 + 2.0 * decal.y) - decal.y
            );
            gradientUV = vec2(
                (v_tex.x - decal.x) / (1.0 - 2.0 * decal.x),
                (v_tex.y - decal.y) / (1.0 - 2.0 * decal.y)
            );
        }
    }

    // 3. Sample texture (with optional pixelation and/or blur)
    vec4 sampledColor = applyBlur(texCoord);

    // 4. Bilinear filtering (legacy)
    if (bilinearFiltering && hasBorder) {
        vec2 texelSize = 1.0 / textureSize;
        vec2 f = fract(texCoord);
        vec4 texel00 = sampleTexture(u_tex, texCoord);
        vec4 texel10 = sampleTexture(u_tex, texCoord + vec2(texelSize.x, 0.0));
        vec4 texel01 = sampleTexture(u_tex, texCoord + vec2(0.0, texelSize.y));
        vec4 texel11 = sampleTexture(u_tex, texCoord + texelSize);
        sampledColor = mix(
            mix(texel00, texel10, f.x),
            mix(texel01, texel11, f.x),
            f.y
        );
    }

    // 5. Apply HyperBat image filters (color processing pipeline)
    sampledColor.rgb = applyBrightness(sampledColor.rgb);
    sampledColor.rgb = applyContrast(sampledColor.rgb);
    sampledColor.rgb = applySaturation(sampledColor.rgb);
    sampledColor.rgb = applySepia(sampledColor.rgb);

    // Clamp final color values
    sampledColor.rgb = clamp(sampledColor.rgb, 0.0, 1.0);

    // 6. Apply vertex color
    sampledColor *= v_col;

    // 7. Border / Shadow processing (legacy ThemeBat system)
    if (hasBorder) {
        vec2 middle = vec2(abs(outputSize.x), abs(outputSize.y)) / 2.0;
        vec2 center = abs(v_pos - outputOffset - middle);
        vec2 q = center - middle + cornerSize;
        float dist = length(max(q, 0.0)) + min(max(q.x, q.y), 0.0) - cornerSize;

        float totalBorder = b1 + b2 + b3 + innerShadow + outerShadow;

        if (dist > 0.0) {
            discard;
        }
        else if (dist > -totalBorder) {
            if (outerShadow > 0.0 && dist > -outerShadow) {
                sampledColor = outerShadowColor;
                sampledColor.a *= (1.0 - (outerShadow + dist) / outerShadow) * v_col.a;
            }
            else if (dist > -(b1 + outerShadow)) {
                sampledColor = (borderColorStart != borderColorEnd)
                    ? getGradientColor(borderColorStart, borderColorEnd, gradientUV)
                    : borderColor;
                sampledColor.a *= v_col.a;
            }
            else if (dist > -(b1 + b2 + outerShadow)) {
                sampledColor = (borderColorStart2 != borderColorEnd2)
                    ? getGradientColor(borderColorStart2, borderColorEnd2, gradientUV)
                    : borderColor2;
                sampledColor.a *= v_col.a;
            }
            else if (dist > -(b1 + b2 + b3 + outerShadow)) {
                sampledColor = (borderColorStart3 != borderColorEnd3)
                    ? getGradientColor(borderColorStart3, borderColorEnd3, gradientUV)
                    : borderColor3;
                sampledColor.a *= v_col.a;
            }
            else if (innerShadow > 0.0 && dist > -(b1 + b2 + b3 + outerShadow + innerShadow)) {
                float val = abs(b1 + b2 + b3 + outerShadow + dist) / innerShadow;
                val = clamp(val, 0.0, 1.0);
                sampledColor = mix(sampledColor, innerShadowColor, innerShadowColor.a * (1.0 - val));
            }
        }
        else {
            float pixelValue = 1.0 - smoothstep(-0.75, 0.5, dist);
            sampledColor.a *= pixelValue;
            sampledColor.rgb *= pixelValue;
        }
    }

    FragColor = sampledColor;
}

#endif
