#if defined(VERTEX)

#if __VERSION__ >= 130
#define COMPAT_VARYING out
#define COMPAT_ATTRIBUTE in
#else
#define COMPAT_VARYING varying
#define COMPAT_ATTRIBUTE attribute
#endif

uniform mat4 MVPMatrix;

// Paramètres
uniform float tiltX;     // rotation autour de X (deg)
uniform float tiltY;     // rotation autour de Y (deg)
uniform float persp;     // intensité perspective : 0 = off, >0 = distance caméra

COMPAT_ATTRIBUTE vec2 VertexCoord;
COMPAT_ATTRIBUTE vec2 TexCoord;
COMPAT_ATTRIBUTE vec4 COLOR;

COMPAT_VARYING vec2 v_tex;
COMPAT_VARYING vec4 v_col;

void main(void)
{
    // Position de départ (quad déjà placé par ES)
    vec3 pos = vec3(VertexCoord, 0.0);

    // Rotation Y
    float ry = radians(tiltY);
    mat3 RotY = mat3(
         cos(ry), 0.0,  sin(ry),
         0.0,     1.0,  0.0,
        -sin(ry), 0.0,  cos(ry)
    );
    pos = RotY * pos;

    // Rotation X
    float rx = radians(tiltX);
    mat3 RotX = mat3(
        1.0, 0.0,     0.0,
        0.0, cos(rx), -sin(rx),
        0.0, sin(rx),  cos(rx)
    );
    pos = RotX * pos;

    // Perspective optionnelle
    if (persp > 0.0) {
        float z = pos.z + persp;          // éloignement de la caméra
        float scale = persp / z;
        pos.xy *= scale;
    }

    gl_Position = MVPMatrix * vec4(pos.xy, 0.0, 1.0);

    v_tex = TexCoord;
    v_col = COLOR;
}

#elif defined(FRAGMENT)

#if __VERSION__ >= 130
#define COMPAT_VARYING in
out vec4 FragColor;
#else
#define COMPAT_VARYING varying
#define FragColor gl_FragColor
#endif

#ifdef GL_ES
precision mediump float;
#endif

uniform sampler2D u_tex;

COMPAT_VARYING vec2 v_tex;
COMPAT_VARYING vec4 v_col;

void main(void)
{
    vec4 texColor = texture2D(u_tex, v_tex);
    FragColor = texColor * v_col;
}

#endif
