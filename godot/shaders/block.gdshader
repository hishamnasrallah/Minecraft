// Blocks: the vertex colour carries light (r = sky, g = block light, b = face shade).
// daylight / sky_tint change with the time of day, so chunks never need rebuilding for it.
shader_type spatial;
render_mode unshaded, cull_back;

uniform sampler2D atlas : source_color, filter_nearest;
uniform float daylight = 1.0;
uniform vec3 sky_tint : source_color = vec3(1.0);
uniform float alpha_cut = 0.5;

varying vec4 light;

void vertex() {
	light = COLOR;
}

float curve(float level) { return pow(level, 1.6); }

void fragment() {
	vec4 tex = texture(atlas, UV);
	if (tex.a < alpha_cut) discard;
	vec3 sky = vec3(curve(light.r) * daylight) * sky_tint;
	vec3 lamp = vec3(curve(light.g)) * vec3(1.0, 0.86, 0.62);
	ALBEDO = tex.rgb * max(max(sky, lamp), vec3(0.12)) * light.b;   // a faint glow so caves are never pitch black
}
