#if defined(VERTEX)

#if __VERSION__ >= 130
#define COMPAT_VARYING out
#define COMPAT_ATTRIBUTE in
#else
#define COMPAT_VARYING varying
#define COMPAT_ATTRIBUTE attribute
#endif

uniform mat4 MVPMatrix;
COMPAT_ATTRIBUTE vec2 VertexCoord;
COMPAT_ATTRIBUTE vec2 TexCoord;
COMPAT_ATTRIBUTE vec4 COLOR;

COMPAT_VARYING vec2 v_tex;
COMPAT_VARYING vec4 v_col;

void main(void) {
    gl_Position = MVPMatrix * vec4(VertexCoord.xy, 0.0, 1.0);
    v_tex = TexCoord;
    v_col = COLOR;
}

#elif defined(FRAGMENT)

#if __VERSION__ >= 130
#define COMPAT_VARYING in
#define COMPAT_TEXTURE texture
out vec4 FragColor;
#else
#define COMPAT_VARYING varying
#define COMPAT_TEXTURE texture2D
#define FragColor gl_FragColor
#endif

#ifdef GL_ES
precision mediump float;
#endif

uniform sampler2D u_tex;
uniform float u_angle;
uniform float u_thickness;
uniform float u_mode;
uniform float u_pitch;

COMPAT_VARYING vec2 v_tex;
COMPAT_VARYING vec4 v_col;

// =====================
// ANTIALIAS
// =====================
float antialias(float edge, float value) {
    float fw = fwidth(value);
    return smoothstep(edge + fw, edge - fw, value);
}

void main(void) {

    // =====================
    // UV NORMALISÉ
    // =====================
    float internalScale = 0.6;
    vec2 uv = (v_tex - 0.5) / internalScale;

    float cosA = cos(u_angle);
    float sinA = sin(u_angle);
    float halfThick = u_thickness * 0.5;

    float localX = 0.0;
    float depthZ = 0.0;
    float texX = 0.5;
    float alphaX = 0.0;
    bool isFaceArea = false;

    // =====================
    // GÉOMÉTRIE HORIZONTALE
    // =====================
    if (u_mode < 0.5) { // FRONT
        if (cosA > 0.0) {
            localX = (uv.x - halfThick * sinA) / cosA;
            alphaX = antialias(0.5, abs(localX));
            depthZ = -localX * sinA + halfThick * cosA;
            texX = localX + 0.5;
            isFaceArea = true;
        }
    }
    else if (u_mode > 1.5) { // SPINE
        float side = (sinA >= 0.0) ? 0.5 : -0.5;
        if (abs(sinA) > 0.001) {
            float localZ = (uv.x + side * cosA) / sinA;
            alphaX = antialias(halfThick, abs(localZ));
            depthZ = side * sinA + localZ * cosA;
            texX = (localZ / u_thickness) + 0.5;
            localX = side;
            isFaceArea = true;
        }
    }
    else { // BACK
        float cosAB = cos(u_angle + 3.14159265);
        float sinAB = sin(u_angle + 3.14159265);
        if (cosAB > 0.0) {
            localX = (uv.x - halfThick * sinAB) / cosAB;
            alphaX = antialias(0.5, abs(localX));
            depthZ = -localX * sinAB + halfThick * cosAB;
            texX = localX + 0.5;
            isFaceArea = true;
        }
    }

    if (!isFaceArea || alphaX <= 0.0) discard;

    // =====================
    // GÉOMÉTRIE VERTICALE
    // =====================
    float yOffset = depthZ * u_pitch;
    float faceTop = 0.5 + yOffset;
    float faceBottom = -0.5 + yOffset;
    float AAy = fwidth(uv.y);

    vec4 color = vec4(0.0);

    bool insideFace = (uv.y >= faceBottom && uv.y <= faceTop);

    // =====================
    // FACE
    // =====================
    if (insideFace) {

        float texY = (uv.y - yOffset) + 0.5;

        if (u_mode > 1.5)
            texX = 0.01 + texX * 0.04;

        vec4 texColor = COMPAT_TEXTURE(
            u_tex,
            vec2(texX, clamp(texY, 0.0, 1.0))
        );

        float alphaY =
            smoothstep(faceBottom - AAy, faceBottom + AAy, uv.y) *
            smoothstep(faceTop + AAy, faceTop - AAy, uv.y);

        float light = (u_mode > 1.5) ? abs(sinA) * 0.7 : abs(cosA);

        color = vec4(
            texColor.rgb * clamp(light, 0.4, 1.0),
            texColor.a * alphaX * alphaY
        );
    }

    // =====================
    // CAP — VERSION CORRIGÉE
    // =====================
    bool showTop  = (u_pitch < -0.001 && uv.y > faceTop);
    bool showDown = (u_pitch >  0.001 && uv.y < faceBottom);

    if (showTop || showDown) {

        float capY = showTop ? faceTop : faceBottom;

        // profondeur locale du cap (même que tranche)
        float localZ = (uv.y - capY) / (abs(u_pitch) + 1e-5);

        float capAlphaX = antialias(0.5, abs(localX));
        float capAlphaZ = antialias(halfThick, abs(localZ));

        float capAlpha = min(capAlphaX, capAlphaZ) * alphaX;

        if (capAlpha > 0.0) {
            // 🔴 ROUGE DEBUG
            vec3 capColor = vec3(1.0, 0.0, 0.0);
            color = vec4(capColor, capAlpha);
        }
    }

    if (color.a <= 0.0) discard;

    FragColor = color * v_col;
}
#endif
