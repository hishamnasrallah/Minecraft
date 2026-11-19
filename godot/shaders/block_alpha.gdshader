// See-through blocks: water (uniform opacity) and stained glass / ice (texture alpha).
shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_opaque;

uniform sampler2D atlas : source_color, filter_nearest;
uniform float daylight = 1.0;
uniform vec3 sky_tint : source_color = vec3(1.0);
uniform float opacity = 1.0;

varying vec4 light;

void vertex() {
	light = COLOR;
}

float curve(float level) { return pow(level, 1.6); }

void fragment() {
	vec4 tex = texture(atlas, UV);
	if (tex.a < 0.02) discard;
	vec3 sky = vec3(curve(light.r) * daylight) * sky_tint;
	vec3 lamp = vec3(curve(light.g)) * vec3(1.0, 0.86, 0.62);
	ALBEDO = tex.rgb * max(max(sky, lamp), vec3(0.17)) * light.b;   // a faint glow so caves are never pitch black
	ALPHA = tex.a * opacity;
}
