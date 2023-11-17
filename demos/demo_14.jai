#import,dir "../core";
#import "Basic"()(MEMORY_DEBUGGER = true);
#import "Math";
#import "GL";

main :: () {
	defer report_memory_leaks();
	init_resources(); defer deinit_resources();
	init_default_graphics(); defer deinit_default_graphics();

	fb_gbuffer := make_framebuffer(1280, 720, 
		.{"depth", .DEPTH, GL_DEPTH_COMPONENT, GL_DEPTH_COMPONENT, GL_FLOAT},
		.{"color", .COLOR, GL_RGB, GL_RGB, GL_UNSIGNED_BYTE},
		.{"normal", .COLOR, GL_RGB16F, GL_RGB, GL_FLOAT},
		.{"position", .COLOR, GL_RGB32F, GL_RGB, GL_FLOAT}
	);
	defer deinit(*fb_gbuffer);
	fb_depth_filtered := make_framebuffer(1280, 720,
		.{"depth_filtered", .COLOR, GL_R32F, GL_RED, GL_FLOAT}
	);
	defer deinit(*fb_depth_filtered);
	fb_edges := make_framebuffer(1280, 720,
		.{"edges", .COLOR, GL_RGB16F, GL_RGB, GL_FLOAT} // TODO to GL_RGB
	);
	defer deinit(*fb_edges);

	PP_FRAG_EDGES := incl(srcheaders(fb_gbuffer, fb_depth_filtered), dstheader(fb_edges), FRAG_EDGES);
	// print(PP_FRAG_EDGES);
	shader_edges := compile_shader_vf(VERT_SCREEN_QUAD, PP_FRAG_EDGES);
	defer deinit(*shader_edges);

	shader_depth_denoise := compile_shader_vf(VERT_SCREEN_QUAD, incl(dstheader(fb_depth_filtered), srcheader(fb_gbuffer), FRAG_DEPTH_DENOISE));
	defer deinit(*shader_depth_denoise);
	// TODO move to default graphics & make show_texture() function
	shader_show_texture := compile_shader_vf(VERT_SCREEN_QUAD, FRAG_SHOW_TEXTURE);
	defer deinit(*shader_show_texture);


	shader_default := compile_shader_vf(VERT_DEFAULT, incl(dstheader(fb_gbuffer), FRAG_EXTENDED));
	// shader_default := compile_shader_vf(VERT_DEFAULT, incl(SRC_TARGET_MAIN, FRAG_EXTENDED));
	defer deinit(*shader_default);
	// shader_border := compile_shader_vf(VERT_BORDER, incl(SRC_TARGET_MAIN, FRAG_SINGLE_COLOR));
	// defer deinit(*shader_default);
	shader_screen_pass := compile_shader_vf(VERT_SCREEN_QUAD, FRAG_SHOW_TEXTURE);
	// shader_screen_pass := compile_shader_vf(VERT_SCREEN_QUAD, incl(FRAG_SCREEN_REMOVE_CLUSTERS));
	defer deinit(*shader_screen_pass);

	loaded_assets := load_assets("./res/helmet/DamagedHelmet.gltf");
	// loaded_assets, root := load_assets("./res/truck/CesiumMilkTruck.gltf");
	defer deinit(*loaded_assets);

	// fb_gbuffer := make_framebuffer(1280, 720, .NORMAL | .POSITION, 8);

	// graphics_state.default_camera = .{.{yaw = 5.445257, pitch = -0.222045, position = .{-2.032923, 0.498405, 1.628186}, near = 0.1, far = 1000, fow_vertical = 0.942478, screen_size = .{1280, 720}, }, 9, 0.15, 1.570796};
	graphics_state.default_camera = .{.{yaw = 5.243458, pitch = -0.443349, position = .{-1.459238, 0.34051, -0.199949}, near = 0.1, far = 1000, fow_vertical = 0.942478, screen_size = .{1280, 720}, }, 9, 0.15, 1.570796};
	update_default_camera(true);

	glEnable(GL_CULL_FACE);
	check_gl_error();
	for window_cycle() {
		for Events if it.type == {
			case .KEY; using it.key_event;
			if type == .PRESS ifx keycode == {
				case GLFW_KEY_ESCAPE; exit();
				case #char"P"; screenshot();
				case #char"K"; print("%\n", graphics_state.default_camera);
			}
			case .MOUSE_BUTTON; using it.mouse_button_event;
			if button == GLFW_MOUSE_BUTTON_LEFT && action == GLFW_PRESS {
				switch_cursor_lock();
			}
		}
		update_default_camera();
		set_size(*fb_gbuffer, backend_state.window_metrics.size);

		// bind_default_target();
		// 	clear_target(GL_DEPTH_BUFFER_BIT, .[.7, .8, .9,  1]);
		// 	use(*shader_default);
		// 		glEnable(GL_DEPTH_TEST);
		// 		draw_node(loaded_assets, root);
		// 	use(*shader_border);
		// 		glCullFace(GL_FRONT);
		// 		draw_node(loaded_assets, root);
		// 		glCullFace(GL_BACK);


		// print("->% x %\n", fb_gbuffer.width, fb_gbuffer.height);

		bind_as_target(fb_gbuffer);
			glClearBufferfv(GL_COLOR, 0, float.[.7, .8, .9,  1].data);
			glClearBufferfv(GL_COLOR, 1, float.[ 0,  0,  0,  1].data);
			glClearBufferfv(GL_COLOR, 2, float.[ 0,  0,  0,  1].data);
			glClear(GL_DEPTH_BUFFER_BIT);

			glEnable(GL_DEPTH_TEST);
			use(*shader_default);
				draw_all_roots(loaded_assets);
			glDisable(GL_DEPTH_TEST);

		bind_as_target(fb_depth_filtered);
			use(*shader_depth_denoise);
				bind_as_source(fb_gbuffer);
				draw_empty_mesh(6);

		bind_as_target(fb_edges);
			use(*shader_edges);
				bind_as_sources(fb_gbuffer, fb_depth_filtered);
				draw_empty_mesh(6);
		// bind_as_target(fb_sobel);
		// 	use(*shader_sobel);
		// 		bind_as_source(fb_gbuffer);
		// 		draw_empty_mesh(6);

		// bind_default_target();
		// 	use(*shader_screen_pass);
		// 		bind_sampler(0, fb_sobel.textures[0]);
		// 		draw_empty_mesh(6);

		bind_default_target();
			use(*shader_show_texture);
				bind_sampler(0, fb_edges.textures[0]);
				draw_empty_mesh(6);

		// bind_default_target();

		// glClear(GL_DEPTH_BUFFER_BIT);
		// use(*shader_screen_pass);
		// 	set(*shader_screen_pass, "u_time", backend_state.current_time);
		// 	bind_as_source(fb_gbuffer);
		// draw_empty_mesh(6);

		check_gl_error();
	}
}

