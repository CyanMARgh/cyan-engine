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
	shader_show_normals := compile_shader_vf(VERT_DEFAULT, FRAG_SHOW_NORMAL);
	defer deinit(*shader_default);

	model_helmet := load_assets("./res/helmet/DamagedHelmet.gltf");
	defer deinit(*model_helmet);

	model_shapes := load_assets("./res/shapes.glb");
	defer deinit(*model_shapes);

	glEnable(GL_CULL_FACE);

	graphics_state.default_camera = .{.{yaw = 5.759186, pitch = -0.256, position = .{-6.495933, 7.488822, 16.237715}, near = 0.1, far = 1000, fow_vertical = 0.942478, screen_size = .{1280, 720}}, 10, 0.15, 0.002, 1.570796};
 
	for window_cycle() {
		for Events if it.type == {
			case .KEY; using it.key_event;
			if type == .PRESS ifx keycode == {
				case GLFW_KEY_ESCAPE; exit();
				case #char"P"; screenshot();
				case #char"C"; print("camera = %\n", graphics_state.default_camera);
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
		for *shader_show_normals {
			draw_all_roots(model_shapes);
		}
		for *shader_default {
			for translate(.{-2, 6, 0}) {
				for scale(3) draw_all_roots(model_helmet);
			}			
		}
	}
}

FRAG_SHOW_NORMAL :: #run incl(DSTHEADER_DEFAULT, #string GLSL
	in struct VO {
		vec3 position;
		vec3 normal;
		vec2 uv_0;
	} vo;

	void main() {
		vec2 uv_0 = vo.uv_0;

		#ifdef O_COLOR
			o_color = normalize(vo.normal) * .5 + .5;
		#else
			#ifdef O_COLOR4
				o_color = vec4(normalize(vo.normal) * .5 + .5, 1);
			#endif
		#endif
		#ifdef O_NORMAL
			vec3 normal = normalize(vo.normal);
			if(!gl_FrontFacing) normal *= -1;
			o_normal = normal;
		#endif
		#ifdef O_POSITION
			o_position = vo.position;
		#endif
		// #ifdef O_METALLIC_ROUGHNESS
		// 	vec2 metallic_roughness;
		// 	if((u_flags & METALLIC_ROUGHNESS) != 0) {
		// 		metallic_roughness = texture(u_metallic_roughness, uv_0).yz;
		// 	} else {
		// 		metallic_roughness = vec2(u_metallic_factor, u_roughness_factor);
		// 	}
		// 	o_metallic_roughness = vec3(metallic_roughness.xy, 0);
		// #endif
		// #ifdef O_EMISSIVE
		// 	vec3 emissive = u_emissive_strength * u_emissive_factor;
		// 	if((u_flags & EMISSIVE) != 0) {
		// 		emissive = texture(u_emissive, uv_0).xyz;
		// 	}
		// 	o_emissive = emissive;
		// #endif
	}
GLSL); 
