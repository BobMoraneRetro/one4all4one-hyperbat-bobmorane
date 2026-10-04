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

varying vec2 v_tex;
varying vec4 v_col;

float antialias(float edge, float value) {
    float fw = fwidth(value);
    return smoothstep(edge + fw, edge - fw, value);
}

void main(void) {
    float internalScale = 0.6; 
    vec2 uv = (v_tex - 0.5) / internalScale;
    
    float rads = u_angle;
    if (u_mode > 0.5 && u_mode < 1.5) rads += 3.14159265; 
    
    float cosA = cos(rads);
    float sinA = sin(rads);
    float halfThick = u_thickness * 0.5;
    float overlap = 0.003; // Un poil plus d'overlap pour la sécurité

    float depthZ = 0.0;
    float texX = 0.5;
    float alphaX = 0.0;
    bool validFace = false;

    // --- GÉOMÉTRIE ---
    if (u_mode > 1.5) { 
        if (abs(sinA) > 0.001) {
            float side = (sinA >= 0.0) ? 0.5 : -0.5;
            float localZ = (uv.x + side * cosA) / sinA;
            alphaX = antialias(halfThick + overlap, abs(localZ)); 
            depthZ = side * sinA + localZ * cosA;
            texX = (localZ / u_thickness) + 0.5;
            validFace = true;
        }
    } else { 
        if (cosA > 0.0) {
            float localX = (uv.x - halfThick * sinA) / cosA;
            alphaX = antialias(0.5 + overlap, abs(localX)); 
            depthZ = -localX * sinA + halfThick * cosA;
            texX = (u_mode > 0.5) ? 1.0 - (localX + 0.5) : (localX + 0.5);
            validFace = true;
        }
    }

    if (!validFace || alphaX <= 0.0) discard;

    // --- RENDU VERTICAL ---
    float yOffset = depthZ * u_pitch;
    float faceTop = 0.5 + yOffset;
    float faceBottom = -0.5 + yOffset;
    
    if (uv.y < faceTop + 0.005 && uv.y > faceBottom - 0.005) {
        float yPos = (uv.y - yOffset) + 0.5; // 0 (bas) à 1 (haut)
        vec2 finalTexCoord;
        
        if (u_mode > 2.5) {
            // --- LOGIQUE DES ZONES DE TRANCHE ---
            float startY, endY;
            bool rotate = false;
            
            // Définition des zones (Tu peux ajuster ces chiffres ici)
            if (u_mode < 3.15) {      // 3.1 : HAUT
                startY = 0.80; endY = 0.98; rotate = false;
            } else if (u_mode < 3.25) { // 3.2 : MILIEU (Marquee)
                startY = 0.15; endY = 0.85; rotate = true;
            } else {                   // 3.3 : BAS
                startY = 0.02; endY = 0.20; rotate = false;
            }

            // On normalise yPos dans la zone choisie (devient un nouveau 0.0 à 1.0)
            float localY = (yPos - startY) / (endY - startY);
            
            // Application du scale interne
            float scale = (u_logo_scale > 0.0) ? u_logo_scale : 1.0;
            float finalY = (localY - 0.5) / scale + 0.5;

            // On vire ce qui dépasse de la zone
            if (finalY < 0.0 || finalY > 1.0) discard;

            if (rotate) {
                finalTexCoord = vec2(finalY, 1.0 - texX); // Pivoté
            } else {
                finalTexCoord = vec2(texX, finalY);       // Droit
            }
        } 
        else if (u_mode > 1.5) { // MODE 2.0 (Fond de tranche)
             finalTexCoord = vec2(0.005, clamp(yPos, 0.01, 0.99));
        }
        else { // MODES 0.0 / 1.0 (Face / Dos)
             finalTexCoord = vec2(texX, clamp(yPos, 0.005, 0.995));
        }

        vec4 texSample = texture2D(u_tex, finalTexCoord);
        float light = (u_mode > 1.5) ? abs(sinA) * 0.75 : abs(cosA);
        float fwy = fwidth(uv.y);
        float alphaY = smoothstep(faceBottom - fwy, faceBottom + fwy + 0.005, uv.y) * smoothstep(faceTop + fwy, faceTop - fwy - 0.005, uv.y);
        
        gl_FragColor = vec4(texSample.rgb * clamp(light, 0.4, 1.0), texSample.a * alphaX * alphaY);
    } 
    else if (u_mode < 2.5) { // COUVERCLE
        float yCapLimit = (uv.y > 0.0) ? 0.5 : -0.5;
        float B = (uv.y - yCapLimit) / (u_pitch + 0.00001);
        float capX = uv.x * cosA - B * sinA;
        float capZ = uv.x * sinA + B * cosA;
        float cAlpha = min(antialias(0.5 + overlap, abs(capX)), antialias(halfThick + overlap, abs(capZ)));
        if (cAlpha > 0.0) {
            float br = (uv.y > 0.0) ? 0.3 : 0.15;
            gl_FragColor = vec4(vec3(br * (0.6 + 0.4 * abs(cosA))), cAlpha * alphaX);
        } else { discard; }
    } else { discard; }
}
#endif