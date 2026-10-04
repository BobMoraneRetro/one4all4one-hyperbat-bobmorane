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

void main(void)                                    
{                                                  
    gl_Position = MVPMatrix * vec4(VertexCoord.xy, 0.0, 1.0);
    v_tex       = TexCoord;                           
    v_col       = COLOR;                           
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

uniform   sampler2D u_tex;
uniform   COMPAT_PRECISION float waveTime; // Temps pour animer les vagues
uniform   COMPAT_PRECISION vec2 resolution; // Résolution de l'écran

void main(void)                                    
{         
    // Calcul des coordonnées de texture déformées
    vec2 uv = v_tex;
    uv.y += 0.02 * sin(uv.x * 10.0 + waveTime * 5.0); // Déformation ondulée

    // Appliquer la texture avec les coordonnées déformées
    FragColor = COMPAT_TEXTURE(u_tex, uv);
}
#endif
