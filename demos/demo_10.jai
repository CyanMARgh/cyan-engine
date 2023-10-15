#import,dir "../core";
#import "Basic"()(MEMORY_DEBUGGER = true);
#import "Math";
#import "GL";
#import "Print_Color";

main :: () {
	defer report_memory_leaks();
	init_resources(); defer deinit_resources();
	init_default_graphics(); defer deinit_default_graphics();

	fb_gbuffer := make_framebuffer(1280, 720, 
		.{"depth", .DEPTH, GL_DEPTH_COMPONENT, GL_DEPTH_COMPONENT, GL_FLOAT},
		.{"color", .COLOR, GL_RGB, GL_RGB, GL_UNSIGNED_BYTE},
		.{"normal", .COLOR, GL_RGB32F, GL_RGB, GL_FLOAT},
		.{"position", .COLOR, GL_RGB16F, GL_RGB, GL_FLOAT},
		.{"metallic_roughness", .COLOR, GL_RGB, GL_RGB, GL_UNSIGNED_BYTE},
		.{"emissive", .COLOR, GL_RGB16F, GL_RGB, GL_FLOAT}
		// ,samples = 8
	);
	defer deinit(*fb_gbuffer);
	shader_default := compile_shader_vf(SRC_VERT_DEFAULT, incl(dstheader(fb_gbuffer), SRC_FRAG_EXTENDED));
	defer deinit(*shader_default);
	PP_SRC_FRAG_EXTENDED := incl(dstheader(fb_gbuffer), SRC_FRAG_EXTENDED);
	// print_color("-> \n%\n", PP_SRC_FRAG_EXTENDED, color = .CYAN);

	shader_sphere := compile_shader_vf(SRC_VERT_SPHERE, PP_SRC_FRAG_EXTENDED);
	defer deinit(*shader_sphere);
	shader_screen_pass := compile_shader_vf(SRC_VERT_SCREEN_QUAD, incl(srcheader(fb_gbuffer), SRC_FRAG_SCREEN_SHOW_COLOR));
	// shader_screen_pass := compile_shader_vf(SRC_VERT_SCREEN_QUAD, incl(srcheader(fb_gbuffer), SRC_FRAG_SCREEN_SHOW_COLOR_MULTISAMPLED));
	defer deinit(*shader_screen_pass);

	loaded_assets, root := load_assets("./res/helmet/DamagedHelmet.gltf");
	defer deinit(*loaded_assets);

	Directional_Light :: struct {
		direction := #run normalize(Vector3.{1, -1, -1}) #align 16;
		strength : float = 1.;
		color := Vector3.{1, 1, 1} #align 16;
	}
	Scene_Light :: struct {
		sun : Directional_Light;
	}

	default_material : Material;
	default_material.base_color_factor = .{1, 0, 0, 1};
	send_to_gpu(*default_material);
	defer deinit(*default_material);

	scene_light := Scene_Light.{sun = .{color = .{1., 1., 1.}, strength = 4.}};
	ubo_scene_light := make_ubo_initialized(scene_light);
	defer deinit(*ubo_scene_light);
	bind(5, ubo_scene_light);

	// fb_gbuffer := make_framebuffer(1280, 720, .NORMAL | .POSITION, 8);

	graphics_state.default_camera.linear_speed *= .3;

	glEnable(GL_CULL_FACE);
	check_gl_error();

	//TODO MAKE metallic-roughness matrix
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
		set_size(*fb_gbuffer, backend_state.window_metrics.size);

		update_default_camera();
		// scene_light.sun.direction = .{sin(current_time), .5, cos(current_time)};
		// set_value(*ubo_scene_light, scene_light);

		bind_as_target(fb_gbuffer);
			clear_target(GL_DEPTH_BUFFER_BIT, 
				.[.7, .8, .9,  1], 
				.[ 0,  0,  0,  1], 
				.[ 0,  0,  0,  1], 
				.[ 0,  0,  0,  1], 
				.[ 0,  0,  0,  1]
			);
			glEnable(GL_DEPTH_TEST);
			use(*shader_sphere);
				rows, columns : u32 = 20, 30;
				set(*shader_sphere, "u_columns", columns);
				set(*shader_sphere, "u_rows", rows);
				bind(default_material);
				for j : 0..10 {
					for i : 0..10 {
						default_material.metallic_factor = i * .1;
						default_material.roughness_factor = j * .1;
						send_to_gpu(*default_material);

						set_model_transform(make_translation_matrix4(.{(j - 5) * 1.2, (i - 5) * 1.2, -9}) * make_scale_matrix4(.{.5, .5, .5}));
						draw_empty_mesh(rows * columns * 6);
					}
				}

			use(*shader_default);
				draw_node(loaded_assets, root);

		bind_default_target();
			glClear(GL_DEPTH_BUFFER_BIT);
			use(*shader_screen_pass);
				set(*shader_screen_pass, "u_time", backend_state.current_time);
				bind_as_source(fb_gbuffer);
				draw_empty_mesh(6);

		check_gl_error();
	}
}
//TODO full-length shader compilation error repott or "..." at the end

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
SRC_FRAG_SCREEN_SHOW_COLOR_MULTISAMPLED :: #string GLSL
	in vec2 vo_uv;
	out vec4 o_color;

	vec4 texture_average(sampler2DMS source, vec2 uv, int samples) {
		vec2 screen_size = vec2(1280, 720);

		vec4 result = vec4(0);
		for(int i = 0; i < samples; i++) {
			result += texelFetch(source, ivec2(uv * screen_size), i);
		}
		return result / samples;
	}
	
	void main() {
		vec2 screen_size = vec2(1280, 720);
		vec2 uv = vo_uv;
		vec3 color;

		if(uv.y > .5) {
			uv.y = uv.y * 2 - 1;
			if(uv.x > .5) {
				uv.x = uv.x * 2 - 1;
				color = texture_average(u_color, uv, SAMPLES).xyz;
			} else {
				uv.x = uv.x * 2;
				color = texture_average(u_depth, uv, SAMPLES).xxx;
			}
		} else {
			uv.y = uv.y * 2;
			if(uv.x > .5) {
				uv.x = uv.x * 2 - 1;
				color = texture_average(u_normal, uv, SAMPLES).xyz;
			} else {
				uv.x = uv.x * 2;
				color = texture_average(u_position, uv, SAMPLES).xyz;
			}
		}
		o_color = vec4(color, 1);
	}