VERT_BORDER :: #run incl(UBO_CAMERA_PROPERTIES, UBO_MAT_M, VERTICE_INTERFACE_OUT, #string GLSL
	layout (location = 0) in vec3 a_position;
	layout (location = 1) in vec3 a_normal;
	layout (location = 5) in vec2 a_uv_0;
	uniform float offset = 0.03;
	Input_Vertice gen_vertice() {
		return Input_Vertice(a_position + a_normal * offset, -a_normal, a_uv_0);
	}
GLSL);
FRAG_SINGLE_COLOR :: #run incl(#string GLSL
	uniform vec4 u_color = vec4(0, 0, 0, 1);
	void main() {
		o_color = u_color;
	}
GLSL);
FRAG_EDGES :: #run incl(UBO_SCREEN_METRICS, UBO_CAMERA_PROPERTIES, UBO_TIME_INFO, #string GLSL
	in vec2 vo_uv;
	vec2 scale;
	vec4 at(sampler2D tex, float dx, float dy) {
		return texture(tex, vo_uv + vec2(dx, dy) * scale);
	}
	vec4 sobel_x(sampler2D tex) {
		return 
			(at(tex, 1, 1) + 2 * at(tex, 1, 0) + at(tex, 1, -1)) - 
			(at(tex, -1, 1) + 2 * at(tex, -1, 0) + at(tex, -1, -1))
		;
	}
	vec4 sobel_y(sampler2D tex) {
		return 
			(at(tex, 1, 1) + 2 * at(tex, 0, 1) + at(tex, -1, 1)) - 
			(at(tex, 1, -1) + 2 * at(tex, 0, -1) + at(tex, -1, -1))
		;
	}
	vec4 bidir_filter(sampler2D tex) {
		return 4 * at(tex, 0, 0) - at(tex, 1, 0) - at(tex, 0, 1) - at(tex, -1, 0) - at(tex, 0, -1);
	}
	// float linearize_depth(float depth) {
	// 	float z = depth * 2 - 1; 
	// 	return (2 * u_near * u_far) / (u_far + u_near - z * (u_far - u_near));
	// }
	// float lat(float dx, float dy) {
	// 	return linearize_depth(texture(u_depth, vo_uv + vec2(dx, dy) * scale).x);
	// }
	// float lsobel_x() {
	// 	return lat(.5, .5) - lat(-.5, -.5);
	// }
	// float lsobel_y() {
	// 	return lat(-.5, .5) - lat(.5, -.5);
	// }

	void main() {
		vec3 V = normalize(texture(u_position_0, vo_uv).xyz - u_eye);
		vec3 N = texture(u_normal_0, vo_uv).xyz;

		scale = 1. / u_window_size;
		float d = texture(u_depth_filtered_1, vo_uv).x;
		float ls = abs(bidir_filter(u_depth_filtered_1).x);
		ls *= abs(dot(V, N));
		float ps = dot(bidir_filter(u_position_0).xyz, N) * 40;

		float ns = 5 * dot(abs(bidir_filter(u_normal_0).xyz), vec3(1)) / clamp(d, 0.001, 1000.);


		o_edges = vec3(1 - ps - ns > .7 ? 1 : 0);
	}
