// HyperBat Clouds — port clean-room de "Cloud March" (WE 3655189537).
// L'original raymarche un volume fbm (trop lourd en theme) : ici nuages fbm 2D
// qui defilent, melanges sur l'image. Anime via uTime. ⚠ pas de mots reserves ES 3.00.
//   cloudAmount   : densite / opacite (maitre, 0 = off)
//   cloudScale    : echelle des nuages
//   cloudColor    : couleur des nuages
//   cloudSpeed    : vitesse de defilement
//   cloudCover    : couverture (seuil)
//   cloudSoftness : douceur des bords

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

uniform COMPAT_PRECISION float cloudAmount;
uniform COMPAT_PRECISION float cloudScale;
uniform COMPAT_PRECISION vec4  cloudColor;
uniform COMPAT_PRECISION float cloudSpeed;
uniform COMPAT_PRECISION float cloudCover;
uniform COMPAT_PRECISION float cloudSoftness;
uniform int cloudFullArea;   // 1 = les nuages s'affichent aussi sur la transparence du calque

uniform int maskMode;
uniform COMPAT_PRECISION vec2  maskCenter;
uniform COMPAT_PRECISION vec2  maskSize;
uniform COMPAT_PRECISION float maskSoftness;
uniform int maskInvert;
float zoneMask(vec2 uv) {
    if (maskMode == 0) return 1.0;
    vec2 size = (maskSize.x == 0.0 && maskSize.y == 0.0) ? vec2(0.5, 0.5) : maskSize;
    vec2 d = abs(uv - maskCenter) / max(size * 0.5, vec2(1e-5));
    float dist = (maskMode == 2) ? length(d) : max(d.x, d.y);
    float soft = max(maskSoftness, 1e-4);
    float m = 1.0 - smoothstep(1.0 - soft, 1.0 + soft, dist);
    return (maskInvert == 1) ? 1.0 - m : m;
}

float hash21(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
float vnoise(vec2 p) {
    vec2 i = floor(p); vec2 f = fract(p);
    f = f * f * (3.0 - 2.0 * f);
    float a = hash21(i), b = hash21(i + vec2(1.0, 0.0));
    float c = hash21(i + vec2(0.0, 1.0)), d = hash21(i + vec2(1.0, 1.0));
    return mix(mix(a, b, f.x), mix(c, d, f.x), f.y);
}
float fbm(vec2 p) {
    float v = 0.0;
    float amp = 0.5;
    mat2 rot = mat2(0.8, 0.6, -0.6, 0.8);
    for (int i = 0; i < 5; i++) {
        v += amp * vnoise(p);
        p = rot * p * 2.0;
        amp *= 0.5;
    }
    return v;
}

void main(void) {
    vec4 src = COMPAT_TEXTURE(u_tex, hbFlipV(v_tex));
    vec3 base = src.rgb;
    float amt = clamp(cloudAmount, 0.0, 1.0);
    float scl = (cloudScale == 0.0) ? 3.0 : cloudScale;
    float spd = (cloudSpeed == 0.0) ? 0.05 : cloudSpeed;
    float cover = (cloudCover == 0.0) ? 0.5 : cloudCover;
    float soft = (cloudSoftness == 0.0) ? 0.35 : cloudSoftness;
    vec2 res = (textureSize.x > 0.0 && textureSize.y > 0.0) ? textureSize : vec2(1.0, 1.0);
    float aspect = res.x / max(res.y, 1.0);

    vec2 uv = vec2(v_tex.x * aspect, v_tex.y) * scl;
    uv += vec2(uTime * spd, uTime * spd * 0.3);
    // deux octaves de fbm decalees -> nuages bombes
    float n = fbm(uv + fbm(uv * 0.5 + vec2(uTime * spd * 0.5, 0.0)));
    float cloud = smoothstep(cover - soft, cover + soft, n);

    float a = cloud * amt * cloudColor.a * zoneMask(v_tex);
    vec3 col = mix(base, cloudColor.rgb, a);
    // Option : afficher les nuages aussi sur la transparence du calque (sinon colles au PNG).
    float outA = (cloudFullArea == 1) ? max(src.a, clamp(a, 0.0, 1.0)) : src.a;
    FragColor = vec4(col, outA) * v_col;
}
#endif
