#ifdef GL_ES
precision mediump float;
#endif

uniform sampler2D texture;
varying vec2 vTexCoord;

void main()
{
    vec2 uv = vTexCoord;
    vec2 center = vec2(0.5, 0.5);

    vec2 p = uv - center;

    float radius = 0.48;
    float hole = 0.08;
    float reflectStrength = 0.25;

    float dist = length(p);

    // Hors disque
    if (dist > radius)
    {
        discard;
    }

    // Trou central
    if (dist < hole)
    {
        discard;
    }

    vec4 color = texture2D(texture, uv);

    // Reflet plastique
    float angle = atan(p.y, p.x);
    float highlight = cos(angle - 0.8) * 0.5 + 0.5;
    float radialFade = smoothstep(hole, radius, dist);

    float ring = smoothstep(radius * 0.72, radius * 0.74, dist)
               - smoothstep(radius * 0.74, radius * 0.76, dist);

    float reflection = (highlight * 0.6 + ring * 2.0) * radialFade;

    color.rgb += reflection * reflectStrength;

    gl_FragColor = color;
}
