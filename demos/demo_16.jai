#import,dir "../core";
// #load "../core/module.jai";
#import "Basic"()(MEMORY_DEBUGGER = true);
#import "Math";
#import "GL";

main :: () {
	defer report_memory_leaks();
	init_resources(); defer deinit_resources();
	init_default_graphics(); defer deinit_default_graphics();
	init_ui(); defer deinit_ui();

	fval := 0.;
	for window_cycle(fps_log_period = 200) {
		for Events {
			if it.type == {
				case .KEY; using it.key_event;
				if type == .PRESS ifx keycode == {
					case GLFW_KEY_ESCAPE; exit();
					case #char"P"; screenshot();
				}
			}
		}
		update_default_camera();
		clear_target_v4(GL_COLOR_BUFFER_BIT | GL_DEPTH_BUFFER_BIT, hex2f4(0x1a1b1c));

		ui_begin();
			if button("button #1") print("button #1\n");
			if button("second button") print("button #2\n");
			float_range(*fval, 0, 2, "%");

			// if button_base(.{.{5, 5}, .{200, 50}}, "button #1") print("button #1\n");
			// if button_base(.{.{5, 5}, .{100, 50}}, "btn2") print("button #2\n");
		ui_end();
	}	
}