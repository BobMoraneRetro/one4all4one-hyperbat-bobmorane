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
COMPAT_VARYING   vec2 v_pos;

void main(void)                                     
{                                                   
    gl_Position = MVPMatrix * vec4(VertexCoord.xy, 0.0, 1.0);
    v_tex       = TexCoord;                           
    v_col       = COLOR;                           
    v_pos       = VertexCoord;
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
COMPAT_VARYING   vec2      v_pos;

uniform   sampler2D u_tex;
uniform   vec2      resolution;
uniform   vec2      textureSize;
uniform   vec2      outputSize;
uniform   vec2      outputOffset;

uniform   float      borderSize;
uniform   vec4       borderColor;
uniform   float      cornerRadius;
uniform   float      innerShadowSize;
uniform   vec4       innerShadowColor;

uniform   float      outerShadowSize;
uniform   vec4       outerShadowColor;

uniform   float       saturation;

uniform bool        bilinearFiltering;

vec4 sampleTexture(sampler2D tex, vec2 texCoord) 
{
    return COMPAT_TEXTURE(tex, texCoord);
}

float getComputedValue(float value, float defaultValue) {
    if (value == 0.0)
        return defaultValue;
    if (value < 1.0)
        return abs(outputSize.y) * value;
    return value;
}

void main(void)                                     
{
    float outerBorder = getComputedValue(borderSize, 0.0);
    float innerShadow = getComputedValue(innerShadowSize, 0.0);
    float outerShadow = getComputedValue(outerShadowSize, 0.0);
    float cornerSize = getComputedValue(cornerRadius, 0.0);

    // --- CORRECTION 1: SORTIE PRÉMATURÉE ---
    // Si l'image est transparente sur les bords, on applique quand même v_col avant de quitter
    vec2 bottomRight = vec2(1.0, 1.0);
    if (sampleTexture(u_tex, bottomRight).a < 0.3) {
        FragColor = sampleTexture(u_tex, v_tex) * v_col;
        return;
    }
    
    vec2 topLeft = vec2(0.0, 0.0);
    if (sampleTexture(u_tex, topLeft).a < 0.3) {
        FragColor = sampleTexture(u_tex, v_tex) * v_col;
        return;
    }
        
    // Padding pour la bordure
    vec2 decal = vec2((outerBorder/2.0+outerShadow) / abs(outputSize.x), (outerBorder/2.0+outerShadow) / abs(outputSize.y));    
    vec2 v_padtex = vec2(v_tex.x / (1.0 - 2.0 * decal.x) - decal.x, v_tex.y * (1.0 + 2.0 * decal.y) - decal.y);

    // Lecture texture
    vec4 sampledColor = sampleTexture(u_tex, v_padtex);

    // Filtrage bilinéaire
    if (bilinearFiltering)
    {
        vec2 texelSize = 1.0 / textureSize;
        vec2 uv = v_padtex;
        vec2 f = fract(uv);

        vec4 texel00 = sampleTexture(u_tex, uv);
        vec4 texel10 = sampleTexture(u_tex, uv + vec2(texelSize.x, 0.0));
        vec4 texel01 = sampleTexture(u_tex, uv + vec2(0.0, texelSize.y));
        vec4 texel11 = sampleTexture(u_tex, uv + texelSize);

        sampledColor = mix(
            mix(texel00, texel10, f.x),
            mix(texel01, texel11, f.x),
            f.y
        );
    }

    if (saturation != 1.0) {
        vec3 gray = vec3(dot(sampledColor.rgb, vec3(0.34, 0.55, 0.11)));
        vec3 blend = mix(gray, sampledColor.rgb, saturation);
        sampledColor = vec4(blend, sampledColor.a);
    }
                
    // On applique l'opacité/couleur de base à l'image
    sampledColor *= v_col;
                     
    vec2 middle = vec2(abs(outputSize.x), abs(outputSize.y)) / 2.0;
    vec2 center = abs(v_pos - outputOffset - middle);
    vec2 q = center - middle + cornerSize;
    
    float dist = length(max(q, 0.0)) + min(max(q.x, q.y), 0.0) - cornerSize;    
    
    if (dist > 0.0) {
        discard;
    }        
    else if (dist > -(outerBorder + innerShadow + outerShadow)) {        
        
        // --- CORRECTION 2: OMBRE EXTERNE ---
        if (outerShadow != 0.0 && dist > -outerShadow) {
            sampledColor = outerShadowColor * v_col; // On multiplie par v_col
            sampledColor.a *= (1.0 - (outerShadow + dist) / (outerShadow));                
        }        
        // --- CORRECTION 3: BORDURE ---
        else if (dist > -(outerBorder + outerShadow)) {
            sampledColor = borderColor * v_col; // On multiplie par v_col
        }
        // --- CORRECTION 4: OMBRE INTERNE ---
        else if (innerShadow != 0.0) {        
            float val = abs(outerBorder + outerShadow + dist) / innerShadow;
            // On mixe avec l'ombre interne elle-même multipliée par v_col
            sampledColor = mix(sampledColor, innerShadowColor * v_col, innerShadowColor.a * (1.0 - val));           
        }
    }
    else {
        float pixelValue = 1.0 - smoothstep(-0.75, 0.5, dist);
        sampledColor.a *= pixelValue;
        sampledColor.rgb *= pixelValue;
    }
    
    FragColor = sampledColor;
}
#endif