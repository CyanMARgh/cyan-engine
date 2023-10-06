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
	init_resources(); defer deinit_resources();
	init_default_graphics(); defer deinit_default_graphics();

	shader_text := compile_shader_vf(SRC_VERT_TEXT_QUAD, SRC_FRAG_TEXT_QUAD);
	defer deinit(*shader_text);

	text_painter : Text_Painter;

	text_painter.font = load_font_gpu("./res/fonts/JBM_EL.ttf", CHARACTERS_LIST_DEFAULT, CHARACTERS_LIST_RUSSIAN);
	defer deinit(*text_painter.font);
	text_painter.painter = make_atoms_painter(Character_GPU, 1000);
	defer deinit(*text_painter.painter);

	TEXT :: "Купил мужик шляпу, а она ему как раз.";

	measured_size := measure_text(text_painter.font, TEXT);

	for window_cycle(fps_log_period = 100, print_statistical_fps = true) {
		for Events if it.type == {
			case .KEY; using it.key_event;
			if type == .PRESS ifx keycode == {
				case GLFW_KEY_ESCAPE; exit();
				case #char"P"; screenshot();
			}
		}
		update_default_camera();

		glClearColor(.7, .8, .9, 1);
		glClear(GL_COLOR_BUFFER_BIT | GL_DEPTH_BUFFER_BIT);

		glEnable(GL_BLEND);
		glBlendFunc(GL_SRC_ALPHA, GL_ONE_MINUS_SRC_ALPHA);

		// start_text(*text_painter, row_size = 50);
		// append_text(*text_painter, "Купил мужик ");
		// append_text(*text_painter, "шляпу", color = .{1, 0, 0});
		// append_text(*text_painter, ",\nа она ему как раз.");

		start_and_append_text(*text_painter, TEXT, backend_state.window_metrics.width / measured_size.x);

		use(*shader_text);
			draw_simple(*text_painter);
		check_gl_error();
	}
}

Character_GPU :: struct {
	a_left_bottom : Vector2;
	a_right_top : Vector2;
	a_size : Vector2; 
	a_layer : u32;
	color : Vector3;
}
Text_Painter :: struct {
	painter : Atoms_Painter(Character_GPU);
	font : Font;

	origin : Vector2;
	row_size := 50.;
}

measure_text :: (using font : Font, text : string) -> Vector2 {
	lines : s32;
	most_right : s32;
	origin_x : s32;
	process_codepoint :: (font : Font, codepoint : u32) #expand {
		if codepoint == #char"\n" {
			origin_x = 0;
			lines += 1;
			return;
		}
		char, ok := table_find(*font.char_map, codepoint);
		if !ok return;

		actual_size_x := char.width;
		offset_x := char.xoff;
		advance := char.advance;

		origin_x += advance;
		most_right = max(most_right, origin_x);
		// most_right = max(most_right, origin_x + offset_x + actual_size_x);
	}

	for codepoint : iterate(text) {
		process_codepoint(font, codepoint);
	}
	return .{most_right / cast(float) font.line_height, lines + 1.};
}

draw_simple :: (using text_painter : *Text_Painter) {
	bind_sampler(0, font.atlas);
	draw_simple(*painter, 6);
}

start_and_append_text :: (text_painter : *Text_Painter, text : string, row_size := 50., left_top := Vector2.{0, 0}, color := Vector3.{1, 1, 1}) {
	start_text(text_painter, row_size, left_top);
	append_text(text_painter, text, color);
}

start_text :: (text_painter : *Text_Painter, row_size := 50., left_top := Vector2.{0, 0}) {
	text_painter.origin = Vector2.{0, row_size} + left_top;
	text_painter.row_size = row_size;
}

append_text :: (using text_painter : *Text_Painter, text : string, color := Vector3.{1, 1, 1}) {
	append_codepoint :: (using text_painter : *Text_Painter, codepoint : u32, color : Vector3) {
		if codepoint == #char"\n" {
			origin.y += row_size;
			origin.x = 0;
			return;
		}
		char, ok := table_find(*font.char_map, codepoint);
		if !ok return;
		canvas_scale := Vector2.{char.width / cast(float)font.max_width, char.height / cast(float)font.max_height};

		actual_size := row_size * Vector2.{xx char.width, xx char.height} / cast(float) font.line_height;
		offset := row_size * Vector2.{xx char.xoff, xx char.yoff} / cast(float) font.line_height;
		advance := row_size * char.advance / cast(float) font.line_height;

		left_top := origin + offset;
		right_bottom := left_top + actual_size;

		left_bottom := Vector2.{left_top.x, right_bottom.y};
		right_top := Vector2.{right_bottom.x, left_top.y};

		push(*text_painter.painter, .{
			left_bottom,
			right_top,
			canvas_scale,
			char.id_in_bitmap,
			color
		});

		origin.x += advance;
	}

	for codepoint : iterate(text) {
		append_codepoint(text_painter, codepoint, color);
	}
}

SRC_VERT_TEXT_QUAD :: #run incl(UBO_SCREEN_METRICS, #string GLSL
	layout (location = 0) in vec2 a_left_bottom;
	layout (location = 1) in vec2 a_right_top;
	layout (location = 2) in vec2 a_size;
	layout (location = 3) in uint a_layer;
	layout (location = 4) in vec3 a_color;

	out vec2 vo_uv;
	out vec3 vo_color;
	flat out uint vo_layer;

	vec2 transform_canvas_to_gl(vec2 p) {
		p /= vec2(u_window_size);
		return vec2(2 * p.x - 1, 1 - 2 * p.y);
	}

	void main() {
		float points[12] = float[12](0, 0, 1, 1, 0, 1, 0, 0, 1, 0, 1, 1);
		vec2 p = vec2(points[gl_VertexID << 1], points[(gl_VertexID << 1) | 1]);
		vec2 left_bottom = transform_canvas_to_gl(a_left_bottom);
		vec2 right_top = transform_canvas_to_gl(a_right_top);
		gl_Position = vec4(left_bottom + p * (right_top - left_bottom), 0, 1);
		vec2 uv = p;
		uv.y = 1 - uv.y;
		uv *= a_size;

		vo_uv = uv;
		vo_color = a_color;
		vo_layer = a_layer;
	}
GLSL);
SRC_FRAG_TEXT_QUAD :: #run incl(UBO_TIME_INFO, #string GLSL
	layout (binding = 0) uniform sampler2DArray u_text_atlas;

	in vec2 vo_uv;
	in vec3 vo_color;
	flat in uint vo_layer;

	out vec4 o_color;
	void main() {
		float mapval = texture(u_text_atlas, vec3(vo_uv, float(vo_layer))).x;
		o_color = vec4(
			mix(vec3(0), vo_color, smoothstep(.49, .51, mapval)), 
			smoothstep(.44, .47, mapval)
		);
	}
GLSL);