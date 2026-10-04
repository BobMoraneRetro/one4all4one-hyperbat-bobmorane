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
COMPAT_VARYING vec2 v_pos;

void main(void)
{
	gl_Position = MVPMatrix * vec4(VertexCoord.xy, 0.0, 1.0);
	v_tex = TexCoord;
	v_col = COLOR;
	v_pos = VertexCoord;
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

COMPAT_VARYING vec4 v_col;
COMPAT_VARYING vec2 v_tex;
COMPAT_VARYING vec2 v_pos;

uniform sampler2D u_tex;
uniform vec2 textureSize;
uniform vec2 outputSize;
uniform vec2 outputOffset;

uniform float borderSize;
uniform vec4  borderColor;
uniform float cornerRadius;
uniform float innerShadowSize;
uniform vec4  innerShadowColor;
uniform float outerShadowSize;
uniform vec4  outerShadowColor;
uniform float saturation;
uniform bool  bilinearFiltering;
uniform float aaFactor; // 1.0 à 17 ou plus si nécessaire

// --- Fonctions utilitaires ---
vec4 sampleTexture(sampler2D tex, vec2 texCoord)
{
    return COMPAT_TEXTURE(tex, texCoord);
}

float getComputedValue(float value, float defaultValue)
{
    if (value == 0.0) return defaultValue;
    if (value < 1.0)  return abs(outputSize.y) * value;
    return value;
}

void main(void)
{
	// --- Paramètres ---
	float outerBorder = getComputedValue(borderSize, 0.0);
	float innerShadow = getComputedValue(innerShadowSize, 0.0);
	float outerShadow = getComputedValue(outerShadowSize, 0.0);
	float cornerSize  = getComputedValue(cornerRadius, 0.0);

	// --- UV ajusté pour border ---
	vec2 decal = vec2(
		(outerBorder/2.0 + outerShadow) / max(1.0, abs(outputSize.x)),
		(outerBorder/2.0 + outerShadow) / max(1.0, abs(outputSize.y))
	);
	vec2 v_padtex = vec2(
		v_tex.x / max(0.0001, (1.0 - 2.0 * decal.x)) - decal.x,
		v_tex.y / max(0.0001, (1.0 - 2.0 * decal.y)) - decal.y
	);
	v_padtex = clamp(v_padtex, vec2(0.0), vec2(1.0));

	vec4 sampledColor = sampleTexture(u_tex, v_padtex);

	// --- Bilinear filtering ---
	if (bilinearFiltering)
	{
		vec2 texelSize = 1.0 / textureSize;
		vec2 f = fract(v_padtex * textureSize);
		vec2 base = (floor(v_padtex * textureSize)) / textureSize;

		vec4 c00 = sampleTexture(u_tex, base);
		vec4 c10 = sampleTexture(u_tex, base + vec2(texelSize.x, 0.0));
		vec4 c01 = sampleTexture(u_tex, base + vec2(0.0, texelSize.y));
		vec4 c11 = sampleTexture(u_tex, base + texelSize);

		sampledColor = mix(mix(c00, c10, f.x), mix(c01, c11, f.x), f.y);
	}

	// --- Saturation ---
	if (saturation != 1.0)
	{
		vec3 gray = vec3(dot(sampledColor.rgb, vec3(0.34, 0.55, 0.11)));
		sampledColor.rgb = mix(gray, sampledColor.rgb, saturation);
	}

	sampledColor *= v_col;

	// --- Vérification alpha PNG ---
	if (sampledColor.a < 0.01)
	{
		FragColor = sampledColor; 
		return; // Pas de bordure ni d’ombre
	}

	// --- Coin arrondi ---
	vec2 middle = vec2(abs(outputSize.x), abs(outputSize.y)) / 2.0;
	vec2 center = abs(v_pos - outputOffset - middle);
	vec2 q = center - middle + cornerSize;
	float distance = length(max(q, 0.0)) + min(max(q.x, q.y), 0.0) - cornerSize;

	// --- Anti-aliasing bord (AA simple comme avant) ---
	float aa = fwidth(distance) * (aaFactor > 0.0 ? aaFactor : 1.5);
	float alphaEdge = smoothstep(0.0, aa, -distance);

	vec4 outColor = sampledColor;

	// --- Bordures et ombres uniquement sur pixels opaques ---
	if (distance > -(outerBorder + innerShadow + outerShadow))
	{
		if (outerShadow != 0.0 && distance > -outerShadow)
		{
			outColor = outerShadowColor;
			outColor.a = outerShadowColor.a * (1.0 - (outerShadow + distance) / outerShadow) * v_col.a * sampledColor.a;
		}
		else if (distance > -(outerBorder + outerShadow))
		{
			outColor = borderColor;
			outColor.a *= v_col.a * sampledColor.a;
		}
		else if (innerShadow != 0.0)
		{
			float val = abs(outerBorder + outerShadow + distance) / innerShadow;
			outColor = mix(outColor, innerShadowColor, innerShadowColor.a * (1.0 - val) * sampledColor.a);
		}
	}

	// --- Application du lissage sur le bord ---
	outColor.a *= alphaEdge;
	outColor.rgb *= alphaEdge;

	FragColor = outColor;
}

#endif
