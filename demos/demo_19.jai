#import,dir "../core";
#import "Basic"()(MEMORY_DEBUGGER = true);
#import "Math";
#import "GL";

main :: () {
	defer report_memory_leaks();
	init_resources(); defer deinit_resources();
	init_default_graphics(); defer deinit_default_graphics();

	shader_default := compile_shader_vf(VERT_SHELL, FRAG_SHELL);
	defer deinit(*shader_default);
	// loaded_assets := load_assets("./res/helmet/DamagedHelmet.gltf");
	// defer deinit(*loaded_assets);

	// mesh_surface := get_mesh(plane_source);
	// defer deinit(*mesh_surface);

	perlin_texture := load_texture_from_file("res/perlin_noise.png");
	defer deinit(*perlin_texture);

	// graphics_state.default_camera = .{.{yaw = 0.616349, pitch = -0.825441, position = .{1.16945, 2.000623, 1.706091}, near = 0.1, far = 1000, fow_vertical = 0.942478, screen_size = .{1280, 720}, }, 10, 0.15, 1.570796};
	// graphics_state.default_camera = .{.{yaw = 0.59886, pitch = -0.750328, position = .{1.16945, 2.000623, 1.706091}, near = 0.1, far = 1000, fow_vertical = 0.942478, screen_size = .{1280, 720}, }, 10, 0.15, 1.570796};
	update_default_camera(true);

	sphere_quality :u32: 20; 
	layers_count :: 64;

	sphere_position :: (time : float) -> Vector3 {
		return .{sin(time), cos(time), 0};
	}
	sphere_speed :: (time : float) -> Vector3 {
		return .{cos(time), -sin(time), 0};
	}
	sphere_offset :: (time : float) -> Vector3 {
		return -normalize(sphere_speed(time)) * .5 + Vector3.{0, -.5, 0};
	}

	// glEnable(GL_CULL_FACE);
	for window_cycle(print_statistical_fps = true) {
		for Events if it.type == {
			case .KEY; using it.key_event;
			if type == .PRESS ifx keycode == {
				case GLFW_KEY_ESCAPE; exit();
				case #char"P"; screenshot();
				case #char"C"; print("%\n", graphics_state.default_camera);
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
			bind(0, perlin_texture);
			set(*shader_default, "u_rows", sphere_quality);
			set(*shader_default, "u_columns", sphere_quality);
			set(*shader_default, "u_layers", cast(u32)layers_count);
			set(*shader_default, "u_extra_offset", sphere_offset(current_time));
			for i : 0..layers_count-1 {
				set(*shader_default, "u_current_layer", cast(u32)i);
				set(*shader_default, "u_h", i / cast(float)(layers_count - 1));
				for translate(sphere_position(current_time)) {
					set_model_transform(graphics_state.scene_translation);
					draw_empty_mesh(sphere_quality * sphere_quality * 6);
				}
			}
	}
}
plane_source :: Mesh_Source.{
	points =  .[-1, 0, -1, -1, 0, 1, 1, 0, 1, 1, 0, -1],
	normals = .[0, 1, 0, 0, 1, 0, 0, 1, 0, 0, 1, 0],
	uvs_0 =   .[0, 0, 0, 1, 1, 1, 1, 0],
	indices = .[0, 1, 2, 0, 2, 3]
};

VERT_SHELL :: #run incl(VERT_SPHERE_GENERATOR, UBO_MAT_M, UBO_CAMERA_PROPERTIES, UBO_TIME_INFO, #string GLSL
	uniform uint u_layers = 64;
	uniform float u_hmax = .2;
	uniform uint u_current_layer = 0;

	uniform vec3 u_extra_offset;// = vec3(0, -.8, 0);

	out struct VO {
		vec3 position;
		vec3 normal;
		vec2 uv_0;
		// float h;
	} vo;


	void main() {
		Input_Vertice input_vertice = gen_vertice();
		vec4 world_pos = u_mat_m * vec4(input_vertice.position, 1);

		vec3 world_normal = normalize((vec4(input_vertice.normal, 0) * inverse(u_mat_m)).xyz);
	
		float h = u_current_layer / float(u_layers - 1);
		// float h = float(gl_InstanceID) / float(LAYERS - 1);
		world_pos.xyz += u_hmax * (h * world_normal + h * u_extra_offset);

		gl_Position = u_mat_trp * world_pos;
		vo = VO(
			world_pos.xyz,
			world_normal,
			input_vertice.uv_0
			// ,h
		);
	}
GLSL);

FRAG_SHELL :: #run incl(UBO_TIME_INFO, #string GLSL
	layout(binding = 0) uniform sampler2D u_height_map;

	in struct VO {
		vec3 position;
		vec3 normal;
		vec2 uv_0;
		// float h;
	} vo;

	out vec4 o_color;

	float hash12(vec2 p) {
		vec3 p3  = fract(vec3(p.xyx) * .1031);
		p3 += dot(p3, p3.yzx + 33.33);
		return fract((p3.x + p3.y) * p3.z);
	}

	float get_height(vec2 p) {
		p *= 400;
		vec2 pc = floor(p) + .5;
		float gh = hash12(pc);
		float r = length(p - pc);

		return max(0, gh - r / 2);
	}
	// float get_height(vec2 p) {
	// 	float h =  
	// 		texture(u_height_map, vec2(.4, .1) + p * 13).x * .2 +
	// 		texture(u_height_map, vec2(.1, .3) + p * 7).x * .2 +
	// 		texture(u_height_map, vec2(.5, .2) + p * 3).x * .3 +
	// 		texture(u_height_map, p).x * .3
	// 	;
	// 	return mix(.5, h, (1 - pow(p.y, 3)) * (1 - pow(1 - p.y, 3)));
	// }

	uniform float u_h;
	void main() {
		// float h = vo.h;
		float h = u_h;

		float gh = get_height(vo.uv_0);
		if(gh < h) discard;

		vec3 color = mix(vec3(.3, .5, .4), vec3(.5, .9, .6), h);
		o_color = vec4(color, 1);
	}
GLSL);









