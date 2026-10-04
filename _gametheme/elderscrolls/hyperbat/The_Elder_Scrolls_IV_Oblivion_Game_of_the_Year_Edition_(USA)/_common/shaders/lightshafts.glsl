// HyperBat Light Shafts Shader
// Rayons lumineux animés (linéaire / radial / coin), porté du shader custom
// "lightshafts" du thème Wallpaper Engine 3492319908 "Ikki Tousen".
// Le bruit est généré procéduralement (même hash/noise que tvnoise.glsl) :
// aucune texture externe requise. Compatible ES GLSL shader pipeline.
//
// Uniforms pilotables (storyboard "shader.xxx") — 0 = valeur d'origine de la scène :
//   shaftsTime    : temps en secondes (animer 0 -> 3600 sur 3600000 ms, repeat 0)
//   rayMode       : 0 = radial (scène), 1 = linéaire, 2 = coin
//   rayCorner     : pour rayMode 2 : 0 = haut-gauche, 1 = haut-droit, 2 = bas-gauche, 3 = bas-droit
//   directDraw    : 0 = rayons par-dessus la texture de l'élément, 1 = rayons seuls
//   raySpeed      : vitesse de défilement        (scène : 0.34)
//   rayScale      : échelle de forme (vec2)      (scène : 0.69 1.05)
//   raySmoothness : adoucissement du seuillage   (scène : 0.6)
//   rayFeather    : fondu des bords (vec2)       (scène : 0.23 0.07)
//   rayRadius     : rayon intérieur              (scène : 0.1)
//   noiseScale    : échelle du bruit (mode coin) (scène : 1.17)
//   noiseAmount   : quantité de bruit (mode coin)(scène : 0.33)
//   rayIntensity  : intensité de la couleur      (scène : 2.92)
//   rayExponent   : exposant de contraste        (scène : 1.24)
//   colorStart    : couleur au centre (vec4)     (scène : 1 1 1 1)
//   colorEnd      : couleur en bord (vec4)       (scène : 0.435 0.886 1.0 1)
//   startAngle / endAngle : fenêtre angulaire [0..1] (scène : 0 / 1)
//   point0..point3 : quadrilatère de perspective (vec2, tous à 0 = carré unité)

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
COMPAT_VARYING   vec3 v_texfx;

// Quadrilatère de perspective dans l'espace UV (0 partout = carré unité)
uniform COMPAT_PRECISION vec2 point0;
uniform COMPAT_PRECISION vec2 point1;
uniform COMPAT_PRECISION vec2 point2;
uniform COMPAT_PRECISION vec2 point3;

// Homographie carré unité -> quadrilatère (portage de Wallpaper Engine,
// common_perspective.h). Inverse écrite à la main : compatible GLSL < 140.
mat3 squareToQuad(vec2 p0, vec2 p1, vec2 p2, vec2 p3) {
    mat3 m = mat3(1.0, 0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0, 1.0);
    float dx0 = p0.x;
    float dy0 = p0.y;
    float dx1 = p1.x;
    float dy1 = p1.y;
    float dx2 = p3.x;
    float dy2 = p3.y;
    float dx3 = p2.x;
    float dy3 = p2.y;

    float diffx1 = dx1 - dx3;
    float diffy1 = dy1 - dy3;
    float diffx2 = dx2 - dx3;
    float diffy2 = dy2 - dy3;

    float det = diffx1 * diffy2 - diffx2 * diffy1;
    float sumx = dx0 - dx1 + dx3 - dx2;
    float sumy = dy0 - dy1 + dy3 - dy2;

    if (det == 0.0 || (sumx == 0.0 && sumy == 0.0)) {
        m[0][0] = dx1 - dx0;
        m[0][1] = dy1 - dy0;
        m[0][2] = 0.0;
        m[1][0] = dx3 - dx1;
        m[1][1] = dy3 - dy1;
        m[1][2] = 0.0;
        m[2][0] = dx0;
        m[2][1] = dy0;
        m[2][2] = 1.0;
    } else {
        float ovdet = 1.0 / det;
        float g = (sumx * diffy2 - diffx2 * sumy) * ovdet;
        float h = (diffx1 * sumy - sumx * diffy1) * ovdet;

        m[0][0] = dx1 - dx0 + g * dx1;
        m[0][1] = dy1 - dy0 + g * dy1;
        m[0][2] = g;
        m[1][0] = dx2 - dx0 + h * dx2;
        m[1][1] = dy2 - dy0 + h * dy2;
        m[1][2] = h;
        m[2][0] = dx0;
        m[2][1] = dy0;
        m[2][2] = 1.0;
    }
    return m;
}

