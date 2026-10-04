// HyperBat Raindrops — port clean-room de "Raindrops on the glass" (WE 3706822104),
// d'apres la technique procedurale "Heartfelt" (gouttes + trainees + verre depoli).
// Tout est procedural (hash, pas de texture de bruit). Anime via uTime.
// L'intensite (rainAmount) module refraction + flou + buee : a 0 => image nette.
// ⚠ pas de mots reserves ES 3.00.
//   rainAmount  : intensite globale (maitre, 0 = off)
//   rainSpeed   : vitesse de chute
//   dropDensity : densite des gouttes qui ruissellent
//   rainBlur    : flou du verre depoli
//   rainRefract : force de refraction des gouttes
//   rainFog     : voile / buee
//   rainFogColor: teinte de la buee

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

uniform COMPAT_PRECISION float rainAmount;
uniform COMPAT_PRECISION float rainAngle;   // sens d'ecoulement (radians) : 0 = vers le bas
uniform COMPAT_PRECISION float rainSpeed;
uniform COMPAT_PRECISION float dropDensity;
uniform COMPAT_PRECISION float rainBlur;
uniform COMPAT_PRECISION float rainRefract;
uniform COMPAT_PRECISION float rainFog;
uniform COMPAT_PRECISION vec4  rainFogColor;

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

vec3 N13(float p) {
    vec3 p3 = fract(vec3(p) * vec3(0.1031, 0.11369, 0.13787));
    p3 += dot(p3, p3.yzx + 19.19);
    return fract(vec3((p3.x + p3.y) * p3.z, (p3.x + p3.z) * p3.y, (p3.y + p3.z) * p3.x));
}
float Nf(float t) { return fract(sin(t * 12345.564) * 7658.76); }
float Saw(float b, float t) { return smoothstep(0.0, b, t) * smoothstep(1.0, b, t); }

// une couche de gouttes qui ruissellent : renvoie (masque, trainee)
vec2 DropLayer(vec2 uv, float t) {
    vec2 UV = uv;
    uv.y += t * 0.75;
    vec2 a = vec2(6.0, 1.0);
    vec2 grid = a * 2.0;
    vec2 id = floor(uv * grid);
    float colShift = Nf(id.x);
    uv.y += colShift;
    id = floor(uv * grid);
    vec3 n = N13(id.x * 35.2 + id.y * 2376.1);
    vec2 st = fract(uv * grid) - vec2(0.5, 0.0);
    float x = n.x - 0.5;
    float y = UV.y * 20.0;
    float wiggle = sin(y + sin(y));
    x += wiggle * (0.5 - abs(x)) * (n.z - 0.5);
    x *= 0.7;
    float ti = fract(t + n.z);
    y = (Saw(0.85, ti) - 0.5) * 0.9 + 0.5;
    vec2 p = vec2(x, y);
    float d = length((st - p) * a.yx);
    float mainDrop = smoothstep(0.4, 0.0, d);
    float r = sqrt(smoothstep(1.0, y, st.y));
    float cd = abs(st.x - x);
    float trail = smoothstep(0.23 * r, 0.15 * r * r, cd);
    float trailFront = smoothstep(-0.02, 0.02, st.y - y);
    trail *= trailFront * r * r;
    y = fract(UV.y * 10.0) + (st.y - 0.5);
    float dd = length(st - vec2(x, y));
    float droplets = smoothstep(0.3, 0.0, dd);
    float m = mainDrop + droplets * r * trailFront;
    return vec2(m, trail);
}

float StaticDrops(vec2 uv, float t) {
    uv *= 40.0;
    vec2 id = floor(uv);
    uv = fract(uv) - 0.5;
    vec3 n = N13(id.x * 107.45 + id.y * 3543.654);
    vec2 p = (n.xy - 0.5) * 0.7;
    float d = length(uv - p);
    float fade = Saw(0.025, fract(t + n.z));
    return smoothstep(0.3, 0.0, d) * fract(n.z * 10.0) * fade;
}

vec2 Drops(vec2 uv, float t, float density) {
    float s = StaticDrops(uv, t) * 0.6;
    vec2 m1 = DropLayer(uv, t) * density;
    vec2 m2 = DropLayer(uv * 1.85, t) * density * 0.85;
    float c = s + m1.x + m2.x;
    c = smoothstep(0.3, 1.0, c);
    return vec2(c, max(m1.y, m2.y));
}

void main(void) {
    vec4 src = COMPAT_TEXTURE(u_tex, hbFlipV(v_tex));
    vec3 base = src.rgb;
    float amt = clamp(rainAmount, 0.0, 1.0);
    vec2 res = (textureSize.x > 0.0 && textureSize.y > 0.0) ? textureSize : vec2(1.0, 1.0);
    float aspect = res.x / max(res.y, 1.0);

    float spd = (rainSpeed == 0.0) ? 0.25 : rainSpeed;
    float dens = (dropDensity == 0.0) ? 1.0 : dropDensity;
    float T = uTime * spd;

    // espace gouttes, corrige par l'aspect pour des gouttes rondes
    vec2 guv = vec2(v_tex.x * aspect, v_tex.y);
    // sens de la pluie : on tourne le champ. fAxis = axe d'ecoulement (gravite),
    // a 0 il pointe vers le bas de l'ecran (compense le flip vertical du pipeline).
    vec2 fAxis = vec2(sin(rainAngle), -cos(rainAngle));
    vec2 pAxis = vec2(cos(rainAngle), sin(rainAngle));
    vec2 ruv = vec2(dot(guv, pAxis), dot(guv, fAxis));

    vec2 c = Drops(ruv, T, dens);
    // normale de la surface (gradient du masque) dans l'espace tourne -> refraction
    vec2 e = vec2(0.0015, 0.0);
    float cx = Drops(ruv + e, T, dens).x;
    float cy = Drops(ruv + e.yx, T, dens).x;
    vec2 nrm = vec2(cx - c.x, cy - c.x);
    // reprojette la normale dans l'espace ecran
    vec2 screenN = nrm.x * pAxis + nrm.y * fAxis;

    float refr = (rainRefract == 0.0) ? 1.0 : rainRefract;
    vec2 ofs = screenN * refr * 0.6 * amt;

    // verre depoli : flou la ou il n'y a PAS de goutte (les gouttes restent nettes)
    float dropMask = clamp(c.x + c.y, 0.0, 1.0);
    float baseBlur = (rainBlur == 0.0) ? 0.004 : (rainBlur * 0.01);
    float blurR = baseBlur * (1.0 - dropMask * 0.92) * amt;
    vec2 q = v_tex + ofs;
    vec3 col = COMPAT_TEXTURE(u_tex, hbFlipV(q)).rgb;
    col += COMPAT_TEXTURE(u_tex, hbFlipV(q + vec2(blurR, blurR))).rgb;
    col += COMPAT_TEXTURE(u_tex, hbFlipV(q + vec2(-blurR, blurR))).rgb;
    col += COMPAT_TEXTURE(u_tex, hbFlipV(q + vec2(blurR, -blurR))).rgb;
    col += COMPAT_TEXTURE(u_tex, hbFlipV(q + vec2(-blurR, -blurR))).rgb;
    col /= 5.0;

    // voile / buee + petit eclat sur les gouttes
    float fogAmt = (rainFog == 0.0) ? 0.0 : rainFog;
    col = mix(col, rainFogColor.rgb, fogAmt * (1.0 - dropMask) * amt);
    col += dropMask * 0.05 * amt;

    col = mix(base, col, zoneMask(v_tex));
    FragColor = vec4(col, src.a) * v_col;
}
#endif
