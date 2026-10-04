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

COMPAT_VARYING vec2 v_tex;
COMPAT_VARYING vec4 v_col;
COMPAT_VARYING vec2 v_pos;

void main(void)
{
    float angleY = radians(tiltAngle);   // Inclinaison verticale
    float angleX = radians(tiltAngleX);  // Inclinaison horizontale

    float perspectiveY = 0.5 * tan(angleY);
    float perspectiveX = 0.5 * tan(angleX);

    // Centrer la texture autour de (0,0)
    vec2 centered = v_tex - vec2(0.5);

    // Appliquer perspective sur X et Y séparément
    float x = centered.x / (perspectiveDepth + centered.y * perspectiveY);
    float y = centered.y / (perspectiveDepth + centered.x * perspectiveX);

    vec2 distorted = vec2(x, y) + vec2(0.5);

    // Clamp hors zone
    if (distorted.x < 0.0 || distorted.x > 1.0 || distorted.y < 0.0 || distorted.y > 1.0) {
        FragColor = vec4(0.0);
        return;
    }

    vec4 texColor = COMPAT_TEXTURE(u_tex, distorted);
    FragColor = texColor * v_col;
}

#endif