GLSL
SRC_FRAG_SCREEN_SHOW_COLOR :: #run incl(UBO_CAMERA_PROPERTIES, UBO_TIME_INFO, #string GLSL
	in vec2 vo_uv;
	out vec4 o_color;

	const float PI = 3.14159265359;

	struct Directional_Light {
		vec3 direction;
		float strength;
		vec3 color;
	};
	struct Point_Light {
		vec3 position;

		float strength;
		float char_rad;

		vec3 diffuse;
		vec3 specular;
	};
	layout(std140, binding = 5) uniform ubo_scene_light {
		Directional_Light u_sun;
	};

	float DistributionGGX(vec3 N, vec3 H, float roughness) {
		float a = roughness*roughness;
		float a2 = a*a;
		float NdotH = max(dot(N, H), 0.0);
		float NdotH2 = NdotH*NdotH;

		float nom   = a2;
		float denom = (NdotH2 * (a2 - 1.0) + 1.0);
		denom = PI * denom * denom;

		return nom / denom;
	}
	float GeometrySchlickGGX(float NdotV, float roughness) {
		float r = (roughness + 1.0);
		float k = (r*r) / 8.0;

		float nom   = NdotV;
		float denom = NdotV * (1.0 - k) + k;

		return nom / denom;
	}
	float GeometrySmith(vec3 N, vec3 V, vec3 L, float roughness) {
		float NdotV = max(dot(N, V), 0.0);
		float NdotL = max(dot(N, L), 0.0);
		float ggx2 = GeometrySchlickGGX(NdotV, roughness);
		float ggx1 = GeometrySchlickGGX(NdotL, roughness);

		return ggx1 * ggx2;
	}
	vec3 fresnelSchlick(float cosTheta, vec3 F0) {
		return F0 + (1.0 - F0) * pow(clamp(1.0 - cosTheta, 0.0, 1.0), 5.0);
	}
	vec3 get_light_v2(vec3 albedo, float metallic, float roughness, vec3 N, vec3 frag_pos, Directional_Light dl) {
		//                                N

		const float specular_strength = 0.5;

		vec3 L = normalize(-dl.direction);
		float attenuation = 1; // <1 for point 

		vec3 V = normalize(u_eye - frag_pos);
		vec3 H = normalize(V + L);

		vec3 radiance = dl.color * attenuation * dl.strength;
		vec3 F0 = vec3(0.04);
		F0 = mix(F0, albedo, metallic);
		vec3 F = fresnelSchlick(max(dot(H, V), 0), F0);

		float NDF = DistributionGGX(N, H, roughness);
		float G   = GeometrySmith(N, V, L, roughness);
		vec3 numerator = NDF * G * F;
		float denominator = 4 * max(dot(N, V), 0) * max(dot(N, L), 0) + 0.001;
		vec3 specular = numerator / denominator;

		vec3 kS = F;
		vec3 kD = vec3(1) - kS;
		kD *= 1 - metallic;

		float NdotL = max(dot(N, L), 0);
		vec3 Lo = (kD * albedo / PI + specular) * radiance * NdotL;
		return Lo;
	}
	void main() {
		vec2 screen_size = vec2(1280, 720);
		vec2 uv = vo_uv;
		vec3 color = texture(u_color, uv).xyz;
		vec2 metallic_roughness = texture(u_metallic_roughness, uv).xy;
		// vec2 metallic_roughness = vec2(.1, sin(u_time) * .5 + .5);
		vec3 emissive = texture(u_emissive, uv).xyz;

		vec3 normal = texture(u_normal, uv).xyz;
		vec3 frag_pos = texture(u_position, uv).xyz;
		float frag_depth = texture(u_depth, uv).x;

		if(frag_depth < 1.) {
			color = pow(color, vec3(2.2));
			vec3 result_color = get_light_v2(color, metallic_roughness.y, metallic_roughness.x, normal, frag_pos, u_sun);
			result_color += emissive;
			result_color = result_color / (result_color + 1.);
			result_color = pow(result_color, vec3(1. / 2.2));
			color = result_color;			

			// vec3 result_light = vec3(0);
			// result_light += get_light(normal, frag_pos, u_sun);
			// vec3 result_color = result_light * color;
			// color = result_color;
		}

		o_color = vec4(color, 1);
	}
