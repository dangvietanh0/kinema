shader_type sky;

// A quiet studio gradient instead of a photographed sky. The horizon is warm
// enough to separate a dark subject from the background, while the upper field
// stays neutral so material colours read honestly.

uniform vec3 zenith_color : source_color = vec3(0.085, 0.100, 0.125);
uniform vec3 horizon_color : source_color = vec3(0.190, 0.205, 0.230);
uniform vec3 ground_color : source_color = vec3(0.030, 0.036, 0.045);
uniform vec3 glow_color : source_color = vec3(0.260, 0.275, 0.305);
uniform float glow_strength = 0.35;

void sky() {
	float height = EYEDIR.y;
	vec3 color = mix(horizon_color, zenith_color, smoothstep(0.0, 0.72, height));
	color = mix(ground_color, color, smoothstep(-0.30, 0.015, height));
	// A soft pool of light behind the working area gives the silhouette depth
	// without adding a visible sun disc.
	float facing = max(0.0, 1.0 - length(EYEDIR.xz));
	color += glow_color * pow(facing, 3.0) * glow_strength;
	COLOR = color;
}
