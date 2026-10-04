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

void main(void)                                    
{                                                  
	gl_Position = MVPMatrix * vec4(VertexCoord.xy, 0.0, 1.0);
	v_tex       = TexCoord;                           
	v_col       = COLOR;                           
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
			
COMPAT_VARYING   vec4      v_col;
COMPAT_VARYING   vec2      v_tex;

uniform   sampler2D u_tex;
uniform   COMPAT_PRECISION vec2      resolution;
uniform   COMPAT_PRECISION vec2      textureSize;
uniform   COMPAT_PRECISION vec2      outputSize;

uniform   COMPAT_PRECISION float     radius;
uniform   COMPAT_PRECISION float     holeRadius;
uniform   COMPAT_PRECISION float     scaleX;
uniform   COMPAT_PRECISION float     scaleY;
uniform   COMPAT_PRECISION float     offsetX;
uniform   COMPAT_PRECISION float     offsetY;
uniform   COMPAT_PRECISION float     borderWidth;
uniform   COMPAT_PRECISION float     centerRingWidth;

vec4 sampleTexture(sampler2D tex, vec2 texCoord) 
{
    // Check if the texture coordinate is within the [0, 1] range
    if (texCoord.x >= 0.0 && texCoord.x <= 1.0 && texCoord.y >= 0.0 && texCoord.y <= 1.0)
        return COMPAT_TEXTURE(tex, texCoord);
    
    return vec4(0.0); // Return transparent black for coordinates outside [0, 1]    
}

void main(void)                                    
{         
	vec2 center = vec2(0.5, 0.5);
	
	// Get parameters with defaults
	float discRadius = radius;
	if (discRadius == 0.0) {
		discRadius = 0.48;
	}
	
	float hole = holeRadius;
	if (hole == 0.0) {
		hole = 0.08;
	}
	
	float borderSize = borderWidth;
	if (borderSize == 0.0) {
		borderSize = 0.04;
	}
	
	float centerRing = centerRingWidth;
	if (centerRing == 0.0) {
		centerRing = 0.06;
	}
	
	// Calculate aspect ratio to make a perfect circle
	float aspectRatio = 1.0;
	if (resolution.x > 0.0 && resolution.y > 0.0) {
		aspectRatio = resolution.x / resolution.y;
	} else if (outputSize.x > 0.0 && outputSize.y > 0.0) {
		aspectRatio = outputSize.x / outputSize.y;
	}
	
	// Adjust coordinates to compensate for aspect ratio
	vec2 p = v_tex - center;
	p.x *= aspectRatio;
	
	// Calculate distance from center
	float dist = length(p);
	
	// Discard pixels outside the disc
	if (dist > discRadius) {
		discard;
	}
	
	// Discard pixels inside the hole
	if (dist < hole) {
		discard;
	}
	
	// Get scale and offset parameters with defaults
	float texScaleX = scaleX;
	if (texScaleX == 0.0) {
		texScaleX = 1.0;
	}
	
	float texScaleY = scaleY;
	if (texScaleY == 0.0) {
		texScaleY = 1.0;
	}
	
	float texOffsetX = offsetX;
	float texOffsetY = offsetY;
	
	// Apply scale and offset to texture coordinates
	vec2 texCoord = v_tex;
	texCoord -= vec2(0.5, 0.5);
	texCoord /= vec2(texScaleX, texScaleY);
	texCoord += vec2(texOffsetX, texOffsetY);
	texCoord += vec2(0.5, 0.5);
	
	// Sample the texture
	vec4 color = sampleTexture(u_tex, texCoord);
	
	// Colors extracted from real CD image
	vec3 centerGrey = vec3(113.0/255.0, 113.0/255.0, 113.0/255.0);  // Dark grey center ring
	vec3 borderGrey = vec3(191.0/255.0, 193.0/255.0, 206.0/255.0);  // Light grey-blue border
	
	// === CENTER RING (grey plastic around the hole) ===
	float centerRingOuter = hole + centerRing;
	if (dist <= centerRingOuter) {
		// Smooth transition to center ring color
		float centerBlend = smoothstep(centerRingOuter - 0.01, centerRingOuter, dist);
		color.rgb = mix(centerGrey, color.rgb, centerBlend);
	}
	
	// === OUTER BORDER (light grey metallic edge) ===
	float borderStart = discRadius - borderSize;
	if (dist >= borderStart) {
		// Smooth transition to border color
		float borderBlend = smoothstep(borderStart, borderStart + 0.01, dist);
		color.rgb = mix(color.rgb, borderGrey, borderBlend);
	}
	
	// Apply vertex color
	FragColor = color * v_col;
}
#endif