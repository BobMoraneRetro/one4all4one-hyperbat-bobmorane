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

uniform mat4 MVPMatrix;
uniform vec2 textureSize;
COMPAT_ATTRIBUTE vec2 VertexCoord;
COMPAT_ATTRIBUTE vec2 TexCoord;
COMPAT_ATTRIBUTE vec4 COLOR;

// Per-corner offsets, identical semantics to perspective_corners.glsl.
uniform vec2 offsetTL;
uniform vec2 offsetTR;
uniform vec2 offsetBL;
uniform vec2 offsetBR;

COMPAT_VARYING vec2 v_pos;
COMPAT_VARYING vec4 v_col;

void main(void)
{
    vec2 t = TexCoord;
    vec2 offset =
        (1.0 - t.x) * (1.0 - t.y) * offsetTL +
        t.x         * (1.0 - t.y) * offsetTR +
        (1.0 - t.x) * t.y         * offsetBL +
        t.x         * t.y         * offsetBR;

    gl_Position = MVPMatrix * vec4(VertexCoord + offset * textureSize, 0.0, 1.0);
    v_pos = t + offset;
    v_col = COLOR;
}

#elif defined(FRAGMENT)

// fwidth() is core in GLSL 1.30+ but needs an explicit enable in GLSL ES 1.0.
// `: enable` only emits a warning if the platform doesn't ship the extension,
// so it's safe to leave unconditional — the rest of the shader still compiles.
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
precision mediump float;
#endif

uniform sampler2D u_tex;
uniform vec2 textureSize;
uniform vec2 outputSize;

uniform vec2 offsetTL;
uniform vec2 offsetTR;
uniform vec2 offsetBL;
uniform vec2 offsetBR;

// Border params (mirror of border_multi_gradient, same semantic — pixels if
// >= 1, fraction of outputSize.y if < 1, 0 means disabled).
uniform float borderSize;
uniform vec4  borderColor;
uniform float borderSize2;
uniform vec4  borderColor2;
uniform float borderSize3;
uniform vec4  borderColor3;
uniform float cornerRadius;

// Optional pixelate / blur filters, same semantic as in
// perspective_corners.glsl. RetroBat doesn't chain <shader> blocks so any
// pixelate / blur the layer needs has to be folded in here.
uniform float pixelSize;   // 0 or 1 = off; > 1 snaps UVs to pixelSize-px blocks
uniform float filterBlur;  // 0 = off; > 0 = 3x3 Gaussian radius in pixels

COMPAT_VARYING vec2 v_pos;
COMPAT_VARYING vec4 v_col;

float cross2d(vec2 a, vec2 b) {
    return a.x * b.y - a.y * b.x;
}

/** Sample u_tex at `uv` with optional pixelate + 3x3 Gaussian blur applied. */
vec4 sampleWithFilters(vec2 uv) {
    vec2 sUv = uv;
    if (pixelSize > 1.0 && textureSize.x > 0.0 && textureSize.y > 0.0) {
        vec2 px = vec2(pixelSize) / textureSize;
        sUv = (floor(sUv / px) + 0.5) * px;
    }
    if (filterBlur > 0.0 && textureSize.x > 0.0 && textureSize.y > 0.0) {
        vec2 stepBlur = vec2(filterBlur) / textureSize;
        vec4 sum = vec4(0.0);
        sum += COMPAT_TEXTURE(u_tex, clamp(sUv + vec2(-stepBlur.x, -stepBlur.y), vec2(0.0), vec2(1.0))) * 0.0625;
        sum += COMPAT_TEXTURE(u_tex, clamp(sUv + vec2(0.0,         -stepBlur.y), vec2(0.0), vec2(1.0))) * 0.125;
        sum += COMPAT_TEXTURE(u_tex, clamp(sUv + vec2( stepBlur.x, -stepBlur.y), vec2(0.0), vec2(1.0))) * 0.0625;
        sum += COMPAT_TEXTURE(u_tex, clamp(sUv + vec2(-stepBlur.x,  0.0       ), vec2(0.0), vec2(1.0))) * 0.125;
        sum += COMPAT_TEXTURE(u_tex, clamp(sUv,                                  vec2(0.0), vec2(1.0))) * 0.25;
        sum += COMPAT_TEXTURE(u_tex, clamp(sUv + vec2( stepBlur.x,  0.0       ), vec2(0.0), vec2(1.0))) * 0.125;
        sum += COMPAT_TEXTURE(u_tex, clamp(sUv + vec2(-stepBlur.x,  stepBlur.y), vec2(0.0), vec2(1.0))) * 0.0625;
        sum += COMPAT_TEXTURE(u_tex, clamp(sUv + vec2(0.0,          stepBlur.y), vec2(0.0), vec2(1.0))) * 0.125;
        sum += COMPAT_TEXTURE(u_tex, clamp(sUv + vec2( stepBlur.x,  stepBlur.y), vec2(0.0), vec2(1.0))) * 0.0625;
        return sum;
    }
    return COMPAT_TEXTURE(u_tex, sUv);
}