GLSL);

FRAG_DEPTH_DENOISE :: #run incl(UBO_SCREEN_METRICS, UBO_CAMERA_PROPERTIES, #string GLSL
	vec2 scale;
	in vec2 vo_uv;
	float linearize_depth(float depth) {
		float z = depth * 2 - 1; 
		return (2 * u_near * u_far) / (u_far + u_near - z * (u_far - u_near));
	}
	// float scale_back(float depth) {
	// 	return ((u_far + u_near) - ((2 * u_near * u_far) / Z)) / (u_far - u_near) * .5 + .5;
	// }
	float lat(float dx, float dy) {
		// return linearize_depth(texture(u_depth, vo_uv + vec2(dx, dy) * scale).x);
		return texture(u_depth, vo_uv + vec2(dx, dy) * scale).x;
	}
	void main() {
		scale = 1. / u_window_size;
		float l = lat(0, 0);
		l = max(l, lat(-1, 0));
		l = max(l, lat(1, 0));
		l = max(l, lat(0, 1));
		l = max(l, lat(0, -1));
		o_depth_filtered = linearize_depth(l);
	}
GLSL);

FRAG_SCREEN_SHOW_COLOR :: #run incl(UBO_SCREEN_METRICS, UBO_TIME_INFO, #string GLSL
	in vec2 vo_uv;
	out vec4 o_color;

	// TODO add u_target_scale to window metrics;
	vec2 scale;
	vec4 disp_of(sampler2D tex) {
		vec4 S = vec4(0);
		vec4 S2 = vec4(0);
		for(int y = -1; y <= 1; y++) {
			for(int x = -1; x <= 1; x++) {
				vec4 c;
				c = texture(tex, vo_uv + vec2(x, y) * scale);
				S += c;
				S2 += c * c;
			}
		}
		S /= 9;
		S2 /= 9;
		return S2 - S * S;		
	}
	
	void main() {
		scale = 1. / u_window_size;
		vec2 uv = vo_uv;
		float d1 = dot(disp_of(u_normal), vec4(1, 1, 1, 0));
		float d2 = dot(disp_of(u_color), vec4(1, 1, 1, 0));

		o_color = vec4(vec3(d1 + d2 > .2 ? 1 : 0), 1);
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

