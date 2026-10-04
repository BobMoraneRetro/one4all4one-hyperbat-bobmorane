// HyperBat Light Pillar — port clean-room de "Ethereal Light Pillar" (WE 3647838840).
// Le shader d'origine est un raymarch 100 iterations (injouable en theme) : ici
// version procedurale 2D = faisceau vertical lumineux, degrade + scintillement,
// fondu en "ecran" (screen) sur l'image. ⚠ pas de mots reserves ES 3.00.
//   pillarIntensity : intensite globale (maitre, 0 = off)
//   pillarCenter    : position du faisceau (vec2 UV, X surtout)
//   pillarWidth     : largeur du faisceau
//   pillarColor     : couleur de la lumiere
//   pillarSoftness  : douceur des bords + degrade vertical
//   pillarSpeed     : vitesse du scintillement

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
uniform mat4 MVPMatrix;
COMPAT_ATTRIBUTE vec2 VertexCoord;
COMPAT_ATTRIBUTE vec2 TexCoord;
COMPAT_ATTRIBUTE vec4 COLOR;
COMPAT_VARYING vec2 v_tex;
COMPAT_VARYING vec4 v_col;
void main(void) {
    v_tex = vec2(TexCoord.x, 1.0 - TexCoord.y);
    gl_Position = MVPMatrix * vec4(VertexCoord.xy, 0.0, 1.0);
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
uniform sampler2D u_tex;
uniform COMPAT_PRECISION vec2 textureSize;
uniform COMPAT_PRECISION float uTime;
vec2 hbFlipV(vec2 p) { return vec2(p.x, 1.0 - p.y); }

uniform COMPAT_PRECISION float pillarIntensity;
uniform COMPAT_PRECISION vec2  pillarCenter;
uniform COMPAT_PRECISION float pillarWidth;
uniform COMPAT_PRECISION vec4  pillarColor;
uniform COMPAT_PRECISION float pillarSoftness;
uniform COMPAT_PRECISION float pillarSpeed;
uniform int pillarFullArea;   // 1 = le faisceau s'affiche aussi sur la transparence du calque

float hash21(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
float vnoise(vec2 p) {
    vec2 i = floor(p); vec2 f = fract(p);
    f = f * f * (3.0 - 2.0 * f);
    float a = hash21(i), b = hash21(i + vec2(1.0, 0.0));
    float c = hash21(i + vec2(0.0, 1.0)), d = hash21(i + vec2(1.0, 1.0));
    return mix(mix(a, b, f.x), mix(c, d, f.x), f.y);
}

void main(void) {
    vec4 src = COMPAT_TEXTURE(u_tex, hbFlipV(v_tex));
    vec3 base = src.rgb;
    float amt = clamp(pillarIntensity, 0.0, 1.0);
    vec2 center = (pillarCenter.x == 0.0 && pillarCenter.y == 0.0) ? vec2(0.5, 0.5) : pillarCenter;
    float width = (pillarWidth == 0.0) ? 0.12 : pillarWidth;
    float soft = (pillarSoftness == 0.0) ? 0.5 : pillarSoftness;
    float spd = (pillarSpeed == 0.0) ? 1.0 : pillarSpeed;
    vec2 res = (textureSize.x > 0.0 && textureSize.y > 0.0) ? textureSize : vec2(1.0, 1.0);
    float aspect = res.x / max(res.y, 1.0);

    // distance horizontale au faisceau (aspect-correct), profil gaussien
    float dx = (v_tex.x - center.x) * aspect;
    // leger evasement vertical + ondulation du faisceau
    float sway = (vnoise(vec2(v_tex.y * 4.0, uTime * spd * 0.5)) - 0.5) * width * 0.6;
    float beam = exp(-pow(abs(dx - sway) / max(width, 1e-3), 2.0));

    // degrade vertical : plus lumineux vers le centre, fondu haut/bas selon douceur
    float vgrad = smoothstep(0.0, soft, v_tex.y) * smoothstep(1.0, 1.0 - soft, v_tex.y);
    vgrad = mix(1.0, vgrad, clamp(soft, 0.0, 1.0));

    // scintillement vertical
    float shimmer = 0.75 + 0.25 * vnoise(vec2(v_tex.y * 10.0, uTime * spd));

    float glow = beam * vgrad * shimmer * amt * pillarColor.a;
    vec3 light = pillarColor.rgb * glow;
    // fondu "ecran" : ajoute de la lumiere sans cramer
    vec3 col = 1.0 - (1.0 - base) * (1.0 - light);
    // Option : faisceau visible AUSSI sur la transparence du calque (sinon colle au PNG).
    float outA = (pillarFullArea == 1) ? max(src.a, clamp(glow, 0.0, 1.0)) : src.a;
    FragColor = vec4(col, outA) * v_col;
}
#endif
