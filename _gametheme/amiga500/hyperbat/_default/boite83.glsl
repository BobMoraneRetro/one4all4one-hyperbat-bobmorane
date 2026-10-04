#if defined(VERTEX)
uniform mat4 MVPMatrix;
attribute vec2 VertexCoord;
attribute vec2 TexCoord;
attribute vec4 COLOR;
varying vec2 v_tex;
varying vec4 v_col;

void main(void) {
    gl_Position = MVPMatrix * vec4(VertexCoord.xy, 0.0, 1.0);
    v_tex = TexCoord;
    v_col = COLOR;
}

#elif defined(FRAGMENT)
#ifdef GL_ES
precision mediump float;
#endif

uniform sampler2D u_tex;
uniform float u_angle;     
uniform float u_thickness; 
uniform float u_mode;      
uniform float u_pitch;
uniform float u_logo_scale; 
uniform float u_shiny;      // <--- NOUVEAU : Intensité du reflet (0.0 à 1.0)

varying vec2 v_tex;
varying vec4 v_col;

float antialias(float edge, float value) {
    float fw = fwidth(value);
    return smoothstep(edge + fw, edge - fw, value);
}

// Fonction pour simuler le reflet plastique
float getSpecular(float angle, vec2 uv) {
    // Lumière virtuelle venant de "haut-gauche"
    float lightPos = 0.5; 
    
    // Le reflet bouge en fonction de l'angle de la boite
    float refAngle = angle + lightPos;
    
    // Pic de brillance (Specular highlight)
    float spec = pow(max(0.0, cos(refAngle)), 10.0);
    
    // Petit dégradé diagonal pour faire "film plastique"
    float sheen = smoothstep(0.4, 0.6, sin(angle + uv.x * 3.0 + uv.y * 2.0));
    
    return (spec + sheen * 0.2) * u_shiny; 
}

void main(void) {
    float internalScale = 0.6; 
    vec2 uv = (v_tex - 0.5) / internalScale;
    
    float rads = u_angle;
    if (u_mode > 0.5 && u_mode < 1.5) rads += 3.14159265; 
    
    float cosA = cos(rads);
    float sinA = sin(rads);
    float halfThick = u_thickness * 0.5;
    float overlap = 0.003; 

    float depthZ = 0.0;
    float texX = 0.5;
    float alphaX = 0.0;
    bool validFace = false;
    bool isSpine = false;

    // --- GEOMETRIE ---
    if (u_mode > 1.5) { // TRANCHE
        if (abs(sinA) > 0.001) {
            float side = (sinA >= 0.0) ? 0.5 : -0.5;
            float localZ = (uv.x + side * cosA) / sinA;
            alphaX = antialias(halfThick + overlap, abs(localZ)); 
            depthZ = side * sinA + localZ * cosA;
            texX = (localZ / u_thickness) + 0.5;
            validFace = true;
            isSpine = true;
        }
    } else { // FACE
        if (cosA > 0.0) {
            float localX = (uv.x - halfThick * sinA) / cosA;
            alphaX = antialias(0.5 + overlap, abs(localX)); 
            depthZ = -localX * sinA + halfThick * cosA;
            texX = (u_mode > 0.5) ? 1.0 - (localX + 0.5) : (localX + 0.5);
            validFace = true;
        }
    }

    if (!validFace || alphaX <= 0.0) discard;

    float yOffset = depthZ * u_pitch;
    float faceTop = 0.5 + yOffset;
    float faceBottom = -0.5 + yOffset;
    
    if (uv.y < faceTop + 0.005 && uv.y > faceBottom - 0.005) {
        float yPos = (uv.y - yOffset) + 0.5; 
        vec2 finalTexCoord;
        
        // --- LOGIQUE TEXTURE ---
        if (u_mode > 2.5) { // DECO TRANCHE
            float startY, endY;
            bool rotate = false;
            if (u_mode < 3.15) { startY=0.80; endY=0.98; rotate=false; }
            else if (u_mode < 3.25) { startY=0.15; endY=0.85; rotate=true; }
            else { startY=0.02; endY=0.20; rotate=false; }
            
            float localY = (yPos - startY) / (endY - startY);
            float scale = (u_logo_scale > 0.0) ? u_logo_scale : 1.0;
            float finalY = (localY - 0.5) / scale + 0.5;
            if (finalY < 0.0 || finalY > 1.0) discard;
            if (rotate) finalTexCoord = vec2(finalY, 1.0 - texX);
            else finalTexCoord = vec2(texX, finalY);
        } else if (u_mode > 1.5) { 
             finalTexCoord = vec2(0.005, clamp(yPos, 0.01, 0.99));
        } else { 
             finalTexCoord = vec2(texX, clamp(yPos, 0.005, 0.995));
        }

        vec4 texSample = texture2D(u_tex, finalTexCoord);
        
        // --- LUMIERE & REFLET (NOUVEAU) ---
        float light = (isSpine) ? abs(sinA) * 0.75 : abs(cosA);
        
        // Calcul du reflet plastique
        float spec = 0.0;
        if (u_shiny > 0.01) {
            // Reflet différent sur la tranche et la face
            float faceAngle = isSpine ? rads + 1.57 : rads;
            spec = getSpecular(faceAngle, uv);
        }

        float fwy = fwidth(uv.y);
        float alphaY = smoothstep(faceBottom - fwy, faceBottom + fwy + 0.005, uv.y) * smoothstep(faceTop + fwy, faceTop - fwy - 0.005, uv.y);
        
        // Ajout du reflet (additif)
        vec3 finalRGB = texSample.rgb * clamp(light, 0.4, 1.0) + vec3(spec);
        
        gl_FragColor = vec4(finalRGB, texSample.a * alphaX * alphaY);
    } 
    else if (u_mode < 2.5) { // COUVERCLE
        float yCapLimit = (uv.y > 0.0) ? 0.5 : -0.5;
        float B = (uv.y - yCapLimit) / (u_pitch + 0.00001);
        float capX = uv.x * cosA - B * sinA;
        float capZ = uv.x * sinA + B * cosA;
        float cAlpha = min(antialias(0.5 + overlap, abs(capX)), antialias(halfThick + overlap, abs(capZ)));
        
        if (cAlpha > 0.0) {
            float br = (uv.y > 0.0) ? 0.3 : 0.15;
            // Petit reflet sur le couvercle aussi si shiny
            float capSpec = (u_shiny > 0.0) ? 0.2 * u_shiny * abs(cosA) : 0.0;
            gl_FragColor = vec4(vec3(br * (0.6 + 0.4 * abs(cosA)) + capSpec), cAlpha * alphaX);
        } else { discard; }
    } else { discard; }
}
#endif