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

// Per-corner offsets in normalized quad-space (proportion of width/height).
// TL = TexCoord (0,0), TR = (1,0), BL = (0,1), BR = (1,1).
uniform vec2 offsetTL;
uniform vec2 offsetTR;
uniform vec2 offsetBL;
uniform vec2 offsetBR;

// Position of this fragment within the warped quad-UV space, sent over to
// the fragment shader so the inverse-bilinear can recover the source UV.
// Linear interpolation of a vec2 across the rasterized quad would normally
// produce a diagonal crease (= what we're fighting), but here it's only an
// intermediate signal: the fragment shader inverts the bilinear mapping
// independently per pixel and reads the texture at the correct UV.
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

// Needed for fwidth() in GLSL ES 1.0; no-op on platforms where it's core.
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
uniform vec2 offsetTL;
uniform vec2 offsetTR;
uniform vec2 offsetBL;
uniform vec2 offsetBR;
// Optional pixelate / blur filters folded into the perspective shader because
// RetroBat doesn't chain <shader> blocks per layer. Same uniform names as the
// dedicated pixelate.glsl / blur.glsl / hyperbat_ultimate.glsl, so the same
// values can be animated end-to-end.
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
        // 9-tap Gaussian (kernel weights 0.0625 / 0.125 / 0.25 / 0.125 / 0.0625)
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

void main(void)
{
    // Inverse bilinear interpolation (Iñigo Quilez):
    // Find (u, v) ∈ [0,1]² such that
    //   v_pos = (1-u)(1-v)*cTL + u(1-v)*cTR + (1-u)v*cBL + uv*cBR
    // Each cN = the matching UV corner + its offset, so (u, v) is the source
    // texture coord that should be sampled at this fragment. This recovers a
    // perspective-correct mapping over an arbitrary 4-corner warp without
    // depending on the rasterizer's varying interpolation behavior.
    vec2 cTL = vec2(0.0, 0.0) + offsetTL;
    vec2 cTR = vec2(1.0, 0.0) + offsetTR;
    vec2 cBL = vec2(0.0, 1.0) + offsetBL;
    vec2 cBR = vec2(1.0, 1.0) + offsetBR;

    vec2 e = cTR - cTL;
    vec2 f = cBL - cTL;
    vec2 g = cTL - cTR + cBR - cBL;
    vec2 h = v_pos - cTL;

    float k2 = cross2d(g, f);
    float k1 = cross2d(e, f) + cross2d(h, g);
    float k0 = cross2d(h, e);

    vec2 uv;
    if (abs(k2) < 0.0001) {
        // Degenerate (parallelogram) — quadratic collapses to linear in v.
        // For the corresponding u we use the algebraic combination from
        // Quilez's paper that stays well-defined when k2 → 0.
        float vLin = -k0 / k1;
        float denom = e.x * k1 - g.x * k0;
        float uLin = abs(denom) > 1e-6
            ? (h.x * k1 + f.x * k0) / denom
            : (h.x - f.x * vLin) / e.x;
        uv = vec2(uLin, vLin);
    } else {
        float w = k1 * k1 - 4.0 * k0 * k2;
        if (w < 0.0) {
            // Outside the quad — drop the fragment.
            FragColor = vec4(0.0);
            return;
        }
        w = sqrt(w);
        float ik2 = 0.5 / k2;
        float v = (-k1 - w) * ik2;
        // Pick the branch that lands in [0,1]²; quadratic has two roots and
        // only one corresponds to the point being inside the quad.
        float denomU = e.x + g.x * v;
        float u = abs(denomU) > 1e-6 ? (h.x - f.x * v) / denomU : 0.0;
        if (u < 0.0 || u > 1.0 || v < 0.0 || v > 1.0) {
            v = (-k1 + w) * ik2;
            denomU = e.x + g.x * v;
            u = abs(denomU) > 1e-6 ? (h.x - f.x * v) / denomU : 0.0;
        }
        uv = vec2(u, v);
    }

    // Anti-alias the rectangular silhouette of the (warped) quad. We compute
    // a separate fade per axis (X and Y) and combine them with `min`, instead
    // of taking the min of UV distances first and feeding fwidth() that.
    // Reason: `min(uv.x, 1-uv.x)` and `min(uv.y, 1-uv.y)` each have a kink
    // at 0.5, and combining them with another `min` gives derivatives that
    // are discontinuous along the diagonals. fwidth on a discontinuous value
    // is unreliable — it reports near-zero in the wrong direction, leaving
    // the perpendicular edges (here, the horizontal ones) under-AA'd.
    // Per-axis fwidth(uv.x) / fwidth(uv.y) is smooth across the whole quad
    // and gives a clean ~1px fade on every side.
    float aaX = max(fwidth(uv.x), 0.0001);
    float aaY = max(fwidth(uv.y), 0.0001);
    float alphaX = min(smoothstep(0.0, aaX, uv.x), smoothstep(0.0, aaX, 1.0 - uv.x));
    float alphaY = min(smoothstep(0.0, aaY, uv.y), smoothstep(0.0, aaY, 1.0 - uv.y));
    float edgeAlpha = min(alphaX, alphaY);
    if (edgeAlpha <= 0.0) {
        FragColor = vec4(0.0);
        return;
    }

    vec4 col = sampleWithFilters(clamp(uv, vec2(0.0), vec2(1.0))) * v_col;
    col.a *= edgeAlpha;
    FragColor = col;
}

#endif
