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
uniform float tiltAngle;          // axe Y (vue de dessus)
uniform float tiltAngleX;         // axe X (vue de côté)
uniform float perspectiveDepth;   // profondeur base, ex: 0.7
uniform float borderSize;          // taille bordure (en pixels)
uniform vec4  borderColorStart;   // couleur bordure début dégradé
uniform vec4  borderColorEnd;     // couleur bordure fin dégradé
uniform vec2 textureSize;         // résolution texture (ex: 1920x1080)

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

    // Calcul distance aux bords (intérieur)
    float distLeft = distorted.x;
    float distRight = 1.0 - distorted.x;
    float distTop = distorted.y;
    float distBottom = 1.0 - distorted.y;
    float distBorder = min(min(distLeft, distRight), min(distTop, distBottom));

    // Antialiasing bordure intérieur (douce transition vidéo->bordure)
    float aa = fwidth(distBorder) * 2.5;
    float alphaInner = 1.0 - smoothstep(borderTexSize - aa, borderTexSize + aa, distBorder);

    // Gestion bordure extérieure (douce transition bordure->fond)
    float outsideDist = 0.0;
    float outsideAlpha = 0.0;
    bool outside = false;
    if(distorted.x < 0.0) {
        outsideDist = -distorted.x;
        outside = true;
    } else if(distorted.x > 1.0) {
        outsideDist = distorted.x - 1.0;
        outside = true;
    }
    if(distorted.y < 0.0) {
        float dist = -distorted.y;
        if(dist > outsideDist) outsideDist = dist;
        outside = true;
    } else if(distorted.y > 1.0) {
        float dist = distorted.y - 1.0;
        if(dist > outsideDist) outsideDist = dist;
        outside = true;
    }

    if(outside) {
        float outsideAA = 2.0 / textureSize.y; // environ 2 pixels
        outsideAlpha = 1.0 - smoothstep(0.0, outsideAA, outsideDist);
    }

    float alphaBorder = max(alphaInner, outsideAlpha);

    vec4 borderCol = mix(borderColorStart, borderColorEnd, clamp(distorted.x, 0.0, 1.0));

    // Afficher vidéo si à l’intérieur, sinon bordure avec fondu extérieur, sinon transparent
    if(!outside) {
        // Si coordonnée hors texture, on sort transparent (sécurité)
        if(distorted.x < 0.0 || distorted.x > 1.0 || distorted.y < 0.0 || distorted.y > 1.0) {
            FragColor = vec4(0.0);
            return;
        }
        vec4 texColor = COMPAT_TEXTURE(u_tex, distorted) * v_col;
        FragColor = mix(texColor, borderCol, alphaInner);
    } else {
        // Bordure extérieure avec fondu progressif vers transparent
        FragColor = vec4(borderCol.rgb, borderCol.a * outsideAlpha);
        if(outsideAlpha < 0.01) FragColor = vec4(0.0);
    }
}

#endif
