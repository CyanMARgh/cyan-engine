#import,dir "../core";
#import "Basic"()(MEMORY_DEBUGGER = true);
#import "Math";
#import "GL";

main :: () {
	defer report_memory_leaks();
	init_resources(); defer deinit_resources();
	init_default_graphics(); defer deinit_default_graphics();

	shader_default := compile_shader_vf(VERT_DEFAULT, incl(DSTHEADER_DEFAULT, FRAG_EXTENDED));
	defer deinit(*shader_default);
	// loaded_assets := load_assets("./res/animated_cube/AnimatedCube.gltf");
	loaded_assets := load_assets("./res/arm.glb");
	print("nodes:\n");
	for loaded_assets.nodes print("%\n\n", it);
	// print("animations:\n");
	// for loaded_assets.animations print("%\n\n", it);
	// print("materials:\n");
	// for loaded_assets.materials print("%\n\n", it);
	// print("%\n", loaded_assets.animations);
	defer deinit(*loaded_assets);
	glEnable(GL_CULL_FACE);
	for window_cycle() {
		for Events if it.type == {
			case .KEY; using it.key_event;
			if type == .PRESS ifx keycode == {
				case GLFW_KEY_ESCAPE; exit();
				case #char"P"; screenshot();
			}
			case .MOUSE_BUTTON; using it.mouse_button_event;
			if button == GLFW_MOUSE_BUTTON_LEFT && action == GLFW_PRESS {
				switch_cursor_lock();
			}
		}
		update_default_camera();

		// apply_animation(*loaded_assets, 0, fmod_cycling(current_time, loaded_assets.animations[0].delay));

		glClearColor(.7, .8, .9, 1);
		glClear(GL_COLOR_BUFFER_BIT | GL_DEPTH_BUFFER_BIT);
		// glEnable(GL_DEPTH_TEST);
		// use(*shader_default);
		// 	// for transformation(rotm) 
		// 	{
		// 		// draw_root(loaded_assets, 0);
		// 		// draw_root(loaded_assets, 1);
		// 		draw_all_roots(loaded_assets);
		// 	}
	}
}
