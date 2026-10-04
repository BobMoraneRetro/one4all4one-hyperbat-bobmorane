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

void main(void)
{
    v_tex = vec2(TexCoord.x, 1.0 - TexCoord.y);
    v_col = COLOR;

    gl_Position =
        MVPMatrix *
        vec4(VertexCoord.xy, 0.0, 1.0);
}

#elif defined(FRAGMENT)

#if __VERSION__ >= 130
#define COMPAT_VARYING in
#define COMPAT_TEXTURE texture
out vec4 FragColor;
#else
#define COMPAT_VARYING varying
#define COMPAT_TEXTURE texture2D
#define FragColor gl_FragColor
#endif

#ifdef GL_ES
#ifdef GL_FRAGMENT_PRECISION_HIGH
precision highp float;
#else
precision mediump float;
#endif
#endif

COMPAT_VARYING vec2 v_tex;
COMPAT_VARYING vec4 v_col;

uniform sampler2D u_tex;

uniform float uTime;  // XML : <uTime>0</uTime> OBLIGATOIRE

// V7.3.1 — rotate HyperSpin = °/frame → ×60 (sinon 1–10 invisible sur lifespan 500 ms)
// V7.3 — fade plein-vie sans fadeIn ; (rotate °/s retiré : trop lent vs HS)
// V7.2 — angle="" → 0° (droite), comme HyperSpin ; startScale="" → ×1
// V7.1 — startScale="" → ×1 (spriteSizePx) ; (angle 0..360 retiré : incorrect)
// V7 — atlasOffset optionnel (auto-centré si absent) ; hérite v6.6.33 (Norm, gravité×60, birthGen)
// V6.6.33 — *Norm + pixels HyperSpin
// V6.6.32 — gravité HyperTheme (×60) + culling trajectoire
uniform float debugShow;
uniform float quality;
uniform float useSprite;
uniform float spriteSizePx;

uniform float lifespan;
uniform float ppm;

uniform float minRotate;
uniform float maxRotate;

uniform vec2 spriteAngle;
uniform float spriteAngleOsc;

uniform float scaleMinEnd;
uniform float scaleMaxEnd;

uniform float fade;
uniform float blendMode;
uniform float movement;
uniform float particlesOnTop;

uniform float themeWidth;
uniform float themeHeight;
uniform float emitterX;
uniform float emitterY;
uniform float emitterW;
uniform float emitterH;
// Fallback HyperSpin (uniquement si > 2 = pixels, pas le size 0..1 du calque)
uniform float x;
uniform float y;
uniform float width;
uniform float height;
uniform vec2 speed;
uniform vec2 speedNorm;       // fraction écran / s (prioritaire sur speed si non nul)
uniform vec2 angle;
uniform vec2 startScale;
uniform vec2 rotate;
uniform vec4 bound;
uniform vec2 xOscillate;
uniform vec2 xOscillateNorm;  // amp en fraction largeur (prioritaire sur xOscillate)
uniform vec2 scale;
uniform float rotateToAngle;
uniform float randomFrame;
uniform float frameCols;
uniform float frameRows;
uniform float frameCount;
uniform float atlasOffsetX;
uniform float atlasOffsetY;
uniform float limit;
uniform float particlesontop;
uniform float blendmode;

uniform vec2 emitterPos;
uniform vec2 emitterSize;

uniform float minAngle;
uniform float maxAngle;

uniform float minSpeed;
uniform float maxSpeed;

uniform float minSize;
uniform float maxSize;

uniform float gravity;
uniform float gravityNorm;    // UV/s² (prioritaire sur gravity si non nul)
uniform float accel;
uniform float accelNorm;      // UV/s² le long de la vitesse (prioritaire si non nul)

uniform float xOscAmplitude;
uniform float xOscFrequency;

uniform vec4 boundRect;

uniform vec2 pointSwarm;
uniform float swarmAttraction;
uniform float swarmOrbit;
uniform float swarmStartLife;
uniform float swarmRadius;
uniform float swarmFalloff;

uniform vec2 outputSize;
uniform vec2 textureSize;
uniform vec2 resolution;

float hash(float n)
{
    return fract(
        sin(n) *
        43758.5453123
    );
}

