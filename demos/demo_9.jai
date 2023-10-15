#import,dir "../core";
#import "Basic"()(MEMORY_DEBUGGER = true);
#import "Math";
#import "GL";
#import "String";
#import "Random";
#import "Print_Color";

main :: () {
	defer report_memory_leaks();
	init_resources(); defer deinit_resources();
	init_default_graphics(); defer deinit_default_graphics();

	fb_gbuffer_ms := make_framebuffer(backend_state.window_metrics.size, 
		.{"depth", .DEPTH, GL_DEPTH_COMPONENT, GL_DEPTH_COMPONENT, GL_FLOAT},
		.{"color", .COLOR, GL_RGB, GL_RGB, GL_UNSIGNED_BYTE},
		.{"normal", .COLOR, GL_RGB16F, GL_RGB, GL_FLOAT},
		.{"position", .COLOR, GL_RGB16F, GL_RGB, GL_FLOAT},
		samples = 4
	);
	defer deinit(*fb_gbuffer_ms);
	fb_gbuffer := make_framebuffer(backend_state.window_metrics.size, 
		.{"depth", .COLOR, GL_R32F, GL_RED, GL_FLOAT},
		.{"color", .COLOR, GL_RGB, GL_RGB, GL_UNSIGNED_BYTE},
		.{"normal", .COLOR, GL_RGB16F, GL_RGB, GL_FLOAT},
		.{"position", .COLOR, GL_RGB16F, GL_RGB, GL_FLOAT}
	);
	defer deinit(*fb_gbuffer);

	fb_ssao_raw := make_framebuffer(backend_state.window_metrics.size, 
		.{"occlusion_raw", .COLOR, GL_RGB, GL_RGB, GL_UNSIGNED_BYTE},
	);
	defer deinit(*fb_ssao_raw);

	dstheader_gbuffer_ms := dstheader(fb_gbuffer_ms);
	srcheader_gbuffer := srcheader(fb_gbuffer);

	shader_gbuf_msaa := compile_shader_vf(SRC_VERT_SCREEN_QUAD, incl(srcheader(fb_gbuffer_ms), dstheader(fb_gbuffer), SRC_FRAG_GBUF_MSAA)); defer deinit(*shader_gbuf_msaa);
	shader_cube := compile_shader_vf(SRC_VERT_CUBE, incl(dstheader_gbuffer_ms, SRC_FRAG_EXTENDED)); defer deinit(*shader_cube);
	shader_default := compile_shader_vf(SRC_VERT_DEFAULT, incl(dstheader_gbuffer_ms, SRC_FRAG_EXTENDED)); defer deinit(*shader_default);
	shader_ssao := compile_shader_vf(SRC_VERT_SCREEN_QUAD, incl(srcheader_gbuffer, SRC_FRAG_SSAO)); defer deinit(*shader_ssao);
	shader_blur := compile_shader_vf(SRC_VERT_SCREEN_QUAD, incl(srcheaders(fb_gbuffer, fb_ssao_raw), SRC_FRAG_BLUR)); defer deinit(*shader_blur);

	loaded_assets, root := load_assets("./res/helmet/DamagedHelmet.gltf");
	defer deinit(*loaded_assets);
	noise_texture := make_noise_texture(4, 4);
	defer deinit(*noise_texture);

	default_material : Material;
	send_to_gpu(*default_material);
	defer deinit(*default_material);

	graphics_state.default_camera.linear_speed *= .3;

	glEnable(GL_CULL_FACE);
	check_gl_error();

	render_scene :: () #expand {
		glEnable(GL_DEPTH_TEST);
		use(*shader_cube);
			bind(default_material);
			set_model_transform(make_scale_matrix4(.{10, 10, 10}));
			glCullFace(GL_FRONT);
			draw_empty_mesh(36);
			glCullFace(GL_BACK);
		use(*shader_default);
			draw_node(loaded_assets, root);
		glDisable(GL_DEPTH_TEST);
	}
	for window_cycle(fps_log_period = 100, print_statistical_fps = true) {
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

		set_size(*fb_gbuffer, backend_state.window_metrics.size);
		set_size(*fb_gbuffer_ms, backend_state.window_metrics.size);
		ssao_quality := ivec2.{1280, 720};
		set_size(*fb_ssao_raw, ssao_quality);

		bind_as_target(fb_gbuffer_ms);
			clear_target(GL_DEPTH_BUFFER_BIT, .[.7, .8, .9, 1], .[0, 0, 0, 0], .[0, 0, 0, 0]);
			render_scene();
		bind_as_target(fb_gbuffer);
			use(*shader_gbuf_msaa);
				bind_as_source(fb_gbuffer_ms);
				draw_empty_mesh(6);
		bind_as_target(fb_ssao_raw);
			use(*shader_ssao);
				bind_as_source(fb_gbuffer);
				bind_sampler(4, noise_texture);
				draw_empty_mesh(6);
		bind_default_target();
			use(*shader_blur);
				set(*shader_blur, "u_ssao_quality", Vector2.{xx ssao_quality.x, xx ssao_quality.y});
				bind_as_sources(fb_gbuffer, fb_ssao_raw);
				draw_empty_mesh(6);
		check_gl_error();
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
SRC_VERT_SCREEN_QUAD :: #string GLSL
	out vec2 vo_uv;
	
	void main() {
		float points[12] = float[12](0, 0, 1, 1, 0, 1, 0, 0, 1, 0, 1, 1);
		vec2 uv = vec2(points[gl_VertexID << 1], points[(gl_VertexID << 1) | 1]);
		vo_uv = uv;
		gl_Position = vec4(uv * 2 - 1, 0, 1);
	}
GLSL
SRC_VERT_CUBE :: #run incl(UBO_CAMERA_PROPERTIES, UBO_MAT_M, VERTICE_INTERFACE_OUT, #string GLSL
	Input_Vertice gen_vertice() {
		vec3 points[8] = vec3[8](
			vec3( 1, -1, -1), vec3( 1, -1,  1),
			vec3(-1, -1,  1), vec3(-1, -1, -1),
			vec3( 1,  1, -1), vec3( 1,  1,  1),
			vec3(-1,  1,  1), vec3(-1,  1, -1)
		);
		vec3 normals[6] = vec3[6](
			vec3( 0, -1,  0),
			vec3( 0,  1,  0),
			vec3( 1,  0,  0),
			vec3( 0,  0,  1),
			vec3(-1,  0,  0),
			vec3( 0,  0, -1)
		);
		int indices[36] = int[36](
			1, 2, 3, 7, 6, 5, 4, 5, 1, 5, 6, 2,
			2, 6, 7, 0, 3, 7, 0, 1, 3, 4, 7, 5,
			0, 4, 1, 1, 5, 2, 3, 2, 7, 4, 0, 7
		);
		vec3 point = points[indices[gl_VertexID]];
		vec3 normal = normals[(gl_VertexID / 3) % 6];
		return Input_Vertice(point, normal, vec2(0));
	}
GLSL);
SRC_FRAG_SSAO :: #run incl(UBO_SCREEN_METRICS, gen_kernel(), UBO_CAMERA_PROPERTIES, UBO_TIME_INFO, #string GLSL
	layout(binding = 4) uniform sampler2D u_noise;

	in vec2 vo_uv;
	out vec4 o_color;

	float linearize_depth(float depth) {
		float z = depth * 2 - 1; 
		return (2 * u_near * u_far) / (u_far + u_near - z * (u_far - u_near));	
	}

	void main() {
		vec2 noise_scale = u_window_size / 4; 
		vec2 uv = vo_uv;

		float depth = texture(u_depth, uv).x;
		if(depth >= 1.) {
			o_color = vec4(1);
			return;
		}

		vec3 frag_pos = texture(u_position, uv).xyz;
		vec3 normal = texture(u_normal, uv).xyz;
		vec3 random_vec = normalize(texture(u_noise, uv * noise_scale).xyz);
		vec3 tangent = normalize(random_vec - normal * dot(random_vec, normal));
		vec3 bitangent = cross(normal, tangent);		
		mat3 TBN = mat3(tangent, bitangent, normal);

		float occlusion = 0;
		int samples_count = kernel_size;
		for(int i = 0; i < samples_count; i++) {
			vec3 offset = TBN * kernel_values[i];
			vec3 sample_pos = frag_pos + offset;

			vec4 P = u_mat_trp * vec4(sample_pos, 1);
			P.xyz /= P.w;
			vec2 Q = abs(P.xy);
			if(max(Q.x, Q.y) > 1) continue;
			P.xyz = P.xyz * .5 + .5;

			float scene_depth = texture(u_depth, P.xy).x;
			float point_depth = linearize_depth(P.z);
			scene_depth = linearize_depth(scene_depth);

			// float range_check = smoothstep(0, 1, kernel_radius / abs(scene_depth - point_depth));
			float range_check = smoothstep(kernel_radius, 0, abs(scene_depth - point_depth));
			occlusion += (scene_depth < point_depth - kernel_bias ? 1. : 0.) * range_check;
		}
		occlusion = 1 - (occlusion / float(samples_count));
		o_color = vec4(vec3(occlusion), 1);
	}
