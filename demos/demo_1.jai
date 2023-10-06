#import,dir "../core";
// #import "Basic"()(MEMORY_DEBUGGER = true);
#import "Basic";
#import "Math";
#import "GL";

main :: () {
	// defer report_memory_leaks();
	init_resources(); defer deinit_resources();
	init_default_graphics(); defer deinit_default_graphics();

	shader_default := compile_shader_vf(SRC_VERT_DEFAULT, incl(DSTHEADER_DEFAULT, SRC_FRAG_EXTENDED));
	defer deinit(*shader_default);
	loaded_assets, root := load_assets("./res/helmet/DamagedHelmet.gltf");
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
		glClearColor(.7, .8, .9, 1);
		glClear(GL_COLOR_BUFFER_BIT | GL_DEPTH_BUFFER_BIT);
		glEnable(GL_DEPTH_TEST);
		use(*shader_default);
		draw_node(loaded_assets, root);
	}
}
SRC_VERT_DEFAULT :: #run incl(UBO_CAMERA_PROPERTIES, UBO_MAT_M, VERTICE_INTERFACE_OUT, #string GLSL
	layout (location = 0) in vec3 a_position;
	layout (location = 1) in vec3 a_normal;
	layout (location = 5) in vec2 a_uv_0;
	Input_Vertice gen_vertice() {
		return Input_Vertice(a_position, a_normal, a_uv_0);
	}
GLSL);