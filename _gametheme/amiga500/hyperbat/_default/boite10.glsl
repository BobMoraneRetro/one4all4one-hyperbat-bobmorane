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
#extension GL_OES_standard_derivatives : enable
precision mediump float;
#endif

uniform sampler2D u_tex;
uniform float u_angle;
uniform float u_thickness;
uniform float u_mode;
uniform float u_pitch;
uniform float u_logo_scale;
uniform float u_shiny;
uniform vec4 u_cap_color;
uniform float u_box_ratio; // Ratio largeur/hauteur de la boîte (ex: 0.75). Si 0, pas de correction.

COMPAT_VARYING vec2 v_tex;
COMPAT_VARYING vec4 v_col;

// =====================
// ANTIALIAS GLOBAL
// =====================
float AA;
float antialias(float edge, float value) {
    return smoothstep(edge + AA, edge - AA, value);
}

// Fonction pour simuler le reflet plastique
float getSpecular(float angle, vec2 uv) {
    float lightPos = 0.5; 
    float refAngle = angle + lightPos;
    float spec = pow(max(0.0, cos(refAngle)), 10.0);
    float sheen = smoothstep(0.4, 0.6, sin(angle + uv.x * 3.0 + uv.y * 2.0));
    return (spec + sheen * 0.2) * u_shiny; 
}

