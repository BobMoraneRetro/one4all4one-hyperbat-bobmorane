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

COMPAT_VARYING vec2 v_tex;
COMPAT_VARYING vec4 v_col;

// =====================
// ANTIALIAS GLOBAL
// =====================
float AA;
float antialias(float edge, float value) {
    return smoothstep(edge + AA, edge - AA, value);
}

// Fonction pour simuler le reflet plastique (Optimisée & Fresnel)
float getSpecular(float angle, vec2 uv, float cosA) {
    float lightPos = 0.5; 
    float refAngle = angle + lightPos;
    
    // Optimisation : x*x*x*x (puissance 8) au lieu de pow(cos, 10)
    float x = max(0.0, cos(refAngle));
    float x2 = x * x;
    float x4 = x2 * x2;
    float spec = x4 * x4; 
    
    // Lissage du sheen (scintillement réduit)
    float sheen = smoothstep(0.3, 0.7, sin(angle + uv.x * 2.0 + uv.y * 1.5)) * 0.15;
    
    // Effet Fresnel (plus de reflet sur les angles rasants)
    float fresnel = 0.2 + 0.8 * pow(1.0 - abs(cosA), 3.0);
    
    return (spec + sheen) * u_shiny * fresnel; 
}

void main(void) {

    float internalScale = 0.6;
    vec2 uv = (v_tex - 0.5) / internalScale;
    
    // AA Stabilisé
    AA = max(fwidth(uv.x), fwidth(uv.y));

    float radAngle = radians(u_angle);
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
            float rawTexX = (localZ / u_thickness) + 0.5;
            texX = (sinA >= 0.0) ? rawTexX : 1.0 - rawTexX;
            isFaceArea = true;
        }
    }
    else { // BACK
        float cosAB = cos(radAngle + 3.14159265);
        float sinAB = sin(radAngle + 3.14159265);
        if (cosAB > 0.0) {
            float localX = (uv.x - halfThick * sinAB) / cosAB;
            alphaX = antialias(0.5, abs(localX));
            depthZ = -localX * sinAB + halfThick * cosAB;
            texX = localX + 0.5;
            isFaceArea = true;
        }
    }

    if (!isFaceArea || alphaX <= 0.0) discard;

    // --- 2. GÉOMÉTRIE VERTICALE ---
    float yOffset = depthZ * u_pitch;
    float faceTop = 0.5 + yOffset;
    float faceBottom = -0.5 + yOffset;
    float edgeSoftness = fwidth(uv.y);
    
    // --- 3. RENDU EN COUCHES ---
    vec4 color = vec4(0.0);
    
    // Éclairage de base lissé (évite le noir total à 90°)
    float baseLight = (u_mode > 1.5) ? abs(sinA) : abs(cosA);
    float light = 0.5 + 0.5 * baseLight; 
    
    // Alpha vertical pour les bords doux
    float alphaY = smoothstep(faceBottom - edgeSoftness, faceBottom + edgeSoftness, uv.y) 
                 * smoothstep(faceTop + edgeSoftness, faceTop - edgeSoftness, uv.y);
    
    // ====== COUCHE 1 : COUVERCLES (TOP/BOTTOM CAP) ======
    bool showTop = (u_pitch < -0.001);
    bool showDown = (u_pitch > 0.001);

    if (u_mode < 2.5 && (showTop || showDown)) {
        float yCapLimit = showTop ? 0.5 : -0.5;
        float yCapEdge = showTop ? faceTop : faceBottom;
        
        bool inCapZone = showTop ? (uv.y > yCapEdge) : (uv.y < yCapEdge);
        
        if (inCapZone) {
            // Division stabilisée
            float pitchSafe = max(abs(u_pitch), 0.01) * sign(u_pitch);
            float B = (uv.y - yCapLimit) / pitchSafe;
            
            float capX = uv.x * cosA - B * sinA;
            float capZ = uv.x * sinA + B * cosA;

            if (abs(capX) <= 0.5 && abs(capZ) <= halfThick) {
                float capAA = AA * 1.2;
                float edgeAlphaX = smoothstep(0.5 + capAA, 0.5 - capAA, abs(capX));
                float edgeAlphaZ = smoothstep(halfThick + capAA, halfThick - capAA, abs(capZ));
                float capAlpha = edgeAlphaX * edgeAlphaZ;

                if (capAlpha > 0.001) {
                    float capLight = (showTop ? 0.35 : 0.15) * (0.7 + 0.3 * abs(cosA));
                    float capSpec = (u_shiny > 0.01) ? 0.15 * u_shiny * abs(cosA) : 0.0;
                    color = vec4(vec3(capLight + capSpec), capAlpha);
                }
            }
        }
    }
    
    // ====== COUCHE 2 : TEXTURE DE LA FACE ======
    if (uv.y <= faceTop && uv.y >= faceBottom) {
        float yPos = (uv.y - yOffset) + 0.5;
        vec2 finalTexCoord;

        if (u_mode > 2.5) { // DECO TRANCHE
            float startY, endY;
            bool rotate = false;
            if (u_mode < 3.15) { startY=0.80; endY=0.98; rotate=false; }
            else if (u_mode < 3.25) { startY=0.15; endY=0.85; rotate=true; }
            else { startY=0.02; endY=0.20; rotate=false; }
            
            float localY = (yPos - startY) / (endY - startY);
            float scale = max(0.01, u_logo_scale);
            float finalY = (localY - 0.5) / scale + 0.5;
            
            if (finalY >= 0.0 && finalY <= 1.0) {
                if (rotate) finalTexCoord = vec2(finalY, 1.0 - texX);
                else finalTexCoord = vec2(texX, finalY);
            } else { discard; }
        } else if (u_mode > 1.5) {
            finalTexCoord = vec2(0.01 + texX * 0.04, clamp(yPos, 0.0, 1.0));
        } else {
            finalTexCoord = vec2(texX, clamp(yPos, 0.0, 1.0));
        }
        
        vec4 texColor = COMPAT_TEXTURE(u_tex, finalTexCoord);
        
        // --- AMÉLIORATIONS VISUELLES PREMIUM ---
        vec3 finalRGB = texColor.rgb;
        
        // 1. Éclairage
        finalRGB *= light;
        
        // 2. Ombre de profondeur (donne du volume à la tranche)
        float depthShadow = 0.85 + 0.15 * smoothstep(0.0, halfThick, abs(depthZ));
        finalRGB *= depthShadow;
        
        // 3. Ambient Occlusion simulée (bords plus profonds)
        float edgeAO = smoothstep(0.4, 0.5, abs(uv.x)) * 0.15;
        finalRGB *= (1.0 - edgeAO);

        // 4. Reflet Shiny (avec Fresnel)
        float spec = 0.0;
        if (u_shiny > 0.01) {
            float faceAngle = (u_mode > 1.5) ? radAngle + 1.5708 : radAngle;
            spec = getSpecular(faceAngle, uv, cosA);
        }
        finalRGB += vec3(spec);

        vec4 litTexColor = vec4(finalRGB, texColor.a * alphaX * alphaY);
        color.rgb = mix(color.rgb, litTexColor.rgb, litTexColor.a);
        color.a = max(color.a, litTexColor.a);
    }

    if (color.a <= 0.0) discard;
    FragColor = color * v_col;
}
#endif



