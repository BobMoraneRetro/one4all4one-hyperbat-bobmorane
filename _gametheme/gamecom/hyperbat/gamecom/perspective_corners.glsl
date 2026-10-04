#if defined(VERTEX)

uniform mat4 MVPMatrix;

attribute vec2 VertexCoord;
attribute vec2 TexCoord;
attribute vec4 COLOR;

varying vec2 v_tex;
varying vec4 v_col;

// Offsets pour chaque coin (en proportion de la largeur/hauteur)
uniform vec2 offsetTL;
uniform vec2 offsetTR;
uniform vec2 offsetBL;
uniform vec2 offsetBR;

void main(void)
{
    // Déterminer quel coin on manipule selon VertexCoord
    vec2 offset = vec2(0.0, 0.0);

    if(VertexCoord.x <= 0.0 && VertexCoord.y <= 0.0)      offset = offsetTL; // haut-gauche
    else if(VertexCoord.x >= 1.0 && VertexCoord.y <= 0.0) offset = offsetTR; // haut-droit
    else if(VertexCoord.x <= 0.0 && VertexCoord.y >= 1.0) offset = offsetBL; // bas-gauche
    else if(VertexCoord.x >= 1.0 && VertexCoord.y >= 1.0) offset = offsetBR; // bas-droit

    vec3 pos = vec3(VertexCoord + offset, 0.0);

    gl_Position = MVPMatrix * vec4(pos.xy, 0.0, 1.0);
    v_tex = TexCoord;
    v_col = COLOR;
}

#elif defined(FRAGMENT)

#ifdef GL_ES
precision mediump float;
#endif

uniform sampler2D u_tex;
varying vec2 v_tex;
varying vec4 v_col;

void main(void)
{
    vec4 texColor = texture2D(u_tex, v_tex);
    gl_FragColor = texColor * v_col;
}

#endif
