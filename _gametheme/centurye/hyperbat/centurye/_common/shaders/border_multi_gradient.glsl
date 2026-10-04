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

// fwidth() : core en OpenGL desktop et en ESSL3 (WebGL2). La directive n'est
// requise qu'en GLSL ES 1.0 — et ESSL3/ANGLE la REJETTE quand elle suit des
// tokens non-préprocesseur (le wrapper du preview injecte `precision` avant le
// source), d'où le garde-fou : sans lui le shader ne compile pas dans l'aperçu.
#if defined(GL_ES) && (__VERSION__ < 300)
#extension GL_OES_standard_derivatives : enable
#endif

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
uniform float edgeSoftness;
uniform float borderPad;
uniform float borderOffset;
uniform int   borderLayout;
uniform float borderPos1;
uniform float borderPos2;
uniform float borderPos3;

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

// Standard source-over on straight alpha (free layout: rings may overlap).
vec4 srcOver(vec4 dst, vec4 src) {
    float a = src.a + dst.a * (1.0 - src.a);
    if (a <= 0.0) return vec4(0.0);
    return vec4((src.rgb * src.a + dst.rgb * dst.a * (1.0 - src.a)) / a, a);
}

vec4 evalOuterShadow(float d, float os) {
    vec4 c = outerShadowColor * v_col;
    if (os > 0.0) {
        // t = 0 at the silhouette, 1 against the border. Smoothstep falloff —
        // a linear ramp shows Mach bands (hard start/stop) at both ends.
        float t = clamp(-d / os, 0.0, 1.0);
        c.a *= t * t * (3.0 - 2.0 * t);
    }
    return c;
}