GLSL);

SRC_FRAG_BLUR :: #run incl(UBO_SCREEN_METRICS, UBO_TIME_INFO, #string GLSL
	in vec2 vo_uv;
	out vec4 o_color;
	uniform vec2 u_ssao_quality = vec2(1);

	void main() {
		vec2 uv = vo_uv;
		vec2 texture_factor = 1.0 / u_ssao_quality;

		float kernel[4] = float[4](1, 1, 1, 1);
		const float S = 1. / (4 * 4);

		float occlusion = 0;
		float depth = texture(u_depth_0, uv).x;
		if(depth >= 1.) {
			occlusion = 1;
		} else {
			for(int x = -2; x <= 1; ++x) {
				for(int y = -2; y <= 1; ++y) {
					vec2 offset = (vec2(float(x), float(y)) + .5) * texture_factor;
					float src = texture(u_occlusion_raw_1, vo_uv + offset).x;
					float factor = kernel[x + 2] * kernel[y + 2] * S;
					occlusion += src * factor;
				}
			}
		}
		vec3 color = texture(u_color_0, uv).xyz;


		// if(fract(u_time * .5) < .5) 
		{
			color *= occlusion;
		}
		o_color = vec4(color, 1);
	}
GLSL);

SRC_FRAG_GBUF_MSAA :: #run incl(UBO_SCREEN_METRICS, #string GLSL
	vec4 texture_average(sampler2DMS source, vec2 uv, int samples) {
		vec4 result = vec4(0);
		for(int i = 0; i < samples; i++) {
			result += texelFetch(source, ivec2(uv * u_window_size), i);
		}
		return result / samples;
	}
	in vec2 vo_uv;
	void main() {
		#ifdef O_DEPTH
			#ifdef U_SAMPLER2DMS_DEPTH
				o_depth = texture_average(u_depth, vo_uv, SAMPLES).x;
			#endif
		#endif
		#ifdef O_COLOR
			#ifdef U_SAMPLER2DMS_COLOR
				o_color = texture_average(u_color, vo_uv, SAMPLES).xyz;
			#endif
		#endif
		#ifdef O_NORMAL
			#ifdef U_SAMPLER2DMS_NORMAL
				o_normal = texture_average(u_normal, vo_uv, SAMPLES).xyz;
				// TODO just output all vec3/4 or add O_NORMAL_EXT or something
			#endif
		#endif
		#ifdef O_POSITION
			#ifdef U_SAMPLER2DMS_POSITION
				o_position = texture_average(u_position, vo_uv, SAMPLES).xyz;
			#endif
		#endif
		#ifdef O_METALLIC_ROUGHNESS
			#ifdef U_SAMPLER2DMS_METALLIC_ROUGHNESS
				o_metallic_roughness = vec3(texture_average(u_metallic_roughness, vo_uv, SAMPLES).xy, vo_uv.x);
			#endif
		#endif
	}
GLSL);

gen_kernel :: () -> string {
	builder := String_Builder.{allocator = temp};
	KERNEL_SIZE :: 20;
	KERNEL_RADIUS :: 0.7;
	KERNEL_BIAS :: 0.025;

	print_to_builder(*builder, #string GLSL 
	const int kernel_size = %1;
	const float kernel_radius = %2;
	const float kernel_bias = %3;
	vec3 kernel_values[%1] = vec3[%1](
	GLSL, KERNEL_SIZE, KERNEL_RADIUS, KERNEL_BIAS);
	for i : 0..KERNEL_SIZE-1 {
		r := i / cast(float)KERNEL_SIZE;
		r = (r * r) * .9 + .1;
		v := Vector3.{0, 2, 0};
		while length(v) > 1 {
			for * v.component it.* = random_get_within_range(-1, 1);
		}
		v.z = abs(v.z);
		v *= r * KERNEL_RADIUS;
		print_to_builder(*builder, "\tvec3(%, %, %)%", v.x, v.y, v.z, ifx i == KERNEL_SIZE - 1 then ");\n" else ",\n");
	}
	return builder_to_string(*builder, allocator = temp);
}