vec2 rot2d(vec2 v, float a)
{
    float c = cos(a);
    float s = sin(a);
    return vec2(
        v.x * c - v.y * s,
        v.x * s + v.y * c
    );
}

float particleShape(
    vec2 uv,
    vec2 center,
    float radius)
{
    float d = distance(uv, center);

    return smoothstep(
        radius,
        radius * 0.6,
        d
    );
}

float refScale()
{
    if (abs(outputSize.y) > 1.0)
        return abs(outputSize.y);
    if (abs(textureSize.y) > 1.0)
        return abs(textureSize.y);
    if (abs(resolution.y) > 1.0)
        return abs(resolution.y);
    return 1080.0;
}

vec2 spriteTexSize()
{
    if (abs(textureSize.x) > 1.0 && abs(textureSize.y) > 1.0)
        return abs(textureSize);
    if (abs(outputSize.x) > 1.0 && abs(outputSize.y) > 1.0)
        return abs(outputSize);
    return vec2(1920.0, 1080.0);
}

float aspectRatio()
{
    vec2 ts = spriteTexSize();
    return ts.x / max(ts.y, 1.0);
}

float distSq(vec2 a, vec2 b)
{
    vec2 d = a - b;
    return dot(d, d);
}

float distSqAspect(vec2 a, vec2 b, float asp)
{
    vec2 d = (a - b) * vec2(asp, 1.0);
    return dot(d, d);
}

bool particleMayHit(
    vec2 uv,
    vec2 spawn,
    vec2 approxPos,
    vec2 swarmCenter,
    float swarmRad,
    float reach,
    float asp)
{
    float r2 = reach * reach;

    if (distSqAspect(uv, approxPos, asp) <= r2)
        return true;

    if (distSqAspect(uv, spawn, asp) <= r2)
        return true;

    // Segment spawn → pos (sans bound, chute / trajectoire longue)
    vec2 uvA = uv * vec2(asp, 1.0);
    vec2 aA = spawn * vec2(asp, 1.0);
    vec2 bA = approxPos * vec2(asp, 1.0);
    vec2 ab = bA - aA;
    float abLen2 = dot(ab, ab);
    if (abLen2 > 1e-10) {
        float t = clamp(dot(uvA - aA, ab) / abLen2, 0.0, 1.0);
        vec2 closest = aA + ab * t;
        vec2 dSeg = uvA - closest;
        if (dot(dSeg, dSeg) <= r2)
            return true;
    }

    if (swarmRad > 0.0) {
        float swarmReach = swarmRad + reach;
        if (distSqAspect(uv, swarmCenter, asp) <= swarmReach * swarmReach)
            return true;
    }

    return false;
}