vec4 evalInnerShadow(vec4 content, float d, float tContent, float is) {
    float val = clamp(abs(d - tContent) / is, 0.0, 1.0);
    // Smoothstep strength instead of linear (1-val): avoids the visible banding
    // at the shadow's start/end.
    float t = 1.0 - val;
    float s = t * t * (3.0 - 2.0 * t);
    // Source-over: the shadow darkens the content WITHOUT eroding its alpha.
    // Mixing the whole vec4 made a black semi-opaque shadow punch a translucent
    // hole in the content (grey over the editor's light backdrop instead of a
    // dark shadow). At opacity 1.0 this is identical to the previous mix.
    vec4 sh = innerShadowColor * v_col;
    return srcOver(content, vec4(sh.rgb, sh.a * s));
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
    // Allow up to a stadium/half-circle: the SDF misbehaves past half the box.
    cornerSize = min(cornerSize, 0.5 * min(abs(outputSize.x), abs(outputSize.y)));

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
    float stackTotal = borderSum + outerShadow;
    // Frame position (P1b). borderOffset slides the frame relative to the content
    // edge: 0 = fully outside (touching), <0 = penetrates inward, >0 = floating gap.
    // borderPad = pixels the app added around the layer rect so the outside part of
    // the frame has room; the frame's outer edge always lands on the quad silhouette,
    // so the ring thresholds below are unchanged. Legacy themes emit neither uniform
    // (0/0) → old fully-inset look.
    float off = borderOffset;
    if (borderPad == 0.0 && off == 0.0)
        off = -stackTotal;
    off = max(off, -stackTotal);
    float penetration = max(0.0, -off);
    // Free layout never shrinks the content: rings overlay it, pad gives outside room.
    float shrink = (borderLayout == 1) ? borderPad : borderPad + penetration;

    vec2 decal = vec2(
        shrink / abs(outputSize.x),
        shrink / abs(outputSize.y)
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
    // edgeSoftness == 0 (uniform absent on old themes) falls back to the P0 default.
    float aa = max(fwidth(distValue), edgeSoftness > 0.0 ? edgeSoftness : 1.0);

    if (borderLayout == 1) {
        // ── FREE layout: rings centered at borderPos_i from the frame line,
        //    composited b1 under b2 under b3; shadows anchor to the ring extents. ──
        float tContent = -shrink;
        float base = tContent + borderOffset;   // frame line (content edge + global offset)
        float c1 = base + borderPos1;
        float c2 = base + borderPos2;
        float c3 = base + borderPos3;
        float cov1 = (b1 > 0.0) ? ringWeight(distValue, c1 + b1 * 0.5, c1 - b1 * 0.5, aa) : 0.0;
        float cov2 = (b2 > 0.0) ? ringWeight(distValue, c2 + b2 * 0.5, c2 - b2 * 0.5, aa) : 0.0;
        float cov3 = (b3 > 0.0) ? ringWeight(distValue, c3 + b3 * 0.5, c3 - b3 * 0.5, aa) : 0.0;

        float wC = ringWeight(distValue, tContent, tContent - 1e6, aa);
        vec4 col = vec4(sampledColor.rgb, sampledColor.a * wC);

        // Inner shadow: hugs the innermost ring edge (or the frame line), falls
        // inward UNDER the borders — over the gap it is a translucent ring, over
        // the content it darkens it.
        float innerEdge = base;
        if (b1 > 0.0) innerEdge = min(innerEdge, c1 - b1 * 0.5);
        if (b2 > 0.0) innerEdge = min(innerEdge, c2 - b2 * 0.5);
        if (b3 > 0.0) innerEdge = min(innerEdge, c3 - b3 * 0.5);
        if (innerShadow > 0.0) {
            float t = clamp((innerEdge - distValue) / innerShadow, 0.0, 1.0);
            float st = 1.0 - t;
            st = st * st * (3.0 - 2.0 * st);
            float below = 1.0 - smoothstep(innerEdge - aa, innerEdge + aa, distValue);
            vec4 shc = innerShadowColor * v_col;
            col = srcOver(col, vec4(shc.rgb, shc.a * st * below));
        }

        if (cov1 > 0.0) { vec4 bc = evalBorder1(gradientUV); col = srcOver(col, vec4(bc.rgb, bc.a * cov1)); }
        if (cov2 > 0.0) { vec4 bc = evalBorder2(gradientUV); col = srcOver(col, vec4(bc.rgb, bc.a * cov2)); }
        if (cov3 > 0.0) { vec4 bc = evalBorder3(gradientUV); col = srcOver(col, vec4(bc.rgb, bc.a * cov3)); }

        // Outer shadow: beyond the outermost ring edge, falling outward.
        if (outerShadow > 0.0) {
            float outerEdge = base;
            if (b1 > 0.0) outerEdge = max(outerEdge, c1 + b1 * 0.5);
            if (b2 > 0.0) outerEdge = max(outerEdge, c2 + b2 * 0.5);
            if (b3 > 0.0) outerEdge = max(outerEdge, c3 + b3 * 0.5);
            float t = clamp((distValue - outerEdge) / outerShadow, 0.0, 1.0);
            float st = 1.0 - t;
            st = st * st * (3.0 - 2.0 * st);
            float above = smoothstep(outerEdge - aa, outerEdge + aa, distValue);
            vec4 shc = outerShadowColor * v_col;
            col = srcOver(col, vec4(shc.rgb, shc.a * st * above));
        }
        FragColor = col;
        return;
    }

    float tSilhouette = 0.0;
    float tOS  = -outerShadow;
    float tB1  = -(b1 + outerShadow);
    float tB2  = -(b1 + b2 + outerShadow);
    float tB3  = -(b1 + b2 + b3 + outerShadow);
    float tContent = -shrink;
    float contentOuter = tContent;
    // Inner shadow anchors to the border stack bottom (tB3). If the frame floats
    // (gap: tB3 > tContent) the part above the content is a standalone ring.
    float isGapInner = max(tB3 - innerShadow, tContent);

    float wOS = (outerShadow > 0.0)
        ? ringWeight(distValue, tSilhouette, tOS, aa) : 0.0;
    float outerB1 = (outerShadow > 0.0) ? tOS : tSilhouette;
    float wB1 = (b1 > 0.0)
        ? ringWeight(distValue, outerB1, tB1, aa) : 0.0;
    float wB2 = (b2 > 0.0)
        ? ringWeight(distValue, tB1, tB2, aa) : 0.0;
    float wB3 = (b3 > 0.0)
        ? ringWeight(distValue, tB2, tB3, aa) : 0.0;
    float wISgap = (innerShadow > 0.0 && tB3 > tContent + 0.5)
        ? ringWeight(distValue, tB3, isGapInner, aa) : 0.0;
    float wContent = ringWeight(distValue, contentOuter, contentOuter - 1e6, aa);

    float totalW = wOS + wB1 + wB2 + wB3 + wISgap + wContent;
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
    if (wISgap > 0.0) {
        float t = clamp((tB3 - distValue) / innerShadow, 0.0, 1.0);
        float st = 1.0 - t;
        st = st * st * (3.0 - 2.0 * st);
        vec4 shc = innerShadowColor * v_col;
        result += vec4(shc.rgb, shc.a * st) * wISgap;
    }
    result += ((innerShadow > 0.0)
        ? evalInnerShadow(sampledColor, distValue, tB3, innerShadow)
        : sampledColor) * wContent;

    FragColor = result;
}
#endif
