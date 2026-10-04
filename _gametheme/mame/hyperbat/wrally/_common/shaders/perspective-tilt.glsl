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
COMPAT_ATTRIBUTE vec2 VertexCoord;
COMPAT_ATTRIBUTE vec2 TexCoord;
COMPAT_ATTRIBUTE vec4 COLOR;

COMPAT_VARYING vec2 v_tex;
COMPAT_VARYING vec4 v_col;
COMPAT_VARYING vec2 v_pos;

void main(void)
{
    gl_Position = MVPMatrix * vec4(VertexCoord.xy, 0.0, 1.0);
    v_tex = TexCoord;
    v_col = COLOR;
    v_pos = VertexCoord;
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
precision mediump float;
#endif

uniform sampler2D u_tex;
uniform float tiltAngle;
uniform float tiltAngleX;
uniform float perspectiveDepth;
uniform float borderSize;
uniform vec4  borderColorStart;
uniform vec4  borderColorEnd;
uniform vec2 textureSize;

uniform int gradientMode;   // 0=vertical,1=horizontal,2=diag1,3=diag2,4=radial
uniform float gradientMix;  // point exact du changement (0.0 à 1.0)
uniform float gradientTransition; // largeur de transition douce autour du point, default 0.02

COMPAT_VARYING vec2 v_tex;
COMPAT_VARYING vec4 v_col;
COMPAT_VARYING vec2 v_pos;

void main(void)
{
    float angleY = radians(tiltAngle);
    float angleX = radians(tiltAngleX);

    float perspectiveY = 0.5 * tan(angleY);
    float perspectiveX = 0.5 * tan(angleX);

    vec2 centered = v_tex - vec2(0.5);
    float x = centered.x / (perspectiveDepth + centered.y * perspectiveY);
    float y = centered.y / (perspectiveDepth + centered.x * perspectiveX);
    vec2 distorted = vec2(x, y) + vec2(0.5);

    float borderTexSize = borderSize / textureSize.y;

    float distLeft = distorted.x;
    float distRight = 1.0 - distorted.x;
    float distTop = distorted.y;
    float distBottom = 1.0 - distorted.y;
    float distBorder = min(min(distLeft, distRight), min(distTop, distBottom));

    float aa = fwidth(distBorder) * 2.5;
    float alphaInner = 1.0 - smoothstep(borderTexSize - aa, borderTexSize + aa, distBorder);

    float outsideDist = 0.0;
    float outsideAlpha = 0.0;
    bool outside = false;

    if (distorted.x < 0.0) { outsideDist = -distorted.x; outside = true; }
    else if (distorted.x > 1.0) { outsideDist = distorted.x - 1.0; outside = true; }
    if (distorted.y < 0.0) { float dist = -distorted.y; if (dist > outsideDist) outsideDist = dist; outside = true; }
    else if (distorted.y > 1.0) { float dist = distorted.y - 1.0; if (dist > outsideDist) outsideDist = dist; outside = true; }

    if (outside) {
        float outsideAA = 2.0 / textureSize.y;
        outsideAlpha = 1.0 - smoothstep(0.0, outsideAA, outsideDist);
    }

    float alphaBorder = max(alphaInner, outsideAlpha);

    // Calcul du gradient selon le mode
    float t = 0.0;

    if (gradientMode == 1) {
        t = v_tex.x;
    } else if (gradientMode == 2) {
        t = (v_tex.x + v_tex.y) * 0.5;
    } else if (gradientMode == 3) {
        t = (v_tex.x + (1.0 - v_tex.y)) * 0.5;
    } else if (gradientMode == 4) {
        vec2 center = vec2(0.5, 0.5);
        float dist = distance(v_tex, center);
        t = smoothstep(0.0, 0.5, dist);
    } else {
        t = v_tex.y;
    }

    // Gradient mix avec transition douce
    float gm = clamp(gradientMix, 0.0, 1.0);
    float tr = max(gradientTransition, 0.001); // valeur minimale pour éviter 0
    float alphaGrad = clamp((t - (gm - tr*0.5)) / tr, 0.0, 1.0);

    vec4 borderCol = mix(borderColorStart, borderColorEnd, alphaGrad);

    // Sortie finale
    if (!outside)
    {
        if (distorted.x < 0.0 || distorted.x > 1.0 || distorted.y < 0.0 || distorted.y > 1.0)
        {
            FragColor = vec4(0.0);
            return;
        }

        vec4 texColor = COMPAT_TEXTURE(u_tex, distorted) * v_col;
        FragColor = mix(texColor, borderCol, alphaInner);
    }
    else
    {
        FragColor = vec4(borderCol.rgb, borderCol.a * outsideAlpha);
        if (outsideAlpha < 0.01)
            FragColor = vec4(0.0);
    }
}

#endif
