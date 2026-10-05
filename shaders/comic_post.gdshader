// Full-screen comic print filter. Every world feeds its own ComicStyle into these
// uniforms, so each dimension reads like a different comic (ukiyo-e, noir, pop...).
shader_type canvas_item;
render_mode unshaded;

uniform sampler2D screen_tex : hint_screen_texture, filter_linear;

uniform vec4 paper_color : source_color = vec4(0.96, 0.93, 0.85, 1.0);
uniform vec4 ink_color : source_color = vec4(0.06, 0.05, 0.07, 1.0);
uniform vec4 accent_color : source_color = vec4(0.75, 0.1, 0.1, 1.0);
uniform float posterize_levels = 6.0;
uniform float halftone_strength = 0.4;
uniform float halftone_scale = 6.0;
uniform float halftone_angle = 0.785;
uniform float hatching = 0.0;
uniform float outline_strength = 1.0;
uniform float outline_threshold = 0.2;
uniform float misregistration = 0.0;
uniform float paper_grain = 0.2;
uniform float paper_tint = 0.5;
uniform float saturation = 1.0;
uniform float monochrome = 0.0;
uniform float accent_keep = 0.0;
// 0..1, driven by GameState hope: as hope fades, so does the colour of the world.
uniform float hope_desaturation = 0.0;
// 0..1 flash used for hits / reveals.
uniform float impact_flash = 0.0;

float luma(vec3 c) { return dot(c, vec3(0.299, 0.587, 0.114)); }

float hash(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }

vec3 sample_rgb(vec2 uv, vec2 px) {
	if (misregistration <= 0.0) {
		return texture(screen_tex, uv).rgb;
	}
	// Spider-Verse style off-register print plates.
	vec2 o = px * misregistration;
	float r = texture(screen_tex, uv + vec2(o.x, o.y * 0.5)).r;
	float g = texture(screen_tex, uv).g;
	float b = texture(screen_tex, uv - vec2(o.x * 0.5, o.y)).b;
	return vec3(r, g, b);
}

void fragment() {
	vec2 uv = SCREEN_UV;
	vec2 px = SCREEN_PIXEL_SIZE;
	vec2 p = uv / px;
	vec3 col = sample_rgb(uv, px);

	// Colour grading: saturation, monochrome, and the hope fade.
	float l = luma(col);
	vec3 accent_dir = normalize(accent_color.rgb + 0.001);
	float accent_match = smoothstep(0.85, 0.97, dot(normalize(col + 0.001), accent_dir)) * step(0.15, length(col));
	float mono = clamp(monochrome - accent_match * accent_keep, 0.0, 1.0);
	col = mix(vec3(l), col, saturation);
	col = mix(col, vec3(l), mono);
	col = mix(col, vec3(l) * vec3(0.92, 0.9, 1.0), hope_desaturation);

	// Flat printed colour.
	col = floor(col * posterize_levels + 0.5) / posterize_levels;

	// Halftone dots that grow in the shadows.
	float s = sin(halftone_angle);
	float c = cos(halftone_angle);
	vec2 rp = mat2(vec2(c, -s), vec2(s, c)) * p / halftone_scale;
	vec2 cell = fract(rp) - 0.5;
	float dark = 1.0 - luma(col);
	float radius = sqrt(dark) * 0.62;
	float dots = 1.0 - smoothstep(radius - 0.08, radius + 0.08, length(cell));
	col = mix(col, mix(col, ink_color.rgb, 0.65), dots * halftone_strength * smoothstep(0.1, 0.35, dark));

	// Cross-hatching in deep shadows.
	if (hatching > 0.0) {
		float h1 = step(0.82, fract((p.x + p.y) / halftone_scale));
		float h2 = step(0.82, fract((p.x - p.y) / halftone_scale));
		float hatch = max(h1 * step(0.55, dark), h2 * step(0.75, dark));
		col = mix(col, ink_color.rgb, hatch * hatching);
	}

	// Ink outlines from a Sobel pass on luminance.
	float tl = luma(texture(screen_tex, uv + px * vec2(-1.0, -1.0)).rgb);
	float t  = luma(texture(screen_tex, uv + px * vec2( 0.0, -1.0)).rgb);
	float tr = luma(texture(screen_tex, uv + px * vec2( 1.0, -1.0)).rgb);
	float ml = luma(texture(screen_tex, uv + px * vec2(-1.0,  0.0)).rgb);
	float mr = luma(texture(screen_tex, uv + px * vec2( 1.0,  0.0)).rgb);
	float bl = luma(texture(screen_tex, uv + px * vec2(-1.0,  1.0)).rgb);
	float b  = luma(texture(screen_tex, uv + px * vec2( 0.0,  1.0)).rgb);
	float br = luma(texture(screen_tex, uv + px * vec2( 1.0,  1.0)).rgb);
	float gx = -tl - 2.0 * ml - bl + tr + 2.0 * mr + br;
	float gy = -tl - 2.0 * t - tr + bl + 2.0 * b + br;
	float edge = smoothstep(outline_threshold, outline_threshold * 2.0, length(vec2(gx, gy)));
	col = mix(col, ink_color.rgb, clamp(edge * outline_strength, 0.0, 1.0));

	// Paper stock and grain.
	col = mix(col, col * paper_color.rgb * 1.06, paper_tint);
	col -= (hash(floor(p * 0.5)) - 0.5) * paper_grain * 0.18;

	col = mix(col, paper_color.rgb, impact_flash);
	COLOR = vec4(col, 1.0);
}
