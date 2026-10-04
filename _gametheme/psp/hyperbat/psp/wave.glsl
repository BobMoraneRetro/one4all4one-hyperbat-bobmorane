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

void main(void)                                    
{                                                  
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

// Paramètres XML (facultatifs)
uniform float waveTime;         // Animation time (0 = pas de déformation)
uniform float waveIntensity;    // amplitude de l'onde
uniform float waveSpeed;        // vitesse de l'onde
uniform float waveFrequency;    // nombre de vagues sur l'image
uniform vec2 resolution;        // résolution écran

void main(void)                                    
{         
	vec2 uv = v_tex;

	// valeurs par défaut si non définies
	float intensity = (waveIntensity != 0.0) ? waveIntensity : 0.02;
	float speed     = (waveSpeed != 0.0)     ? waveSpeed     : 5.0;
	float frequency = (waveFrequency != 0.0) ? waveFrequency : 10.0;

	// interpolation douce pour transition vers zéro
	float t = clamp(waveTime, 0.0, 1.0);
	t = sin(t * 1.57079632679); // easing sin(t * pi/2)

	if(t > 0.0){
		uv.y += t * intensity * sin(uv.x * frequency + waveTime * speed);
	}

	FragColor = COMPAT_TEXTURE(u_tex, uv);
}

#endif
