#import,dir "../core";
#import "Basic"()(MEMORY_DEBUGGER = true);
#import "Math";
#import "GL";

main :: () {
	defer report_memory_leaks();
	init_resources(); defer deinit_resources();
	init_default_graphics(); defer deinit_default_graphics();

	shader_default := compile_shader_vf(VERT_DEFAULT, FRAG_SHOW_NORMAL);
	defer deinit(*shader_default);
	// loaded_assets := load_assets("./res/helmet/DamagedHelmet.gltf");
	loaded_assets := load_assets("./res/shapes.glb");
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
			draw_all_roots(loaded_assets);
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