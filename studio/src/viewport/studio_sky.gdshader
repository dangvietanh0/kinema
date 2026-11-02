shader_type sky;

// Procedural studio environment. The gradient is achromatic and intentionally
// lifted so the stage reads as a lit room rather than a black void. The only
// sun is Godot's real sky light: LIGHT0_* follows the DirectionalLight3D that
// owns SKY_MODE_LIGHT_AND_SKY, so the disc moves with the key light and
// disappears when no directional light contributes to the sky. The colour
// values below are linear, matching the Environment energy scale.

uniform vec3 zenith_color = vec3(0.10, 0.10, 0.10);
uniform vec3 horizon_color = vec3(0.26, 0.26, 0.26);
uniform vec3 ground_color = vec3(0.04, 0.04, 0.04);
uniform vec3 glow_color = vec3(0.34, 0.34, 0.34);
uniform float glow_strength = 0.30;
uniform float disc_brightness = 2.2;
uniform float halo_gain = 0.10;
uniform float halo_angle = 0.18;

void sky() {
	float height = EYEDIR.y;
	vec3 color = mix(horizon_color, zenith_color, smoothstep(0.0, 0.72, height));
	color = mix(ground_color, color, smoothstep(-0.30, 0.015, height));

	// A soft pool of light behind the working area adds depth without acting
	// as a second sun.
	float facing = max(0.0, 1.0 - length(EYEDIR.xz));
	color += glow_color * pow(facing, 3.0) * glow_strength;

	if (LIGHT0_ENABLED) {
		float angle = acos(clamp(dot(EYEDIR, LIGHT0_DIRECTION), -1.0, 1.0));
		float disc_radius = max(LIGHT0_SIZE, 0.030);
		vec3 disc_color = LIGHT0_COLOR * LIGHT0_ENERGY * disc_brightness;

		// The visible sun core. The radius is clamped so the disc stays
		// legible when the light's shadow-softening angle is small.
		float core = 1.0 - smoothstep(disc_radius * 0.55, disc_radius, angle);
		color += disc_color * core;

		// A wide, low-brightness halo keeps the sun readable against the
		// lifted gradient without becoming a second light source.
		float halo = 1.0 - smoothstep(0.0, halo_angle, angle);
		color += disc_color * halo * halo_gain;
	}

	COLOR = color;
}
