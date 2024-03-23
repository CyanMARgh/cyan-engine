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

	shader_text := compile_shader_vf(VERT_TEXT_QUAD, FRAG_TEXT_QUAD);
	defer deinit(*shader_text);

	text_painter : Text_Painter;
	init_buffers(*text_painter, 1000);
	defer deinit(*text_painter);

	text_painter.font = load_font_gpu("./res/fonts/JBM_EL.ttf", CHARACTERS_LIST_DEFAULT, CHARACTERS_LIST_RUSSIAN);
	defer deinit(*text_painter.font);

	TEXT :: "Купил мужик шляпу, а она ему как раз.";

	// measured_size := measure_text(text_painter.font, TEXT);

	base_length := measure_line(text_painter.font, TEXT);

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

		// write_line_in_rect(*text_painter, TEXT, .{.{0, 0}, .{800, 100}}, .{1, 1, 1}, 0);
		write_line_from_corner(*text_painter, TEXT, .{0, 0}, backend_state.window_metrics.width / base_length * text_painter.font.max_char_height, .{1, 1, 1}, 0);
		// start_and_append_text(*text_painter, TEXT, backend_state.window_metrics.width / measured_size.x);

		use(*shader_text);
			draw_simple(*text_painter);
		check_gl_error();
	}
}