void main(void)
{
    if (debugShow > 0.5) {
        FragColor = vec4(1.0, 0.0, 1.0, 1.0) * v_col;
        return;
    }

    // HyperTheme : bound = boîte de rebond, PAS de disparition
    bool bounceBound = false;
    vec4 bounds = vec4(0.0, 0.0, 1.0, 1.0);
    if (bound.z > 0.0 && bound.w > 0.0) {
        float twB = (themeWidth > 1.0) ? themeWidth : bound.z;
        float thB = (themeHeight > 1.0) ? themeHeight : bound.w;
        bounds = vec4(
            bound.x / twB,
            bound.y / thB,
            bound.z / twB,
            bound.w / thB
        );
        bounceBound = true;
    } else if (boundRect.z > 0.0 && boundRect.w > 0.0) {
        bounds = boundRect;
        bounceBound = true;
    }

    float tw = (themeWidth > 1.0) ? themeWidth : 1024.0;
    float th = (themeHeight > 1.0) ? themeHeight : 768.0;
    if (bound.z > 0.0 && themeWidth <= 1.0)
        tw = bound.z;
    if (bound.w > 0.0 && themeHeight <= 1.0)
        th = bound.w;

    vec2 ePos = vec2(0.5, 0.0);
    vec2 eSize = vec2(0.0, 0.0);

    bool useEmitNamed =
        (emitterW > 2.0 || emitterH > 2.0 ||
         emitterX > 2.0 || emitterY > 2.0);
    bool useEmitLegacy =
        (width > 2.0 || height > 2.0 || x > 2.0 || y > 2.0);
    bool useEmitUV =
        (emitterSize.x > 0.001 || emitterSize.y > 0.001);

    if (useEmitNamed) {
        ePos = vec2(emitterX / tw, emitterY / th);
        eSize = vec2(emitterW / tw, max(emitterH, 1.0) / th);
    } else if (useEmitLegacy) {
        ePos = vec2(x / tw, y / th);
        eSize = vec2(width / tw, max(height, 1.0) / th);
    } else if (useEmitUV) {
        ePos = emitterPos;
        eSize = emitterSize;
    } else if (emitterPos.x != 0.0 || emitterPos.y != 0.0) {
        ePos = emitterPos;
        eSize = emitterSize;
    }

    // HyperSpin angle="" = 0° (vers la droite). Pour du 360°, écrire angle="0,360".
    float angMin = 0.0;
    float angMax = 0.0;
    if (angle.x != 0.0 || angle.y != 0.0) {
        angMin = angle.x;
        angMax = angle.y;
    } else if (minAngle != 0.0 || maxAngle != 0.0) {
        angMin = minAngle;
        angMax = maxAngle;
    }

    // speedNorm (fraction écran/s) prioritaire ; sinon speed HyperSpin (px/s)
    bool useSpeedNorm = (speedNorm.x > 0.0 || speedNorm.y > 0.0);
    float spdMin = minSpeed;
    float spdMax = maxSpeed;
    if (useSpeedNorm) {
        spdMin = speedNorm.x;
        spdMax = speedNorm.y;
        if (spdMax == 0.0) spdMax = spdMin;
        if (spdMin == 0.0) spdMin = spdMax;
    } else if (speed.x > 0.0 || speed.y > 0.0) {
        // HyperSpin speed="0,0" = immobile — ne pas forcer à 1.0
        spdMin = speed.x;
        spdMax = speed.y;
        if (spdMax == 0.0) spdMax = spdMin;
        if (spdMin == 0.0) spdMin = spdMax;
    } else if (speed.x == 0.0 && speed.y == 0.0) {
        if (minSpeed <= 0.0 && maxSpeed <= 0.0) {
            spdMin = 0.0;
            spdMax = 0.0;
        }
    } else if (spdMax == 0.0) {
        spdMax = spdMin;
    }

    float pxEarly = (spriteSizePx > 0.0) ? spriteSizePx : 46.0;
    // Taille ≈ spriteSizePx × startScale ; HyperSpin startScale="" → 1.0 (pas 0.01 UV)
    float szMin = minSize;
    float szMax = maxSize;
    if (startScale.x > 0.0) {
        float s0 = startScale.x;
        float s1 = (startScale.y > 0.0) ? startScale.y : startScale.x;
        szMin = (pxEarly * s0 * 0.5) / th;
        szMax = (pxEarly * s1 * 0.5) / th;
    } else if (spriteSizePx > 0.0 && szMin == 0.0 && szMax == 0.0) {
        szMin = (pxEarly * 0.5) / th;
        szMax = szMin;
    } else if (szMin == 0.0 && szMax == 0.0) { szMin = 0.01; szMax = 0.01; }
    else if (szMax == 0.0) szMax = szMin;

    float hsRotMin = minRotate;
    float hsRotMax = maxRotate;
    if (rotate.x > 0.0 || rotate.y > 0.0) {
        hsRotMin = rotate.x;
        hsRotMax = rotate.y;
        // HyperSpin "50,0" / "0,50" → vitesse constante (0 = copie l’autre)
        if (hsRotMin > 0.0 && hsRotMax == 0.0) hsRotMax = hsRotMin;
        if (hsRotMax > 0.0 && hsRotMin == 0.0) hsRotMin = hsRotMax;
    }

    float hsScaleMinEnd = scaleMinEnd;
    float hsScaleMaxEnd = scaleMaxEnd;
    if (scale.x > 0.0) {
        hsScaleMinEnd = scale.x;
        hsScaleMaxEnd = (scale.y > 0.0) ? scale.y : scale.x;
    }

    // xOscillateNorm : amp déjà en fraction de largeur ; sinon xOscillate en px thème
    bool useXOscNorm = (xOscillateNorm.x != 0.0 || xOscillateNorm.y != 0.0);
    float hsXOscAmp = xOscAmplitude;
    float hsXOscFreq = xOscFrequency;
    bool xOscAmpIsNorm = false;
    if (useXOscNorm) {
        hsXOscAmp = xOscillateNorm.x;
        hsXOscFreq = xOscillateNorm.y;
        xOscAmpIsNorm = true;
    } else if (xOscillate.x != 0.0 || xOscillate.y != 0.0) {
        hsXOscAmp = xOscillate.x;
        hsXOscFreq = xOscillate.y;
    }

    float hsFade = fade;
    float hsBlend = blendMode;
    float hsYoungOnTop = particlesOnTop;
    if (particlesontop > 0.0)
        hsYoungOnTop = particlesontop;
    if (blendmode > 0.0)
        hsBlend = blendmode;

    float swarmRad = swarmRadius;
    vec2 swarmCenter = pointSwarm;
    if (swarmRad > 0.0 && swarmCenter.x == 0.0 && swarmCenter.y == 0.0)
        swarmCenter = vec2(0.5, 0.5);

    // Mode pixels HyperSpin si speed (px) utilisé ; speedNorm = déjà normalisé
    float usePixels = 0.0;
    if (!useSpeedNorm && spdMax > 10.0)
        usePixels = 1.0;

    // gravityNorm / accelNorm = déjà normalisés (fraction écran / s²)
    // Sinon HyperTheme : delta/frame (~60 fps) → ×60 / themeSize
    bool useGravityNorm = (abs(gravityNorm) > 1e-8);
    bool useAccelNorm = (abs(accelNorm) > 1e-8);
    float gUV = 0.0;
    float accelPx = 0.0;
    float accelNormVal = 0.0;
    if (useGravityNorm) {
        gUV = gravityNorm;
    } else if (abs(gravity) > 1e-8) {
        gUV = (gravity * 60.0) / th;
    }
    if (useAccelNorm) {
        accelNormVal = accelNorm;
    } else if (abs(accel) > 1e-8) {
        accelPx = accel * 60.0;
    }

    bool spriteMode = (useSprite > 0.5);

    bool dynamicMove = true;
    if (movement > 1.5)
        dynamicMove = false;

    float nP = 24.0;
    float nS = 16.0;
    if (quality > 0.5 && quality < 1.5) {
        nP = spriteMode ? 24.0 : 32.0;
        nS = spriteMode ? 16.0 : 24.0;
    }
    if (quality > 1.5) {
        nP = spriteMode ? 32.0 : 48.0;
        nS = spriteMode ? 20.0 : 32.0;
    }

    float lifeRate = 0.03;
    if (lifespan > 0.0)
        lifeRate = 1000.0 / lifespan;
    else if (swarmRad <= 0.0 && swarmFalloff > 0.0)
        lifeRate = swarmFalloff;

    float lifeSpanSec = 1.0 / max(lifeRate, 1e-5);

    bool ppmMode = false;
    float ppmVal = ppm;
    if (ppmVal <= 0.0 && swarmRad <= 0.0 && swarmAttraction >= 1.0)
        ppmVal = swarmAttraction;

    if (ppmVal > 0.0) {
        ppmMode = true;
        float slots = ppmVal * lifeSpanSec / 60.0;
        if (slots < 1.0) slots = 1.0;
        if (slots > 96.0) slots = 96.0;
        nP = slots;
    } else if (swarmRad <= 0.0 && swarmAttraction > 0.0 && swarmAttraction < 1.0) {
        float scaled = nP * swarmAttraction;
        if (scaled < 1.0) scaled = 1.0;
        if (scaled > 96.0) scaled = 96.0;
        nP = scaled;
    }

    if (limit > 0.0) {
        if (nP > limit) nP = limit;
    }

    // HyperTheme Rotate = vitesse spin | spriteAngle = inclinaison fixe (°)
    bool spriteSpin =
        spriteMode &&
        (hsRotMin > 0.0 || hsRotMax > 0.0);

    float rotLo = hsRotMin;
    float rotHi = hsRotMax;
    if (rotHi < rotLo) {
        float t = rotLo;
        rotLo = rotHi;
        rotHi = t;
    }

    bool useSpriteAngle =
        spriteMode &&
        (spriteAngle.x != 0.0 || spriteAngle.y != 0.0);

    // HyperTheme X Oscillate : distance (px) + temps entre oscillations
    bool doXOscillate =
        (hsXOscAmp != 0.0 && hsXOscFreq != 0.0);

    bool scaleOverLife = (hsScaleMinEnd > 0.0 || hsScaleMaxEnd > 0.0);

    float fadeInEnd = 0.05;
    // HyperSpin fade="" → quasi pas de fondu avant la fin
    // HyperSpin fade="500" = durée du fade-out en ms (pas une fraction 0..1)
    float fadeOutStart = 0.90;
    if (hsFade > 0.0) {
        if (hsFade > 1.0) {
            float fadeSec = hsFade * 0.001;
            fadeOutStart = 1.0 - clamp(fadeSec / max(lifeSpanSec, 1e-5), 0.0, 1.0);
        } else {
            // Anciens XML qui passaient une fraction de vie
            fadeOutStart = 1.0 - clamp(hsFade, 0.01, 0.99);
        }
    }
    // fade ≈ lifespan (étoiles) : HyperSpin part opaque puis fade-out, sans fade-in
    if (fadeOutStart < 0.2)
        fadeInEnd = 0.0;

    bool additive = (hsBlend > 0.5);
    bool youngOnTop = (hsYoungOnTop > 0.5);

    float px = pxEarly;
    vec2 texSz = spriteTexSize();
    float asp = aspectRatio();

    float layerA = v_col.a;

    if (swarmRad > 0.0) {
        float globalPad = szMax * 1.6 + 0.12;
        vec2 emitCenter = ePos + eSize * 0.5;
        float emitReach = length(eSize) * 0.5 + globalPad;
        float swarmReach = swarmRad + globalPad;

        bool nearEmit = distSqAspect(v_tex, emitCenter, asp) <= emitReach * emitReach;
        bool nearSwarm = distSqAspect(v_tex, swarmCenter, asp) <= swarmReach * swarmReach;

        if (!nearEmit && !nearSwarm) {
            FragColor = vec4(0.0);
            return;
        }
    }

    float alpha = 0.0;
    vec3 rgb = vec3(0.0);
    float bestLife = 2.0;

    const int MAX_PARTICLES = 96;
    const int MAX_STEPS = 64;

    for(int i = 0; i < MAX_PARTICLES; i++)
    {
        float fi = float(i);
        if (fi >= nP) {
        } else {

        float seed = fi;

        float life = 0.0;
        float ageSec = 0.0;
        bool born = false;

        if (ppmMode) {
            // HyperTheme PPM : 1 particule toutes les (60/ppm) s, depuis uTime=0
            float interval = 60.0 / max(ppmVal, 1.0);
            float localTime = uTime - fi * interval;
            if (localTime >= 0.0) {
                born = true;
                ageSec = mod(localTime, lifeSpanSec);
                life = ageSec / max(lifeSpanSec, 1e-5);
            }
        } else {
            float phase = hash(seed + 100.0);
            float raw = uTime * lifeRate + phase;
            // Ignore les cycles « nés » avant l'ouverture du thème
            float cycleStart =
                (floor(raw) - phase) / max(lifeRate, 1e-5);
            if (cycleStart >= 0.0) {
                born = true;
                life = fract(raw);
                ageSec = life * lifeSpanSec;
            }
        }

        if (born) {

        float birthGen = 0.0;
        if (ppmMode) {
            float interval = 60.0 / max(ppmVal, 1.0);
            float lt = uTime - fi * interval;
            birthGen = floor(lt / max(lifeSpanSec, 1e-5));
        } else {
            float phase = hash(seed + 100.0);
            float raw = uTime * lifeRate + phase;
            birthGen = floor(raw);
        }
        // rnd change à chaque cycle de vie → frame + spawn + vitesse (HyperSpin)
        float rnd = seed + birthGen * 97.13;

        vec2 spawn;

        spawn.x =
            ePos.x +
            eSize.x *
            hash(rnd + 10.0);

        spawn.y =
            ePos.y +
            eSize.y *
            hash(rnd + 20.0);

        float angleDeg =
            mix(
                angMin,
                angMax,
                hash(rnd + 30.0)
            );

        float angleRad =
            radians(angleDeg);

        vec2 dir =
            vec2(
                cos(angleRad),
                sin(angleRad)
            );

        float speedRaw =
            mix(
                spdMin,
                spdMax,
                hash(rnd + 40.0)
            );

        // speedNorm = déjà fraction écran/s ; sinon px/s → / themeSize
        vec2 vel0;
        if (useSpeedNorm)
            vel0 = dir * speedRaw;
        else if (usePixels > 0.5)
            vel0 = vec2(
                cos(angleRad) * speedRaw / tw,
                sin(angleRad) * speedRaw / th
            );
        else
            vel0 = dir * (speedRaw * 0.30);

        float radius =
            mix(
                szMin,
                szMax,
                hash(rnd + 50.0)
            );

        if (scaleOverLife) {
            float endR = mix(
                max(hsScaleMinEnd, 0.001),
                max(hsScaleMaxEnd, 0.001),
                hash(rnd + 51.0)
            );
            radius *= mix(1.0, endR, life);
        }

        float reach = radius * 1.4 + 0.08;
        vec2 approxPos = spawn + vel0 * ageSec;
        approxPos.y += 0.5 * gUV * ageSec * ageSec;
        float cullReach = reach + 0.05 +
            length(vel0) * ageSec +
            abs(gUV) * ageSec * ageSec * 0.5;
        if (doXOscillate)
            cullReach += xOscAmpIsNorm
                ? abs(hsXOscAmp)
                : (abs(hsXOscAmp) / max(tw, 1.0));

        bool doSim;
        if (bounceBound) {
            float pad = reach + 0.02;
            doSim =
                v_tex.x >= (bounds.x - pad) &&
                v_tex.x <= (bounds.x + bounds.z + pad) &&
                v_tex.y >= (bounds.y - pad) &&
                v_tex.y <= (bounds.y + bounds.w + pad);
        } else {
            doSim =
                particleMayHit(
                    v_tex,
                    spawn,
                    approxPos,
                    swarmCenter,
                    swarmRad,
                    cullReach,
                    asp
                );
        }

        if (doSim) {

        vec2 pos = spawn;
        vec2 vel = vel0;

        if (dynamicMove) {

        float orbitDir =
        (
            hash(rnd + 500.0)
            > 0.5
        )
        ? 1.0
        : -1.0;

        float stepsF = nS;
        if (bounceBound) {
            // dt trop grand = collé au mur puis téléport — viser ~0.25–0.5 s / step
            stepsF = clamp(ceil(ageSec * 4.0), 24.0, 64.0);
        } else if (abs(gUV) > 1e-6 || abs(accelPx) > 1e-6 || abs(accelNormVal) > 1e-6) {
            // Gravité / accel : assez de steps sur toute la vie
            stepsF = clamp(ceil(ageSec * 4.0), 16.0, 64.0);
        } else if (life < 0.12) {
            stepsF = max(nS * 0.5, 8.0);
        }

        float dt =
            ageSec /
            max(stepsF, 1.0);

        for(int s = 0; s < MAX_STEPS; s++)
        {
            float fs = float(s);
            if (fs < stepsF) {

            float t =
                fs /
                stepsF;

            // Accel : Norm (UV/s²) prioritaire, sinon pixels HyperSpin
            if (abs(accelNormVal) > 1e-8) {
                float vLen = length(vel);
                if (vLen > 1e-6)
                    vel += (vel / vLen) * accelNormVal * dt;
                else
                    vel += dir * accelNormVal * dt;
            } else if (accelPx != 0.0) {
                vec2 velPx = vec2(vel.x * tw, vel.y * th);
                float vLenPx = length(velPx);
                if (vLenPx > 1e-6)
                    velPx += (velPx / vLenPx) * accelPx * dt;
                else
                    velPx += vec2(cos(angleRad), sin(angleRad)) * accelPx * dt;
                vel = vec2(velPx.x / tw, velPx.y / th);
            }

            vel.y +=
                gUV *
                dt;

            // xOscillate appliqué après le move (voir fin de sim)

            if (swarmRad > 0.0)
            {
                vec2 toCenter =
                    swarmCenter - pos;

                float dist =
                    length(toCenter);

                if(
                dist > 0.0001 &&
                dist < swarmRad
            )
            {
                vec2 radial =
                    normalize(toCenter);

                vec2 tangent =
                    vec2(
                        -radial.y,
                         radial.x
                    )
                    * orbitDir;

                float distanceFactor =
                    1.0 -
                    clamp(
                        dist /
                        swarmRad,
                        0.0,
                        1.0
                    );

                distanceFactor =
                    pow(
                        distanceFactor,
                        0.35
                    );

                if(swarmFalloff > 0.0 && swarmRad > 0.0)
                {
                    distanceFactor =
                        pow(
                            distanceFactor,
                            swarmFalloff
                        );
                }

                vec2 swarmForce =
                    (
                        radial *
                        swarmAttraction *
                        0.01

                        +

                        tangent *
                        swarmOrbit *
                        0.005
                    )
                    *
                    distanceFactor;

                swarmForce *=
                    smoothstep(
                        swarmStartLife,
                        1.0,
                        life
                    );

                vel +=
                    swarmForce *
                    dt;

                float damping =
                    mix(
                        1.0,
                        0.94,
                        distanceFactor
                    );

                vel *= damping;
            }
            }

            pos +=
                vel *
                dt;

            if (bounceBound) {
                float bx0 = bounds.x;
                float by0 = bounds.y;
                float bx1 = bounds.x + bounds.z;
                float by1 = bounds.y + bounds.w;
                // Réflexion overshoot (évite clamp + accumulation de vitesse)
                if (pos.x < bx0 && vel.x < 0.0) {
                    pos.x = bx0 + (bx0 - pos.x);
                    vel.x = -vel.x;
                } else if (pos.x > bx1 && vel.x > 0.0) {
                    pos.x = bx1 - (pos.x - bx1);
                    vel.x = -vel.x;
                }
                if (pos.y < by0 && vel.y < 0.0) {
                    pos.y = by0 + (by0 - pos.y);
                    vel.y = -vel.y;
                } else if (pos.y > by1 && vel.y > 0.0) {
                    pos.y = by1 - (pos.y - by1);
                    vel.y = -vel.y;
                }
                pos.x = clamp(pos.x, bx0, bx1);
                pos.y = clamp(pos.y, by0, by1);
            }
            }
        }
        }

        // X Oscillate : amp Norm = fraction largeur ; sinon px / themeWidth
        if (doXOscillate) {
            float period = abs(hsXOscFreq);
            if (period >= 100.0)
                period *= 0.001;
            period = max(period, 0.05);
            float ampUV = xOscAmpIsNorm ? hsXOscAmp : (hsXOscAmp / tw);
            float ph = hash(rnd + 70.0) * 6.2831853;
            pos.x += sin(ageSec * 6.2831853 / period + ph) * ampUV;
        }

        if (distSqAspect(v_tex, pos, asp) <= reach * reach) {

        float fadeIn =
            smoothstep(
                0.0,
                fadeInEnd,
                life
            );

        float fadeOut =
            1.0 -
            smoothstep(
                fadeOutStart,
                1.0,
                life
            );

        float lifeVis =
            fadeIn *
            fadeOut;

        float visibility = min(lifeVis, layerA);

        float a = 0.0;
        vec3 c = vec3(1.0);

        if (spriteMode) {
            vec2 local =
                (v_tex - pos) *
                vec2(asp, 1.0) /
                max(radius, 1e-5);
            if (spriteSpin || useSpriteAngle) {
                float rotA = 0.0;
                if (useSpriteAngle) {
                    float angMin = spriteAngle.x;
                    float angMax =
                        (spriteAngle.y != 0.0)
                        ? spriteAngle.y
                        : spriteAngle.x;
                    if (angMax < angMin) {
                        float tmp = angMin;
                        angMin = angMax;
                        angMax = tmp;
                    }
                    float angDeg;
                    if (spriteAngleOsc > 0.0) {
                        // Oscille entre angMin et angMax (spriteAngleOsc = Hz)
                        float w =
                            0.5 +
                            0.5 *
                            sin(
                                ageSec *
                                spriteAngleOsc *
                                6.2831853 +
                                hash(rnd + 62.0) * 6.2831853
                            );
                        angDeg = mix(angMin, angMax, w);
                    } else {
                        // Inclinaison fixe tirée une fois
                        angDeg = mix(
                            angMin,
                            angMax,
                            hash(rnd + 62.0)
                        );
                    }
                    rotA += radians(angDeg);
                }
                if (spriteSpin) {
                    float rotSpeed = mix(
                        rotLo,
                        rotHi,
                        hash(rnd + 60.0)
                    );
                    float spinDir =
                        (hash(rnd + 61.0) > 0.5) ? 1.0 : -1.0;
                    // HyperSpin / HyperTheme rotate ≈ °/frame @60fps → ×60 = °/s
                    rotA +=
                        radians(rotSpeed * 60.0 * ageSec) *
                        spinDir;
                }
                if (rotateToAngle > 0.5)
                    rotA += atan(vel.y, vel.x);
                local = rot2d(local, rotA);
            }
            if (abs(local.x) <= 1.0 && abs(local.y) <= 1.0) {
                float cellPx = px;
                vec2 frameCtr = texSz * 0.5;

                float rfVal = randomFrame;
                float nFrames = floor(frameCount + 0.5);
                if (nFrames < 2.0 && rfVal >= 2.0)
                    nFrames = floor(rfVal + 0.5);

                float cols = max(floor(frameCols + 0.5), 1.0);
                if (cols < 1.5 && nFrames >= 2.0)
                    cols = nFrames;
                float rows = max(floor(frameRows + 0.5), 1.0);
                if (rows < 1.5)
                    rows = max(ceil(nFrames / cols), 1.0);

                bool multiFrame =
                    nFrames >= 2.0 &&
                    (rfVal > 0.5);

                if (multiFrame) {
                    float idx = floor(
                        hash(rnd + 63.0) * nFrames
                    );
                    if (idx >= nFrames)
                        idx = nFrames - 1.0;
                    float col = mod(idx, cols);
                    float row = floor(idx / cols);
                    float aoX = atlasOffsetX;
                    float aoY = atlasOffsetY;
                    float stripW = cols * cellPx;
                    float stripH = rows * cellPx;
                    // atlasOffset renseigné (px) → origine manuelle de la planche
                    // sinon : planche serrée (tight) OU centrée auto dans le PNG
                    bool hasAtlasOffset = (aoX > 0.5 || aoY > 0.5);
                    bool tightAtlas =
                        !hasAtlasOffset &&
                        texSz.x <= stripW + 8.0 &&
                        texSz.y <= stripH + 8.0;

                    if (hasAtlasOffset) {
                        frameCtr = vec2(aoX, aoY) +
                            vec2(
                                col * cellPx + cellPx * 0.5,
                                row * cellPx + cellPx * 0.5
                            );
                    } else if (tightAtlas) {
                        frameCtr = vec2(
                            (col + 0.5) * cellPx,
                            (row + 0.5) * cellPx
                        );
                    } else {
                        // Auto : planche centrée dans la texture
                        vec2 origin =
                            texSz * 0.5 -
                            vec2(stripW, stripH) * 0.5;
                        frameCtr =
                            origin +
                            vec2(
                                col * cellPx + cellPx * 0.5,
                                row * cellPx + cellPx * 0.5
                            );
                    }
                }
                vec2 sprPx =
                    frameCtr +
                    local * (cellPx * 0.5);
                vec2 sprUV = sprPx / texSz;
                sprUV = vec2(sprUV.x, 1.0 - sprUV.y);
                vec4 spr = COMPAT_TEXTURE(u_tex, sprUV);
                a = spr.a * visibility;
                c = spr.rgb;
            }
        } else {
            float p =
                particleShape(
                    v_tex,
                    pos,
                    radius
                );
            a = p * visibility;
            c = vec3(1.0);
        }

        if (a > 0.001) {
            if (additive) {
                rgb += c * a * v_col.rgb;
                alpha = max(alpha, a * visibility);
            } else if (youngOnTop) {
                if (
                    a > alpha + 0.001 ||
                    (
                        abs(a - alpha) < 0.001 &&
                        life < bestLife
                    )
                ) {
                    alpha = a;
                    rgb = c;
                    bestLife = life;
                }
            } else {
                if (a > alpha) {
                    alpha = a;
                    rgb = c;
                    bestLife = life;
                }
            }
            }
        }
        }
        }
        }
    }

    if (additive)
        FragColor = vec4(clamp(rgb, 0.0, 1.0), clamp(alpha, 0.0, 1.0));
    else
        FragColor = vec4(rgb * v_col.rgb, alpha);
}

#endif
