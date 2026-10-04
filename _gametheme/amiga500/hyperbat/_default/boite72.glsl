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
#define FragColor gl_FragColor
#define COMPAT_TEXTURE texture2D
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

// Global AA variable to be set in main
float AA = 0.0;

float antialias(float edge, float value) {
    return smoothstep(edge + AA, edge - AA, value);
}

void main(void) {
    float internalScale = 0.6; 
    vec2 uv = (v_tex - 0.5) / internalScale;
    
    // Calculate global AA from UV derivatives (smoother than local fwidth)
    AA = fwidth(uv.x) + fwidth(uv.y);
    
    float cosA = cos(u_angle);
    float sinA = sin(u_angle);
    float halfThick = u_thickness * 0.5;
    
    float depthZ = 0.0;
    float texX = 0.5;
    float alphaX = 0.0;
    bool isFaceArea = false;

    // --- 1. GÉOMÉTRIE HORIZONTALE ---
    if (u_mode < 0.5) { // FRONT
        if (cosA > 0.0) {
            float localX = (uv.x - halfThick * sinA) / cosA;
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
            isFaceArea = true;
        }
    }
    else { // BACK
        float cosAB = cos(u_angle + 3.14159265);
        float sinAB = sin(u_angle + 3.14159265);
        if (cosAB > 0.0) {
            float localX = (uv.x - halfThick * sinAB) / cosAB;
            alphaX = antialias(0.5, abs(localX));
            depthZ = -localX * sinAB + halfThick * cosAB;
            texX = localX + 0.5;
            isFaceArea = true;
        }
    }

    // We do NOT discard here anymore because the Cap (Lid) might jut out 
    // beyond the Face width at the corners.
    // if (!isFaceArea || alphaX <= 0.0) discard;

    // --- 2. GÉOMÉTRIE VERTICALE AVEC MARGE D'ERREUR ---
    // On ajoute un très petit EPSILON pour que les surfaces se chevauchent au lieu de se frôler
    float EPSILON = 0.001; 
    float yOffset = depthZ * u_pitch;
    float faceTop = 0.5 + yOffset;
    float faceBottom = -0.5 + yOffset;

    float edgeSoftness = AA;
    
    // --- 3. RENDU ---
    vec4 color = vec4(0.0);

    // Priorité à la FACE (on réduit légèrement ses limites pour laisser le cap prendre le relais proprement)
    if (uv.y <= faceTop && uv.y >= faceBottom) {
        float texY = (uv.y - yOffset) + 0.5;
        float streakAlpha = smoothstep(0.0, edgeSoftness, texY) * smoothstep(1.0, 1.0 - edgeSoftness, texY);
        
        if (u_mode > 1.5) { texX = 0.01 + (texX * 0.04); }
        vec4 texColor = COMPAT_TEXTURE(u_tex, vec2(texX, clamp(texY, 0.0, 1.0)));
        
        float light = (u_mode > 1.5) ? abs(sinA) * 0.7 : abs(cosA);
        float alphaY = smoothstep(faceBottom - edgeSoftness, faceBottom + edgeSoftness, uv.y) * smoothstep(faceTop + edgeSoftness, faceTop - edgeSoftness, uv.y);
        
        color = vec4(texColor.rgb * clamp(light, 0.4, 1.0), texColor.a * alphaX * alphaY * streakAlpha);
    } 
    
    // Rendu du COUVERCLE (on le fait dépasser d'un EPSILON pour boucher les trous)
    bool showTop = (u_pitch < -0.001 && uv.y > faceTop - EPSILON);
    bool showDown = (u_pitch > 0.001 && uv.y < faceBottom + EPSILON);

    if (showTop || showDown) {
        // Select the correct rotation angle for the Cap projection
        // If we are drawing the BACK face (u_mode between 0.5 and 1.5), we must use the Back angle (angle + PI).
        float capCos = cosA;
        float capSin = sinA;
        
        if (u_mode >= 0.5 && u_mode <= 1.5) { // BACK FACE mode
             capCos = cos(u_angle + 3.14159265);
             capSin = sin(u_angle + 3.14159265);
        }

        float yCapLimit = (uv.y > 0.0) ? 0.5 : -0.5;
        float B = (uv.y - yCapLimit) / (u_pitch + 0.0000001); 
        float capX = uv.x * capCos - B * capSin;
        float capZ = uv.x * capSin + B * capCos;

        // Expanded cap X check slightly (0.505 instead of 0.5) to ensure overlap with Face edges
        // This fixes the vertical line artifact at the corners.
        float cAlphaX = antialias(0.505, abs(capX));
        float cAlphaZ = antialias(halfThick, abs(capZ));
        float capAlpha = min(cAlphaX, cAlphaZ);

        if (capAlpha > 0.0) {
            float brightness = (uv.y > 0.0) ? 0.25 : 0.1; // Légèrement plus brillant pour masquer la couture
            brightness *= (0.7 + 0.3 * abs(cosA));
            vec4 capColor = vec4(vec3(brightness), capAlpha);
            
            // Mélange : le Cap remplit là où la Face est transparente ou absente
            color = mix(capColor, color, color.a);
        }
    }

    if (color.a <= 0.0) discard;
    FragColor = color * v_col;
}
#endif