void main(void) {

    float internalScale = 0.6;
    vec2 uv = (v_tex - 0.5) / internalScale;
    
    // AA Isotropique Ultra-Smooth
    float fwX = fwidth(uv.x);
    float fwY = fwidth(uv.y);
    AA = length(vec2(fwX, fwY)) * 3.0;
    AA = max(AA, 0.0025);

    // =====================
    // RATIO DE BOÎTE STANDARD
    // =====================
    // Si u_box_ratio est défini (> 0), on force la boîte à ce ratio (largeur/hauteur).
    // Le shader détecte le ratio du conteneur (le rectangle de rendu donné par ES via maxSize)
    // et ajuste la demi-largeur de la boîte pour que la boîte affichée ait le bon ratio.
    float halfWidth = 0.5; // Par défaut : boîte carrée en UV (ratio dépend du conteneur)
    
    if (u_box_ratio > 0.01) {
        // Ratio du conteneur à l'écran (largeur/hauteur en pixels)
        float containerRatio = fwidth(v_tex.y) / fwidth(v_tex.x);
        
        // Ajuster la demi-largeur en UV pour que la boîte apparaisse au ratio demandé
        halfWidth = 0.5 * u_box_ratio / containerRatio;
        
        // Clamp pour éviter que la boîte dépasse le conteneur
        halfWidth = min(halfWidth, 0.5);
    }

    float radAngle = radians(u_angle);
    if (u_mode > 0.5 && u_mode < 1.5) radAngle += 3.14159265;
    
    float cosA = cos(radAngle);
    float sinA = sin(radAngle);
    float halfThick = u_thickness * 0.5;

    float depthZ = 0.0;
    float texX = 0.5;
    float alphaX = 0.0;
    bool isFaceArea = false;

    // =====================
    // GÉOMÉTRIE HORIZONTALE
    // =====================
    if (u_mode < 0.5) { // FRONT
        if (cosA > 0.0) {
            float localX = (uv.x - halfThick * sinA) / cosA;
            alphaX = antialias(halfWidth, abs(localX));
            depthZ = -localX * sinA + halfThick * cosA;
            texX = localX / (halfWidth * 2.0) + 0.5; // Normaliser pour que 0-1 couvre la boîte
            isFaceArea = true;
        }
    }
    else if (u_mode > 1.5) { // SPINE
        float side = (sinA >= 0.0) ? 0.5 : -0.5;
        if (abs(sinA) > 0.001) {
            float localZ = (uv.x + side * cosA) / sinA;
            alphaX = antialias(halfThick, abs(localZ));
            depthZ = side * sinA + localZ * cosA;
            float rawTexX = (localZ / u_thickness) + 0.5;
            texX = (sinA >= 0.0) ? rawTexX : 1.0 - rawTexX;
            isFaceArea = true;
        }
    }
    else { // BACK
        if (cosA > 0.0) {
            float localX = (uv.x - halfThick * sinA) / cosA;
            alphaX = antialias(halfWidth, abs(localX));
            depthZ = -localX * sinA + halfThick * cosA;
            texX = localX / (halfWidth * 2.0) + 0.5;
            isFaceArea = true;
        }
    }

    // --- 2. GÉOMÉTRIE VERTICALE ---
    float EPSILON = 0.002;
    float yOffset = depthZ * u_pitch;
    float faceTop = 0.5 + yOffset;
    float faceBottom = -0.5 + yOffset;
    float edgeSoftness = AA * 1.5;
    
    // --- 3. RENDU EN COUCHES ---
    vec4 color = vec4(0.0);
    
    float baseLight = (u_mode > 1.5) ? abs(sinA) : abs(cosA);
    float light = 0.5 + 0.5 * baseLight; 
    
    float alphaY = smoothstep(faceBottom - edgeSoftness, faceBottom + edgeSoftness, uv.y) 
                 * smoothstep(faceTop + edgeSoftness, faceTop - edgeSoftness, uv.y);
    
    // ====== COUCHE 1 : COUVERCLES (TOP/BOTTOM CAP) ======
    bool showTop = (u_pitch < -0.001 && uv.y > faceTop - EPSILON);
    bool showDown = (u_pitch > 0.001 && uv.y < faceBottom + EPSILON);

    if (u_mode < 2.5 && (showTop || showDown)) {
        float yCapLimit = (uv.y > 0.0) ? 0.5 : -0.5;
        float pitchSafe = u_pitch + sign(u_pitch) * 0.0000001;
        float B = (uv.y - yCapLimit) / pitchSafe;
        
        float capX = uv.x * cosA - B * sinA;
        float capZ = uv.x * sinA + B * cosA;

        float capAA = AA;
        float edgeAlphaX = smoothstep(halfWidth + 0.001 + capAA, halfWidth + 0.001 - capAA, abs(capX));
        float edgeAlphaZ = smoothstep(halfThick + capAA, halfThick - capAA, abs(capZ));
        float capAlpha = edgeAlphaX * edgeAlphaZ;

        if (capAlpha > 0.001) {
            float capTexX = capX / (halfWidth * 2.0) + 0.5;
            float capTexY = (capZ / u_thickness) + 0.5;
            
            vec2 capTexCoord = vec2(clamp(capTexX, 0.0, 1.0), clamp(capTexY, 0.01, 0.99));
            vec4 rawCapColor = COMPAT_TEXTURE(u_tex, capTexCoord);
            
            vec3 customTint = (u_cap_color.a > 0.0) ? u_cap_color.rgb : vec3(0.65);
            vec3 capBaseColor = rawCapColor.rgb * customTint;

            float capLight = (uv.y > 0.0) ? 0.35 : 0.15;
            capLight *= (0.65 + 0.35 * abs(cosA));
            
            float capSpec = (u_shiny > 0.01) ? 0.2 * u_shiny * abs(cosA) : 0.0;
            
            vec3 finalCapRGB = capBaseColor * capLight + vec3(capSpec);
            color = vec4(finalCapRGB, capAlpha);
        }
    }
    
    // ====== COUCHE 2 : TEXTURE DE LA FACE ======
    if (uv.y <= faceTop + EPSILON && uv.y >= faceBottom - EPSILON) {
        float yPos = (uv.y - yOffset) + 0.5;
        vec2 finalTexCoord;

        if (u_mode > 2.5) {
            float startY, endY;
            bool rotate = false;
            if (u_mode < 3.15) { startY=0.80; endY=0.98; rotate=false; }
            else if (u_mode < 3.25) { startY=0.15; endY=0.85; rotate=true; }
            else { startY=0.02; endY=0.20; rotate=false; }
            
            float localY = (yPos - startY) / (endY - startY);
            float scale = (u_logo_scale > 0.01) ? u_logo_scale : 1.0;
            float finalY = (localY - 0.5) / scale + 0.5;
            
            if (finalY >= 0.0 && finalY <= 1.0) {
                if (rotate) finalTexCoord = vec2(finalY, 1.0 - texX);
                else finalTexCoord = vec2(texX, finalY);
            } else {
                discard; 
            }
        } else if (u_mode > 1.5) {
            finalTexCoord = vec2(0.01 + texX * 0.04, clamp(yPos, 0.0, 1.0));
        } else {
            // Faces (Modes 0.0/1.0)
            finalTexCoord = vec2(texX, clamp(yPos, 0.0, 1.0));
        }
        
        vec4 texColor = COMPAT_TEXTURE(u_tex, finalTexCoord);
        
        // --- REFLET SHINY SUR LA FACE ---
        float spec = 0.0;
        if (u_shiny > 0.01) {
            bool isSpine = (u_mode > 1.5);
            float faceAngle = isSpine ? radAngle + 1.5708 : radAngle;
            spec = getSpecular(faceAngle, uv);
        }

        vec3 finalRGB = texColor.rgb * light + vec3(spec);
        vec4 litTexColor = vec4(finalRGB, texColor.a * alphaX * alphaY);
        
        color.rgb = mix(color.rgb, litTexColor.rgb, litTexColor.a);
        color.a = max(color.a, litTexColor.a);
    }

    if (color.a <= 0.0) discard;
    FragColor = color * v_col;
}
#endif