mat3 mat3Inverse(mat3 m) {
    float a00 = m[0][0], a01 = m[0][1], a02 = m[0][2];
    float a10 = m[1][0], a11 = m[1][1], a12 = m[1][2];
    float a20 = m[2][0], a21 = m[2][1], a22 = m[2][2];
    float b01 = a22 * a11 - a12 * a21;
    float b11 = -a22 * a10 + a12 * a20;
    float b21 = a21 * a10 - a11 * a20;
    float det = a00 * b01 + a01 * b11 + a02 * b21;
    return mat3(b01, (-a22 * a01 + a02 * a21), (a12 * a01 - a02 * a11),
                b11, (a22 * a00 - a02 * a20), (-a12 * a00 + a02 * a10),
                b21, (-a21 * a00 + a01 * a20), (a11 * a00 - a01 * a10)) / det;
}

void main(void)
{
    vec2 hbTexCoord = vec2(TexCoord.x, 1.0 - TexCoord.y); // HB-FLIPV: ES texcoords -> espace effet (toutes varyings géométriques conjuguées)
    gl_Position = MVPMatrix * vec4(VertexCoord.xy, 0.0, 1.0);
    v_tex       = hbTexCoord;
    v_col       = COLOR;

    vec2 p0 = point0;
    vec2 p1 = point1;
    vec2 p2 = point2;
    vec2 p3 = point3;
    // Tous les points à zéro = non configuré -> carré unité (pas de perspective)
    if (dot(abs(p0) + abs(p1) + abs(p2) + abs(p3), vec2(1.0)) == 0.0) {
        p1 = vec2(1.0, 0.0);
        p2 = vec2(1.0, 1.0);
        p3 = vec2(0.0, 1.0);
    }
    mat3 xform = mat3Inverse(squareToQuad(p0, p1, p2, p3));
    v_texfx = xform * vec3(hbTexCoord.xy, 1.0);
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

COMPAT_VARYING vec4 v_col;
COMPAT_VARYING vec2 v_tex;
COMPAT_VARYING vec3 v_texfx;

uniform sampler2D u_tex;
vec2 hbFlipV(vec2 p) { return vec2(p.x, 1.0 - p.y); } // HB-FLIPV


uniform COMPAT_PRECISION float shaftsTime;
uniform int rayMode;        // 0 = radial, 1 = linéaire, 2 = coin
uniform int rayCorner;      // 0..3 (mode coin)
uniform int directDraw;     // 1 = rayons seuls, sans la texture de l'élément
uniform COMPAT_PRECISION vec2 rayCenter;  // centre d'émission (UV, mode radial, 0 0 = 0.5 0.5)

uniform COMPAT_PRECISION float raySpeed;
uniform COMPAT_PRECISION vec2  rayScale;
uniform COMPAT_PRECISION float raySmoothness;
uniform COMPAT_PRECISION vec2  rayFeather;
uniform COMPAT_PRECISION float rayRadius;
uniform COMPAT_PRECISION float noiseScale;
uniform COMPAT_PRECISION float noiseAmount;
uniform COMPAT_PRECISION float rayIntensity;
uniform COMPAT_PRECISION float rayExponent;
uniform COMPAT_PRECISION vec4  colorStart;
uniform COMPAT_PRECISION vec4  colorEnd;
uniform COMPAT_PRECISION float startAngle;
uniform COMPAT_PRECISION float endAngle;

// ── Masque de zone (placement de l'effet, équivalent du masque peint WE) ──
uniform int maskMode;                        // 0 = partout, 1 = rectangle, 2 = ellipse
uniform COMPAT_PRECISION vec2  maskCenter;   // centre de la zone (UV)
uniform COMPAT_PRECISION vec2  maskSize;     // taille de la zone (UV, 0 = 0.5 0.5)
uniform COMPAT_PRECISION float maskSoftness; // douceur du bord
uniform int maskInvert;                      // 1 = effet hors de la zone

float zoneMask(vec2 uv) {
    if (maskMode == 0) return 1.0;
    vec2 size = (maskSize.x == 0.0 && maskSize.y == 0.0) ? vec2(0.5, 0.5) : maskSize;
    vec2 d = abs(uv - maskCenter) / max(size * 0.5, vec2(1e-5));
    float dist = (maskMode == 2) ? length(d) : max(d.x, d.y);
    float soft = max(maskSoftness, 1e-4);
    float m = 1.0 - smoothstep(1.0 - soft, 1.0 + soft, dist);
    return (maskInvert == 1) ? 1.0 - m : m;
}

// Pseudo-random hash function (identique à tvnoise.glsl)
float hash(vec2 p) {
    p = fract(p * vec2(443.8975, 397.2973));
    p += dot(p, p.yx + 19.19);
    return fract(p.x * p.y);
}

// Smooth noise based on hash (identique à tvnoise.glsl)
float noise(vec2 uv) {
    vec2 i = floor(uv);
    vec2 f = fract(uv);
    f = f * f * (3.0 - 2.0 * f);

    float a = hash(i);
    float b = hash(i + vec2(1.0, 0.0));
    float c = hash(i + vec2(0.0, 1.0));
    float d = hash(i + vec2(1.0, 1.0));

    return mix(mix(a, b, f.x), mix(c, d, f.x), f.y);
}

// Remplace la texture de bruit "util/noise" de Wallpaper Engine.
// 256.0 = fréquence équivalente à la texture 256x256 d'origine.
float noiseSample(vec2 uv) {
    uv *= 256.0;
    return noise(uv) * 0.65 + noise(uv * 2.13) * 0.35;
}

void main(void)
{
    // ── Valeurs par défaut de la scène quand l'uniform n'est pas configuré (0) ──
    float speed      = (raySpeed      == 0.0) ? 0.34 : raySpeed;
    vec2  shapeScale = (rayScale.x    == 0.0) ? vec2(0.69, 1.05) : rayScale;
    float smoothn    = (raySmoothness == 0.0) ? 0.6  : raySmoothness;
    vec2  feather    = (rayFeather.x  == 0.0 && rayFeather.y == 0.0) ? vec2(0.23, 0.07) : rayFeather;
    float radius     = (rayRadius     == 0.0) ? 0.1  : rayRadius;
    float nScale     = (noiseScale    == 0.0) ? 1.17 : noiseScale;
    float nAmount    = (noiseAmount   == 0.0) ? 0.33 : noiseAmount;
    float intensity  = (rayIntensity  == 0.0) ? 2.92 : rayIntensity;
    float exponent   = (rayExponent   == 0.0) ? 1.24 : rayExponent;
    vec4  cStart     = (colorStart.a  == 0.0) ? vec4(1.0, 1.0, 1.0, 1.0) : colorStart;
    vec4  cEnd       = (colorEnd.a    == 0.0) ? vec4(0.43529, 0.88627, 1.0, 1.0) : colorEnd;
    float aEnd       = (endAngle      == 0.0) ? 1.0  : endAngle;

    vec2 fxCoord = v_texfx.xy / v_texfx.z;

    vec4 albedo = (directDraw == 1) ? vec4(0.0) : COMPAT_TEXTURE(u_tex, hbFlipV(v_tex));

    float rayMask = step(0.0, v_texfx.z);
    vec2 fxCoordRef;

    if (rayMode == 0) {
        // ── Radial (mode de la scène d'origine) ──
        vec2 center = (rayCenter.x == 0.0 && rayCenter.y == 0.0) ? vec2(0.5, 0.5) : rayCenter;
        vec2 rayDelta = fxCoord - center;
        fxCoord.x = atan(rayDelta.y, rayDelta.x) / 6.283185 + 0.5;

        fxCoord.y = length(rayDelta) * 2.0;
        fxCoord.y = smoothstep(radius, 1.0, fxCoord.y);
        fxCoord.y = (fxCoord.y - 0.0001) * 1.00021;

        fxCoordRef = fxCoord;
        shapeScale.x *= 4.0;

        rayMask *= smoothstep(-0.00001 + startAngle, startAngle + feather.x, fxCoord.x);
        rayMask *= smoothstep(aEnd + 0.00001, aEnd - feather.x, fxCoord.x);
        rayMask *= smoothstep(0.50001, 0.5 - feather.y, abs(fxCoord.y - 0.5));
    } else if (rayMode == 2) {
        // ── Coin ──
        vec2 rayDelta = fxCoord;
        if (rayCorner == 1) {
            rayDelta.x = 1.0 - rayDelta.x;
        } else if (rayCorner == 2) {
            rayDelta.y = 1.0 - rayDelta.y;
        } else if (rayCorner == 3) {
            rayDelta = vec2(1.0) - rayDelta;
        }
        fxCoord.x = atan(rayDelta.y, rayDelta.x) / 6.283185 * 4.0;
        fxCoord.y = max(rayDelta.x, rayDelta.y);
        fxCoord.y += noiseSample(vec2(fxCoord.x * 0.054111 * nScale, 0.0)) * nAmount - (nAmount * 0.5);
        fxCoord.y = smoothstep(radius, 1.0, fxCoord.y);

        fxCoordRef = fxCoord;
        shapeScale.x *= 4.0;

        rayMask *= smoothstep(0.50001, 0.5 - feather.x, abs(fxCoord.x - 0.5));
        rayMask *= smoothstep(0.50001, 0.5 - feather.y, abs(fxCoord.y - 0.5));
    } else {
        // ── Linéaire ──
        fxCoordRef = fxCoord;
        rayMask *= smoothstep(0.50001, 0.5 - feather.x, abs(fxCoord.x - 0.5));
        rayMask *= smoothstep(0.50001, 0.5 - feather.y, abs(fxCoord.y - 0.5));
    }

    rayMask *= 1.0 - fxCoord.y;

    vec2 fxCoord2 = fxCoord;
    fxCoord  *= vec2(0.054111 * shapeScale.x, 0.003111 * shapeScale.y);
    fxCoord2 *= vec2(0.07333 * shapeScale.x, 0.005967111 * shapeScale.y);

    fxCoord  += shaftsTime * speed * vec2(0.003, 0.000375111);
    fxCoord2 -= shaftsTime * speed * vec2(0.0047111, 0.0007399);

    float fx = noiseSample(fxCoord) * noiseSample(fxCoord2);
    fx = pow(fx, exponent);
    fx = smoothstep((1.0 - smoothn) * 0.29999, 0.3 + smoothn * 0.7, fx);
    fx *= rayMask * zoneMask(v_tex);

    vec3 fxColor = mix(cStart.rgb, cEnd.rgb, fxCoordRef.y);

    // Blending additif (mode 31 de Wallpaper Engine, celui de la scène)
    albedo.rgb = albedo.rgb + fxColor * intensity * fx;
    albedo.a = max(albedo.a, fx);

    FragColor = albedo * v_col;
}

#endif
