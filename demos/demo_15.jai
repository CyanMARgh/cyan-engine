#import,dir "../core";
#import "Basic"()(MEMORY_DEBUGGER = true);
#import "Math";
#import "GL";
#import "Random";
#import "Hash_Table";
#import "File";
#import "Sort";

main :: () {
	defer report_memory_leaks();
	init_resources(.{1200, 800}	); defer deinit_resources();
	init_default_graphics(); defer deinit_default_graphics();

	image := load_image("./res/input_texture.png", 4);
	defer deinit(*image);

	texture := load_texture_from_image(image);
	defer deinit(*texture);

	fb_canvas := make_framebuffer(1280, 720,
		.{"color", .COLOR, GL_RGB, GL_RGB, GL_UNSIGNED_BYTE}
	);
	defer deinit(*fb_canvas);

	shader_text := compile_shader_vf(VERT_TEXT_QUAD_CUSTOM, FRAG_TEXT_QUAD);
	defer deinit(*shader_text);
	shader_show_texture := compile_shader_vf(incldefs("NOFLIP", VERT_SCREEN_QUAD), FRAG_SHOW_TEXTURE);
	defer deinit(*shader_show_texture);

	text_painter : Custom_Text_Painter;

	text_painter.font = load_font_gpu("./res/fonts/JBM_EL.ttf", CHARACTERS_LIST_DEFAULT, CHARACTERS_LIST_RUSSIAN);
	defer deinit(*text_painter.font);
	text_painter.painter = make_atoms_painter(Character_GPU, 1000000);
	defer deinit(*text_painter.painter);

	commit_buffer(*text_painter.painter);

	add_char_at :: (px : s32, py : s32) #expand {
		using backend_state;
		if px >= 0 && py >= 0 && px < window_metrics.width && py < window_metrics.height {
			color := at(image, px, py);
			// print("\e[48;2;%;%;%m     \e[0m\n", color & 0xff, (color >> 8) & 0xff, (color >> 16) & 0xff);
			N := text_painter.painter.buffer.count;
			add_codepoint(*text_painter, 
				xx(random_get() % (#char"Z" - #char"A") + #char"A"), 
				.{xx px, xx py}, 
				.{
					xx(color & 0xff), 
					xx((color >> 8) & 0xff), 
					xx ((color >> 16) & 0xff)
				} / 255., 
				50. * pow(2, random_get_within_range(0., 3.)) / (1. + .03 * sqrt(cast(float) N)), 
				random_get_within_range(0, 2 * PI)
			);
			commit_buffer(*text_painter.painter);
		}
	}

	for window_cycle() {
		for Events if it.type == {
			case .KEY; using it.key_event;
			if type == .PRESS ifx keycode == {
				case GLFW_KEY_ESCAPE; exit();
				case #char"P"; screenshot();
				case #char"C";
				using backend_state;
				cpx, cpy :s32= xx cursor_position.x, xx cursor_position.y;
				add_char_at(cpx, cpy);
			}
		}

		update_default_camera();
		clear_target(GL_COLOR_BUFFER_BIT | GL_DEPTH_BUFFER_BIT, .[1, 1, 1, 1]);
		for 1..30 add_char_at(xx(random_get() % 1200), xx(random_get() % 800));

		glEnable(GL_BLEND);
		glBlendFunc(GL_SRC_ALPHA, GL_ONE_MINUS_SRC_ALPHA);

		// use(*shader_show_texture);
		// 	bind_sampler(0, texture);
		// 	draw_empty_mesh(6);
		bind_as_target(fb_canvas);
			use(*shader_text);
				bind_sampler(0, text_painter.font.atlas);
				draw(*text_painter.painter, 6);
		bind_default_target();
			use(*shader_show_texture);
			bind_sampler(0, fb_canvas.textures[0]);
			draw_empty_mesh(6);
		check_gl_error();
	}
}

Character_GPU :: struct {
	left_bottom : Vector2;
	right_top : Vector2;
	size : Vector2; 
	layer : u32;
	color : Vector3;
	angle : float = 0.;
}
Custom_Text_Painter :: struct {
	painter : Atoms_Painter(Character_GPU);
	font : Font;
}

draw_simple :: (using text_painter : *Custom_Text_Painter) {
	bind_sampler(0, font.atlas);
	draw_simple(*painter, 6);
}

add_codepoint :: (using text_painter : *Custom_Text_Painter, codepoint : u32, center : Vector2, color := Vector3.{1, 1, 1}, size := 50., angle := 0.) {
	if codepoint == #char"\n" return;
	char, ok := table_find(*font.char_map, codepoint);
	if !ok return;

	canvas_scale := Vector2.{char.width / cast(float)font.max_bitmap_width, char.height / cast(float)font.max_bitmap_height};

	actual_size := size * Vector2.{xx char.width, xx char.height} / cast(float) font.line_height;

	left_top := center - actual_size * .5;
	right_bottom := center + actual_size * .5;

	left_bottom := Vector2.{left_top.x, right_bottom.y};
	right_top := Vector2.{right_bottom.x, left_top.y};

	push(*text_painter.painter, .{
		left_bottom,
		right_top,
		canvas_scale,
		char.id_in_bitmap,
		color,
		angle
	});
}

VERT_TEXT_QUAD_CUSTOM :: #run incl(UBO_SCREEN_METRICS, UBO_TIME_INFO, #string GLSL
	layout (location = 0) in vec2 a_left_bottom;
	layout (location = 1) in vec2 a_right_top;
	layout (location = 2) in vec2 a_size;
	layout (location = 3) in uint a_layer;
	layout (location = 4) in vec3 a_color;
	layout (location = 5) in float a_angle;

	out vec2 vo_uv;
	out vec3 vo_color;
	flat out uint vo_layer;

	vec2 transform_canvas_to_gl(vec2 p) {
		p /= vec2(u_window_size);
		return vec2(2 * p.x - 1, 1 - 2 * p.y);
	}
	float to_depth(float z) {
		const float zFar = 100, zNear = .1; 
		return -(zFar + zNear - (2.0 * zNear * zFar) / z) / (zFar - zNear);
	}

	void main() {
		float depth = to_depth(float(gl_VertexID % 6) * .0001 + .1);

		float points[12] = float[12](0, 0, 1, 1, 0, 1, 0, 0, 1, 0, 1, 1);
		vec2 p = vec2(points[gl_VertexID << 1], points[(gl_VertexID << 1) | 1]);

		vec2 left_bottom = a_left_bottom;
		vec2 right_top = a_right_top;

		vec2 C = (left_bottom + right_top) / 2;
		vec2 R = (right_top - left_bottom) / 2;

		// float angle = u_time;
		float angle = a_angle;
		vec2 csa = vec2(cos(angle), sin(angle));
		vec2 P = C + ((p * 2 - 1) * R) * mat2(csa.x, csa.y, -csa.y, csa.x);


		gl_Position = vec4(transform_canvas_to_gl(P), depth, 1);
		vec2 uv = p;
		uv.y = 1 - uv.y;
		uv *= a_size;

		vo_uv = uv;
		vo_color = a_color;
		vo_layer = a_layer;
	}
GLSL);
FRAG_SHOW_TEXTURE :: #string GLSL
	layout(binding = 0) uniform sampler2D u_color;
	in vec2 vo_uv;
	out vec4 o_color;
	void main() {
		o_color = texture(u_color, vo_uv);
	}
GLSL;