GLSL);

SRC_FRAG_SCREEN_SHOW_COLOR_V2 :: #run incl(UBO_CAMERA_PROPERTIES, UBO_TIME_INFO, #string GLSL
	in vec2 vo_uv;
	out vec4 o_color;
	const float PI = 3.14159265359;

	struct Directional_Light {
		vec3 direction;
		float strength;
		vec3 color;
	};
	struct Point_Light {
		vec3 position;

		float strength;
		float char_rad;

		vec3 diffuse;
		vec3 specular;
	};
	layout(std140, binding = 5) uniform ubo_scene_light {
		Directional_Light u_sun;
	};

	void main() {
		o_color = vec4(1, 0, 0, 1);
	}
GLSL);

SRC_VERT_SPHERE :: #run incl(UBO_CAMERA_PROPERTIES, UBO_MAT_M, VERTICE_INTERFACE_OUT, #string GLSL
	uniform uint u_rows;
	uniform uint u_columns;
	const float PI = 3.14159265359;

	Input_Vertice gen_vertice() {
		uint subid = gl_VertexID % 6;
		uint quad_column = (gl_VertexID / 6) % u_columns;
		uint quad_row = gl_VertexID / (6 * u_columns);
		uint offsets[12] = uint[12](0, 1, 0, 0, 1, 1, 0, 1, 1, 1, 1, 2);
		uint row = quad_row + offsets[subid << 1];
		uint column = quad_column + offsets[(subid << 1) | 1];

		float yaw = 2 * PI * float(column) / float(u_columns);
		float pitch = PI * float(row) / float(u_rows);

		vec3 pos0 = vec3(sin(yaw) * sin(pitch), cos(pitch), cos(yaw) * sin(pitch));

		return Input_Vertice(pos0, pos0, vec2(0));
	}
GLSL);