vec2 inverseBilinear(vec2 p, vec2 a, vec2 b, vec2 c, vec2 d) {
    // Solve for (u, v) ∈ [0,1]² such that
    //   p = (1-u)(1-v)*a + u(1-v)*b + uv*c + (1-u)v*d
    // Iñigo Quilez method — quadratic in v, then back-substitute u.
    vec2 e = b - a;
    vec2 f = d - a;
    vec2 g = a - b + c - d;
    vec2 h = p - a;

    float k2 = cross2d(g, f);
    float k1 = cross2d(e, f) + cross2d(h, g);
    float k0 = cross2d(h, e);

    if (abs(k2) < 0.0001) {
        float vLin = -k0 / k1;
        float denom = e.x * k1 - g.x * k0;
        float uLin = abs(denom) > 1e-6
            ? (h.x * k1 + f.x * k0) / denom
            : (h.x - f.x * vLin) / e.x;
        return vec2(uLin, vLin);
    }
    float w = k1 * k1 - 4.0 * k0 * k2;
    if (w < 0.0) return vec2(-1.0);
    w = sqrt(w);
    float ik2 = 0.5 / k2;
    float v = (-k1 - w) * ik2;
    float denomU = e.x + g.x * v;
    float u = abs(denomU) > 1e-6 ? (h.x - f.x * v) / denomU : 0.0;
    if (u < 0.0 || u > 1.0 || v < 0.0 || v > 1.0) {
        v = (-k1 + w) * ik2;
        denomU = e.x + g.x * v;
        u = abs(denomU) > 1e-6 ? (h.x - f.x * v) / denomU : 0.0;
    }
    return vec2(u, v);
}

float getComputedValue(float value, float defaultValue) {
    if (value == 0.0) return defaultValue;
    if (value < 1.0) return abs(outputSize.y) * value;
    return value;
}

void main(void)
{
    // ── Step 1 : recover the rectangular UV ──
    vec2 cTL = vec2(0.0, 0.0) + offsetTL;
    vec2 cTR = vec2(1.0, 0.0) + offsetTR;
    vec2 cBL = vec2(0.0, 1.0) + offsetBL;
    vec2 cBR = vec2(1.0, 1.0) + offsetBR;

    vec2 uv = inverseBilinear(v_pos, cTL, cTR, cBR, cBL);
    if (uv.x < 0.0 || uv.x > 1.0 || uv.y < 0.0 || uv.y > 1.0) {
        FragColor = vec4(0.0);
        return;
    }

    vec4 sampledColor = sampleWithFilters(uv) * v_col;

    // ── Step 2 : evaluate border + corner radius in the rectangular UV space ──
    // We do this AFTER the inverse-bilinear so the rounded rectangle outline
    // follows the warped quad (border tracks the perspective, instead of
    // being a separate axis-aligned frame).
    float b1 = getComputedValue(borderSize, 0.0);
    float b2 = getComputedValue(borderSize2, 0.0);
    float b3 = getComputedValue(borderSize3, 0.0);
    float cornerSize = getComputedValue(cornerRadius, 0.0);
    float totalBorder = b1 + b2 + b3;

    if (totalBorder > 0.0 || cornerSize > 0.0) {
        // Rounded-rectangle SDF in pixel space, using the layer's rendered
        // size as the box. `outputSize` is what RetroBat passes for the
        // current node's pixel dimensions; we fall back to `textureSize`
        // when running on a build that doesn't fill outputSize for inline
        // shaders (defensive — both should be equal for image/video layers
        // that don't size-mismatch their source).
        vec2 box = abs(outputSize.x) > 0.0 ? abs(outputSize) : textureSize;
        vec2 half = box * 0.5;
        vec2 centerOffset = abs(uv - vec2(0.5)) * box;
        vec2 q = centerOffset - half + vec2(cornerSize);
        float dist = length(max(q, vec2(0.0))) + min(max(q.x, q.y), 0.0) - cornerSize;

        // Pixel-size in distance units, used to soften the rounded edge by
        // ~1 pixel. Without this, the cutoff at dist == 0 produces visible
        // staircase artifacts on the curved corners.
        float aa = max(fwidth(dist), 0.0001);

        if (dist > aa) {
            // Far outside — drop early; the AA fade only matters within ±aa.
            FragColor = vec4(0.0);
            return;
        }

        // Border rings (hard transitions inside the box are fine — they're
        // far from the visible silhouette where aliasing shows up).
        if (b1 > 0.0 && dist > -b1) {
            sampledColor = borderColor;
            sampledColor.a *= v_col.a;
        } else if (b2 > 0.0 && dist > -(b1 + b2)) {
            sampledColor = borderColor2;
            sampledColor.a *= v_col.a;
        } else if (b3 > 0.0 && dist > -(b1 + b2 + b3)) {
            sampledColor = borderColor3;
            sampledColor.a *= v_col.a;
        }

        // Smooth alpha across the SDF zero crossing — replaces the hard
        // `if (dist > 0) discard` with a fade over one pixel.
        sampledColor.a *= 1.0 - smoothstep(-aa, aa, dist);
    }

    FragColor = sampledColor;
}

#endif
