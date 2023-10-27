#import,dir "../core";
// #import "Basic"()(MEMORY_DEBUGGER = true);
#import "Basic";
#import "GL";

main :: () {
	// defer report_memory_leaks();
	init_resources(); defer deinit_resources();
	init_default_graphics(); defer deinit_default_graphics();

	shader_triangle := compile_shader_vf(VERT_CAMERA_UBO_TEST, FRAG_TRIANGLE);
	defer deinit(*shader_triangle);
	mesh_triangle := get_mesh(SRC_MESH_TRIANGLE);
	defer deinit(*mesh_triangle);

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
		glClear(GL_COLOR_BUFFER_BIT);

		glClear(GL_DEPTH_BUFFER_BIT);
		glDisable(GL_CULL_FACE);
		glDisable(GL_DEPTH_TEST);

		use(*shader_triangle);
		draw(mesh_triangle);
	}
}

SRC_MESH_TRIANGLE :: Mesh_Source.{
	points = .[
		 0,  1,  0,
		 1, -1,  0,
		-1, -1,  0,
	]
};
VERT_TRIANGLE :: #string GLSL
	layout (location = 0) in vec3 a_pos;

	out Vert_Out {
		vec3 position;
	} vert_out;

	void main() {
		gl_Position = vec4(a_pos, 1);
		vert_out.position = a_pos;
	}
GLSL
FRAG_TRIANGLE :: #string GLSL
	in Vert_Out {
		vec3 position;
	} vert_out;

	out vec4 o_color;

	void main() {
		o_color = vec4(vert_out.position, 1);
	}
GLSL
VERT_CAMERA_UBO_TEST :: #run incl(UBO_CAMERA_PROPERTIES, #string GLSL
	struct Input_Vertice {
		vec3 position;
		vec3 normal;
	};

	layout (location = 0) in vec3 a_pos;
	Input_Vertice gen_vertice() {
		return Input_Vertice(a_pos, vec3(0));
	}

	out Vert_Out {
		vec3 position;
	} vert_out;

	void main() {
		Input_Vertice input_vertice = gen_vertice();

		gl_Position = u_mat_trp * vec4(input_vertice.position, 1);
		vert_out.position = a_pos;
	}
GLSL);