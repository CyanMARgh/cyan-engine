#import,dir "../core";
#import "Basic"()(MEMORY_DEBUGGER = true);
#import "Math";
#import "GL";
#import "Print_Color";
#import "Random";

main :: () {
	defer report_memory_leaks();
	init_resources(); defer deinit_resources();
	init_default_graphics(); defer deinit_default_graphics();

	fb_gbuffer_ms := make_framebuffer(backend_state.window_metrics.size, 
		.{"depth", .DEPTH, GL_DEPTH_COMPONENT, GL_DEPTH_COMPONENT, GL_FLOAT},
		.{"color", .COLOR, GL_RGB, GL_RGB, GL_UNSIGNED_BYTE},
		.{"normal", .COLOR, GL_RGB16F, GL_RGB, GL_FLOAT},
		.{"position", .COLOR, GL_RGB16F, GL_RGB, GL_FLOAT},
		.{"metallic_roughness", .COLOR, GL_RGB, GL_RGB, GL_UNSIGNED_BYTE},
		.{"emissive", .COLOR, GL_RGB, GL_RGB, GL_UNSIGNED_BYTE},
		samples = 4
	);
	defer deinit(*fb_gbuffer_ms);
	// fb_gbuffer := make_framebuffer(backend_state.window_metrics.size, 
	// 	// .{"depth", .DEPTH, GL_DEPTH_COMPONENT, GL_DEPTH_COMPONENT, GL_FLOAT},
	// 	.{"depth", .COLOR, GL_R32F, GL_RED, GL_FLOAT},
	// 	.{"color", .COLOR, GL_RGB, GL_RGB, GL_UNSIGNED_BYTE},
	// 	.{"normal", .COLOR, GL_RGB16F, GL_RGB, GL_FLOAT},
	// 	.{"position", .COLOR, GL_RGB16F, GL_RGB, GL_FLOAT},
	// 	.{"metallic_roughness", .COLOR, GL_RGB, GL_RGB, GL_UNSIGNED_BYTE},
	// 	.{"emissive", .COLOR, GL_RGB, GL_RGB, GL_UNSIGNED_BYTE}
	// );
	// defer deinit(*fb_gbuffer);

	fb_ssao_raw := make_framebuffer(backend_state.window_metrics.size, 
		.{"occlusion_raw", .COLOR, GL_RED, GL_RED, GL_UNSIGNED_BYTE},
	);
	defer deinit(*fb_ssao_raw);
	fb_ssao_blurred := make_framebuffer(backend_state.window_metrics.size, 
		.{"occlusion", .COLOR, GL_RGB, GL_RGB, GL_UNSIGNED_BYTE},
	);
	defer deinit(*fb_ssao_blurred);

	// dstheader_gbuffer := dstheader(fb_gbuffer);
	default_target := dstheader(fb_gbuffer_ms);

	// shader_gbuf_msaa := compile_shader_vf(incl(defs("NOFLIP"), SRC_VERT_SCREEN_QUAD), incl(srcheader(fb_gbuffer_ms), dstheader(fb_gbuffer), SRC_FRAG_GBUF_MSAA)); defer deinit(*shader_gbuf_msaa);
	shader_default := compile_shader_vf(SRC_VERT_DEFAULT, incl(default_target, SRC_FRAG_EXTENDED)); defer deinit(*shader_default);
	shader_background_cubemap := compile_shader_vf(SRC_VERT_SCREEN_CUBE, incl(default_target, SRC_FRAG_BACKGROUND_CUBEMAP)); defer deinit(*shader_background_cubemap);
	shader_sphere := compile_shader_vf(SRC_VERT_SPHERE, incl(default_target, SRC_FRAG_EXTENDED)); defer deinit(*shader_sphere);

	// shader_cube := compile_shader_vf(SRC_VERT_CUBE, incl(dstheader_gbuffer_ms, SRC_FRAG_EXTENDED)); defer deinit(*shader_cube);
	// shader_default := compile_shader_vf(SRC_VERT_DEFAULT, incl(dstheader_gbuffer_ms, SRC_FRAG_EXTENDED)); defer deinit(*shader_default);
	PP_SRC_FRAG_SSAO := incl(dstheader(fb_ssao_raw), srcheader(fb_gbuffer_ms), SRC_FRAG_SSAO);
	// print(PP_SRC_FRAG_SSAO);
	shader_ssao := compile_shader_vf(incldefs("NOFLIP", SRC_VERT_SCREEN_QUAD), PP_SRC_FRAG_SSAO); defer deinit(*shader_ssao);
	shader_blur := compile_shader_vf(incl(defs("NOFLIP"), SRC_VERT_SCREEN_QUAD), incl(srcheaders(fb_gbuffer_ms, fb_ssao_raw), SRC_FRAG_BLUR)); defer deinit(*shader_blur);
	shader_light_pass := compile_shader_vf(incl(defs("NOFLIP"), SRC_VERT_SCREEN_QUAD), incl(srcheader(fb_gbuffer_ms), SRC_FRAG_LIGHT_PASS)); defer deinit(*shader_light_pass);

	shader_show_texture := compile_shader_vf(SRC_VERT_SCREEN_QUAD, incldefs("FIRST_CHANNEL", SRC_FRAG_SHOW_TEXTURE)); defer deinit(*shader_show_texture);
	shader_show_cubemap := compile_shader_vf(SRC_VERT_SCREEN_CUBE, SRC_FRAG_SHOW_CUBEMAP); defer deinit(*shader_show_cubemap);
	// shader_default := compile_shader_vf(SRC_VERT_DEFAULT, SRC_FRAG_REFLECTIVE_TEXTURED); defer deinit(*shader_default);

	material_default : Material;
	send_to_gpu(*material_default);
	defer deinit(*material_default);

	noise_texture := make_noise_texture(4, 4);
	defer deinit(*noise_texture);

	source_cubemap, ok := load_cubemap_from_file("res/yokohama2/", "posx.jpg", "negx.jpg", "posy.jpg", "negy.jpg", "posz.jpg", "negz.jpg");
	assert(ok);
	defer deinit(*source_cubemap);
	BRDF_RESOLUTION :: 128;
	texture_brdf := make_texture_buffer(BRDF_RESOLUTION, BRDF_RESOLUTION, .{GL_RGB, GL_RGB, GL_UNSIGNED_BYTE, 0, GL_TEXTURE_2D});
	defer deinit(*texture_brdf);
	{
		shader_prerender := compile_shader_vf(incl(defs("NOFLIP"), SRC_VERT_SCREEN_QUAD), SRC_FRAG_BRDF);
		defer deinit(*shader_prerender);

		prerender_texture_fbo : u32;
		glGenFramebuffers(1, *prerender_texture_fbo);
		glBindFramebuffer(GL_FRAMEBUFFER, prerender_texture_fbo);
			glViewport(0, 0, BRDF_RESOLUTION, BRDF_RESOLUTION);
			glFramebufferTexture2D(GL_FRAMEBUFFER, GL_COLOR_ATTACHMENT0, GL_TEXTURE_2D, texture_brdf.id, 0);
			for *shader_prerender {
				draw_empty_mesh(6);
			}
		glBindFramebuffer(GL_FRAMEBUFFER, 0);
		glDeleteFramebuffers(1, *prerender_texture_fbo);
	}

	PCM_RESOLUTION :: 256;
	prerendered_cubemap := make_cubemap(PCM_RESOLUTION, PCM_RESOLUTION, true);
	defer deinit(*prerendered_cubemap);
	{
		// shader_prerender := compile_shader_vf(SRC_VERT_TO_CUBEMAP, SRC_FRAG_SHOW_UV);
		shader_prerender := compile_shader_vf(SRC_VERT_TO_CUBEMAP, SRC_FRAG_PREFILTER);
		defer deinit(*shader_prerender);

		prerendered_cubemap_fbo : u32;
		glGenFramebuffers(1, *prerendered_cubemap_fbo);
		glBindFramebuffer(GL_FRAMEBUFFER, prerendered_cubemap_fbo);

		max_mml :: 6;
		for mml : 0..max_mml-1 {
			layer_width := PCM_RESOLUTION * pow(.5, xx mml);
			roughness := mml / cast(float)(max_mml-1);
			for i : 0..5 {
				glViewport(0, 0, xx layer_width, xx layer_width);
				glFramebufferTexture2D(GL_FRAMEBUFFER, GL_COLOR_ATTACHMENT0, xx(GL_TEXTURE_CUBE_MAP_POSITIVE_X + i), prerendered_cubemap.id, xx mml);
				for *shader_prerender {
					set("u_roughness", roughness);
					set("u_part_id", cast(u32)i);
					bind_sampler(0, source_cubemap);
					draw_empty_mesh(6);				
				}
			}
		}


		glBindFramebuffer(GL_FRAMEBUFFER, 0);
		glDeleteFramebuffers(1, *prerendered_cubemap_fbo);
	}
	loaded_assets, root := load_assets("./res/helmet/DamagedHelmet.gltf");
	defer deinit(*loaded_assets);

	graphics_state.default_camera = .{
		.{
			yaw = 6.045851,
			pitch = -0.217186,
			position = .{-2.900604, 1.000558, 3.244453},
			near = 0.1, 
			far = 1000, 
			fow_vertical = 0.942478,
			screen_size = .{1280, 720}, 
		}, 
		10, 0.15, 1.570796
	};
	set_value(*graphics_state.ubo_default_camera, to_ubo_content(graphics_state.default_camera));

	glEnable(GL_CULL_FACE);
	for window_cycle(capture_video = false, print_statistical_fps = true) {
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

		// set_size(*fb_gbuffer, backend_state.window_metrics.size);
		set_size(*fb_gbuffer_ms, backend_state.window_metrics.size);
		set_size(*fb_ssao_raw, backend_state.window_metrics.size);

		// bind_as_target(fb_gbuffer_ms);
		bind_as_target(fb_gbuffer_ms);
			glClearColor(.7, .8, .9, 1);
			glClear(GL_COLOR_BUFFER_BIT | GL_DEPTH_BUFFER_BIT);
			clear_target(GL_COLOR_BUFFER_BIT | GL_DEPTH_BUFFER_BIT, 
				.[.7, .8, .9, 1],
				.[ 0,  0,  0, 1],
				.[ 0,  0,  0, 1],
				.[ 0,  0,  0, 1],
				.[ 0,  0,  0, 1],
			);
			glCullFace(GL_FRONT);
				use(*shader_background_cubemap);
					bind_sampler(0, source_cubemap);
					draw_empty_mesh(36);
			glCullFace(GL_BACK);
			glEnable(GL_DEPTH_TEST);
			use(*shader_sphere);
				rows, columns : u32 = 50, 50;
				set(*shader_sphere, "u_columns", columns);
				set(*shader_sphere, "u_rows", rows);
				bind_sampler(7, prerendered_cubemap);
				bind_sampler(6, texture_brdf);
				bind(material_default);
				for j : 0..7 {
					for i : 0..7 {
						material_default.metallic_factor = i / 7.;
						material_default.roughness_factor = j / 7.;
						send_to_gpu(*material_default);
						set_model_transform(make_translation_matrix4(.{(j - 5) * 1.2, (i - 5) * 1.2, -9}) * make_scale_matrix4(.{.5, .5, .5}));
						draw_empty_mesh(rows * columns * 6);
					}
				}
				use(*shader_default);
					bind_sampler(7, prerendered_cubemap);
					bind_sampler(6, texture_brdf);
					draw_node(loaded_assets, root);
			glDisable(GL_DEPTH_TEST);
		bind_as_target(fb_ssao_raw);
			use(*shader_ssao);
				bind_as_source(fb_gbuffer_ms);
				bind_sampler(6, noise_texture);
				draw_empty_mesh(6);
		bind_as_target(fb_ssao_blurred);
			use(*shader_blur);
				bind_as_sources(fb_gbuffer_ms, fb_ssao_raw);
				draw_empty_mesh(6);
		bind_default_target();
			use(*shader_light_pass);
				bind_as_source(fb_gbuffer_ms);
				bind_sampler(6, texture_brdf);
				bind_sampler(7, prerendered_cubemap);
				bind_sampler(8, fb_ssao_blurred.textures[0]);
				draw_empty_mesh(6);
		// if current_time >= PI * 4 exit();
	}
}

SRC_VERT_SCREEN_QUAD :: #string GLSL
	out vec2 vo_uv;
	void main() {
		float points[12] = float[12](0, 0, 1, 1, 0, 1, 0, 0, 1, 0, 1, 1);
		vec2 _uv = vec2(points[gl_VertexID << 1], points[(gl_VertexID << 1) | 1]);
		#ifndef NOFLIP
		vo_uv = vec2(_uv.x, 1 - _uv.y);
		#else
		vo_uv = _uv;
		#endif
		gl_Position = vec4(_uv * 2 - 1, 0, 1);
	}
GLSL
SRC_FRAG_SHOW_TEXTURE :: #run incl(UBO_CAMERA_PROPERTIES, #string GLSL
	layout(binding = 0) uniform sampler2D u_color;
	in vec2 vo_uv;
	out vec4 o_color;
	void main() {
		#ifdef FIRST_CHANNEL
			o_color = vec4(texture(u_color, vo_uv).xxx, 1);
		#else 
			o_color = texture(u_color, vo_uv);
		#endif
	}
GLSL);
SRC_VERT_SCREEN_CUBE :: #run incl(UBO_CAMERA_PROPERTIES, #string GLSL
	out vec3 vo_direction;
	void main() {
		vec3 points[8] = vec3[8](
			vec3( 1, -1, -1), vec3( 1, -1,  1),
			vec3(-1, -1,  1), vec3(-1, -1, -1),
			vec3( 1,  1, -1), vec3( 1,  1,  1),
			vec3(-1,  1,  1), vec3(-1,  1, -1)
		);
		int indices[36] = int[36](
			1, 2, 3, 7, 6, 5, 4, 5, 1, 5, 6, 2,
			2, 6, 7, 0, 3, 7, 0, 1, 3, 4, 7, 5,
			0, 4, 1, 1, 5, 2, 3, 2, 7, 4, 0, 7
		);
		vec3 p = points[indices[gl_VertexID]];
		vo_direction = p;
		gl_Position = u_mat_p * u_mat_r * vec4(p, 1);
	}
GLSL);
SRC_FRAG_SHOW_CUBEMAP :: #run incl(UBO_TIME_INFO, #string GLSL
	layout(binding = 0) uniform samplerCube skybox;
	in vec3 vo_direction;
	out vec4 o_color;
	void main() {
		o_color = texture(skybox, vo_direction);
	}
GLSL);
SRC_FRAG_BACKGROUND_CUBEMAP :: #string GLSL
	layout(binding = 0) uniform samplerCube skybox;
	in vec3 vo_direction;
	void main() {
		vec4 base_color = texture(skybox, vo_direction);
		#ifdef O_COLOR
			o_color = base_color.xyz;
		#else
			#ifdef O_COLOR4
				o_color = base_color;
			#endif
		#endif
		#ifdef O_NORMAL
			o_normal = -normalize(vo_direction);
		#endif
		#ifdef O_POSITION
			o_position = vec3(vo_direction * 100000);
		#endif
		#ifdef O_METALLIC_ROUGHNESS
			o_metallic_roughness = vec3(0);
		#endif
		#ifdef O_EMISSIVE
			o_emissive = vec3(0);
		#endif
	}
GLSL
SRC_FRAG_REFLECTIVE :: #run incl(UBO_CAMERA_PROPERTIES, UBO_TIME_INFO, SRC_SHADING_MODEL_REFLECTIVE_TEXTURED_V0, #string GLSL
	layout(binding = 7) uniform samplerCube u_skybox;
	layout(binding = 6) uniform sampler2D u_brdf;

	in struct VO {
		vec3 position;
		vec3 normal;
		vec2 uv_0;
	} vo;

	uniform float u_roughness;
	uniform float u_metallic;

	out vec4 o_color; 
	void main() {
		vec3 base_color = vec3(1);
		vec3 emissive = vec3(0);
		vec3 result_color = get_color(vo.position, normalize(vo.normal), base_color, vec2(u_metallic, u_roughness), emissive, u_brdf, u_skybox);

		o_color = vec4(result_color, 1.0);
	}
GLSL);
SRC_FRAG_REFLECTIVE_TEXTURED :: #run incl(UBO_CAMERA_PROPERTIES, UBO_TIME_INFO, UBO_MAT_M, GLTF_TEXTURES, SRC_SHADING_MODEL_REFLECTIVE_TEXTURED_V0, #string GLSL
	layout(binding = 7) uniform samplerCube u_skybox;
	layout(binding = 6) uniform sampler2D u_brdf;

	in struct VO {
		vec3 position;
		vec3 normal;
		vec2 uv_0;
	} vo;

	out vec4 o_color; 
	void main() {
		vec2 uv = vec2(vo.uv_0);
		vec3 base_color = texture(u_base_color, uv).xyz;
		vec2 mr = texture(u_metallic_roughness, uv).xy;
		if(fract(u_time * .5) < .5) mr = vec2(0, .5);

		vec3 emissive = texture(u_emissive, uv).xyz;
		vec3 result_color = get_color(vo.position, normalize(vo.normal), base_color, mr, emissive, u_brdf, u_skybox);

		o_color = vec4(result_color, 1.0);
	}
GLSL);
SRC_SHADING_MODEL_REFLECTIVE_TEXTURED_V0 :: #string GLSL
	const float PI = 3.141592;
	const float Epsilon = 0.00001;
	const vec3 Fdielectric = vec3(0.04);
	#define LOD_MAX_LEVEL 5

	float ndfGGX(float cosLh, float roughness) {
		float alpha   = roughness * roughness;
		float alphaSq = alpha * alpha;

		float denom = (cosLh * cosLh) * (alphaSq - 1.0) + 1.0;
		return alphaSq / (PI * denom * denom);
	}
	float gaSchlickG1(float cosTheta, float k) {
		return cosTheta / (cosTheta * (1.0 - k) + k);
	}
	float gaSchlickGGX(float cosLi, float cosLo, float roughness) {
		float r = roughness + 1.0;
		float k = (r * r) / 8.0; // Epic suggests using this roughness remapping for analytic lights.
		return gaSchlickG1(cosLi, k) * gaSchlickG1(cosLo, k);
	}
	vec3 fresnelSchlick(vec3 F0, float cosTheta) {
		return F0 + (vec3(1.0) - F0) * pow(1.0 - cosTheta, 5.0);
	}

	vec3 get_color(
		vec3 position, vec3 normal,
		vec3 base_color, vec2 metallic_rouhness, vec3 emissive,
		sampler2D u_brdf, samplerCube u_skybox,
		float ambient_occlusion = 1
	) {
		vec3 albedo = base_color;
		float metallic = metallic_rouhness.x;
		float roughness = metallic_rouhness.y;

		vec3 Lo = normalize(u_eye - position);
		vec3 N = normal;
		
		float cosLo = max(0.0, dot(N, Lo));
		vec3 Lr = 2.0 * cosLo * N - Lo;

		vec3 F0 = mix(Fdielectric, albedo, metallic);

		vec3 directLighting = vec3(0);
		for(int i=0; i<1; ++i)
		{
			// vec3 Li = -lights[i].direction;
			// vec3 Lradiance = lights[i].radiance;
			float phi = u_time * .5;
			vec3 Li = normalize(vec3(sin(phi), .1, cos(phi)));
			vec3 Lradiance = vec3(1., .9, .8);

			vec3 Lh = normalize(Li + Lo);

			float cosLi = max(0.0, dot(N, Li));
			float cosLh = max(0.0, dot(N, Lh));

			vec3 F  = fresnelSchlick(F0, max(0.0, dot(Lh, Lo)));
			float D = ndfGGX(cosLh, roughness);
			float G = gaSchlickGGX(cosLi, cosLo, roughness);

			vec3 kd = mix(vec3(1.0) - F, vec3(0.0), metallic);
			vec3 diffuseBRDF = kd * albedo;
			vec3 specularBRDF = (F * D * G) / max(Epsilon, 4.0 * cosLi * cosLo);
			directLighting += (diffuseBRDF + specularBRDF) * Lradiance * cosLi;
		}

		vec3 ambientLighting;
		{
			vec3 irradiance = textureLod(u_skybox, N, LOD_MAX_LEVEL).rgb;
			vec3 F = fresnelSchlick(F0, cosLo);
			vec3 kd = mix(vec3(1.0) - F, vec3(0.0), metallic);
			vec3 diffuseIBL = kd * albedo * irradiance;
			vec3 specularIrradiance = textureLod(u_skybox, Lr, roughness * LOD_MAX_LEVEL).rgb;
			vec2 specularBRDF = texture(u_brdf, vec2(cosLo, roughness)).rg;
			vec3 specularIBL = (F0 * specularBRDF.x + specularBRDF.y) * specularIrradiance;
			ambientLighting = diffuseIBL + specularIBL;
		}
		return directLighting + ambientLighting * ambient_occlusion + emissive;
	}
GLSL;

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

SRC_VERT_DEFAULT :: #run incl(UBO_CAMERA_PROPERTIES, UBO_MAT_M, VERTICE_INTERFACE_OUT, #string GLSL
	layout (location = 0) in vec3 a_position;
	layout (location = 1) in vec3 a_normal;
	layout (location = 5) in vec2 a_uv_0;
	Input_Vertice gen_vertice() {
		return Input_Vertice(a_position, a_normal, a_uv_0);
	}
GLSL);
SRC_FRAG_GBUF_MSAA :: #run incl(UBO_SCREEN_METRICS, #string GLSL
	vec4 texture_average(sampler2DMS source, vec2 uv, int samples) {
		vec2 screen_size = u_screen_size;
		vec4 result = vec4(0);
		for(int i = 0; i < samples; i++) {
			result += texelFetch(source, ivec2(uv * screen_size), i);
		}
		return result / samples;
	}
	in vec2 vo_uv;
	void main() {
		vec2 uv = vo_uv;
		#ifdef O_DEPTH
			#ifdef U_SAMPLER2DMS_DEPTH
				o_depth = texture_average(u_depth, uv, SAMPLES).x;
			#endif
		#endif
		#ifdef O_COLOR
			#ifdef U_SAMPLER2DMS_COLOR
				o_color = texture_average(u_color, uv, SAMPLES).xyz;
			#endif
		#endif
		#ifdef O_NORMAL
			#ifdef U_SAMPLER2DMS_NORMAL
				o_normal = texture_average(u_normal, uv, SAMPLES).xyz;
				// TODO just output all vec3/4 or add O_NORMAL_EXT or something
			#endif
		#endif
		#ifdef O_POSITION
			#ifdef U_SAMPLER2DMS_POSITION
				o_position = texture_average(u_position, uv, SAMPLES).xyz;
			#endif
		#endif
		#ifdef O_POSITION
			#ifdef U_SAMPLER2DMS_POSITION
				o_emissive = texture_average(u_emissive, uv, SAMPLES).xyz;
			#endif
		#endif
		#ifdef O_METALLIC_ROUGHNESS
			#ifdef U_SAMPLER2DMS_METALLIC_ROUGHNESS
				o_metallic_roughness = vec3(texture_average(u_metallic_roughness, uv, SAMPLES).xy, 0);
			#endif
		#endif
	}
GLSL);

SRC_VERT_TO_CUBEMAP :: #string GLSL
	uniform uint u_part_id;

	out vec3 vo_direction; 
	void main() {
		vec3 forwards[6] = vec3[6](
			vec3(1, 0, 0), vec3(-1, 0, 0), vec3(0, 1, 0), 
			vec3(0,-1, 0), vec3( 0, 0, 1), vec3(0, 0,-1)
		);
		vec3 ups[6] = vec3[6](
			vec3(0,-1, 0), vec3(0,-1, 0), vec3(0, 0, 1),
			vec3(0, 0,-1), vec3(0,-1, 0), vec3(0,-1, 0)
		);

		float uvs[12] = float[12](0, 0, 1, 1, 0, 1, 0, 0, 1, 0, 1, 1);
		vec2 uv = vec2(uvs[gl_VertexID << 1], uvs[(gl_VertexID << 1) | 1]);
		uv = vec2(uv.x, 1 - uv.y);
		gl_Position = vec4(uv * 2 - 1, 0, 1);

		vec3 forward = forwards[u_part_id];
		vec3 up = ups[u_part_id];
		vec3 right = cross(forward, up);

		vo_direction = forward + up * (uv.y * 2 - 1) + right * (uv.x * 2 - 1);
	}
GLSL
SRC_FRAG_SHOW_UV :: #string GLSL
	layout(binding = 0) uniform samplerCube u_environment_map;
	in vec3 vo_direction;
	out vec3 o_color;

	void main() {
		o_color = texture(u_environment_map, normalize(vo_direction)).xyz;
	}
GLSL

SRC_FRAG_PREFILTER :: #string GLSL
	layout(binding = 0) uniform samplerCube u_environment_map;
	uniform float u_roughness;
	// const float u_roughness = .1;
	const float PI = 3.14159265359;

	float RadicalInverse_VdC(uint bits)  {
		bits = (bits << 16u) | (bits >> 16u);
		bits = ((bits & 0x55555555u) << 1u) | ((bits & 0xAAAAAAAAu) >> 1u);
		bits = ((bits & 0x33333333u) << 2u) | ((bits & 0xCCCCCCCCu) >> 2u);
		bits = ((bits & 0x0F0F0F0Fu) << 4u) | ((bits & 0xF0F0F0F0u) >> 4u);
		bits = ((bits & 0x00FF00FFu) << 8u) | ((bits & 0xFF00FF00u) >> 8u);
		return float(bits) * 2.3283064365386963e-10;
	}
	vec2 Hammersley(uint i, uint N) {
		return vec2(float(i)/float(N), RadicalInverse_VdC(i));
	}
	vec3 ImportanceSampleGGX(vec2 Xi, vec3 N, float roughness) {
		float a = roughness*roughness;

		float phi = 2.0 * PI * Xi.x;
		float cosTheta = sqrt((1.0 - Xi.y) / (1.0 + (a*a - 1.0) * Xi.y));
		float sinTheta = sqrt(1.0 - cosTheta*cosTheta);

		vec3 H;
		H.x = cos(phi) * sinTheta;
		H.y = sin(phi) * sinTheta;
		H.z = cosTheta;

		vec3 up        = abs(N.z) < 0.999 ? vec3(0.0, 0.0, 1.0) : vec3(1.0, 0.0, 0.0);
		vec3 tangent   = normalize(cross(up, N));
		vec3 bitangent = cross(N, tangent);

		vec3 sampleVec = tangent * H.x + bitangent * H.y + N * H.z;
		return normalize(sampleVec);
	}

	in vec3 vo_direction;
	out vec3 o_color;

	void main() {
		vec3 N = normalize(vo_direction);
		vec3 R = N;
		vec3 V = R;

		const uint SAMPLE_COUNT = 1024;
		vec3 prefiltered_color = vec3(0);
		float total_weight = 0;
		for(uint i = 0; i < SAMPLE_COUNT; i++) {
			vec2 Xi = Hammersley(i, SAMPLE_COUNT);
			vec3 H = ImportanceSampleGGX(Xi, N, u_roughness);
			vec3 L = normalize(2 * dot(V, H) * H - V);

			float NdotL = max(dot(N, L), 0);
			if(NdotL > 0) {
				prefiltered_color += texture(u_environment_map, L).rgb * NdotL;
				total_weight += NdotL;
			}
		}
		prefiltered_color /= total_weight;

		o_color = prefiltered_color;
	}
GLSL
SRC_FRAG_BRDF :: #string GLSL
	const float PI = 3.14159265359;
	float RadicalInverse_VdC(uint bits)  {
		bits = (bits << 16u) | (bits >> 16u);
		bits = ((bits & 0x55555555u) << 1u) | ((bits & 0xAAAAAAAAu) >> 1u);
		bits = ((bits & 0x33333333u) << 2u) | ((bits & 0xCCCCCCCCu) >> 2u);
		bits = ((bits & 0x0F0F0F0Fu) << 4u) | ((bits & 0xF0F0F0F0u) >> 4u);
		bits = ((bits & 0x00FF00FFu) << 8u) | ((bits & 0xFF00FF00u) >> 8u);
		return float(bits) * 2.3283064365386963e-10;
	}
	vec2 Hammersley(uint i, uint N) {
		return vec2(float(i)/float(N), RadicalInverse_VdC(i));
	}
	vec3 ImportanceSampleGGX(vec2 Xi, vec3 N, float Roughness) {
		float a = Roughness * Roughness;
		float Phi = 2 * PI * Xi.x;
		float CosTheta = sqrt((1 - Xi.y) / (1 + (a * a - 1) * Xi.y));
		float SinTheta = sqrt(1 - CosTheta * CosTheta);
		vec3 H;
		H.x = SinTheta * cos(Phi);
		H.y = SinTheta * sin(Phi);
		H.z = CosTheta;
		vec3 UpVector = abs(N.z) < 0.999 ? vec3(0,0,1) : vec3(1,0,0);
		vec3 TangentX = normalize(cross(UpVector, N));
		vec3 TangentY = cross(N, TangentX);

		return TangentX * H.x + TangentY * H.y + N * H.z;
	}
	float GeometrySchlickGGX(float NdotV, float roughness) {
		float a = roughness;
		float k = (a * a) / 2.0;

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
	vec2 IntegrateBRDF(float NdotV, float roughness) {
		vec3 V;
		V.x = sqrt(1.0 - NdotV * NdotV);
		V.y = 0.0;
		V.z = NdotV;

		float A = 0.0;
		float B = 0.0;

		vec3 N = vec3(0.0, 0.0, 1.0);

		const uint SAMPLE_COUNT = 1024u;
		for(uint i = 0u; i < SAMPLE_COUNT; ++i) {
			vec2 Xi = Hammersley(i, SAMPLE_COUNT);
			vec3 H  = ImportanceSampleGGX(Xi, N, roughness);
			vec3 L  = normalize(2.0 * dot(V, H) * H - V);

			float NdotL = max(L.z, 0.0);
			float NdotH = max(H.z, 0.0);
			float VdotH = max(dot(V, H), 0.0);

			if(NdotL > 0.0) {
				float G = GeometrySmith(N, V, L, roughness);
				float G_Vis = (G * VdotH) / (NdotH * NdotV);
				float Fc = pow(1.0 - VdotH, 5.0);

				A += (1.0 - Fc) * G_Vis;
				B += Fc * G_Vis;
			}
		}
		return vec2(A, B) / float(SAMPLE_COUNT);
	}

	in vec2 vo_uv;
	out vec3 o_color;

	void main() {
		o_color = vec3(IntegrateBRDF(vo_uv.x, vo_uv.y), 0); 
	}
GLSL

SRC_FRAG_LIGHT_PASS :: #run incl(UBO_TIME_INFO, UBO_SCREEN_METRICS, UBO_CAMERA_PROPERTIES, SRC_SHADING_MODEL_REFLECTIVE_TEXTURED_V0, #string GLSL
	layout(binding = 6) uniform sampler2D u_brdf;
	layout(binding = 7) uniform samplerCube u_skybox;
	layout(binding = 8) uniform sampler2D u_ambient_occlusion;

	in vec2 vo_uv;
	out vec4 o_color;

	vec3 color_by_sampler_id(vec2 uv, int sample_id) {
		ivec2 uvs = ivec2(uv * u_window_size);

		vec3 base_color = texelFetch(u_color, uvs, sample_id).xyz;
		float depth = texelFetch(u_depth, uvs, sample_id).x;
		if(depth >= 1) {
			return base_color;
		} else {
			vec3 normal = texelFetch(u_normal, uvs, sample_id).xyz;
			vec3 position = texelFetch(u_position, uvs, sample_id).xyz;
			vec3 emissive = texelFetch(u_emissive, uvs, sample_id).xyz;
			vec2 mr = texelFetch(u_metallic_roughness, uvs, sample_id).yx;
			float ao = texture(u_ambient_occlusion, uv).x;
			return get_color(
				position, normal, 
				base_color, mr, emissive,
				u_brdf, u_skybox,
				ao
			);
		}
	}

	void main() {
		vec3 color = vec3(0);
		int samples = 4;
		for(int i = 0; i < samples; i++) {
			color += color_by_sampler_id(vo_uv, i);
		}
		color /= samples;

		o_color = vec4(color, 1);
	}
GLSL);

SRC_FRAG_SSAO :: #run incl(UBO_SCREEN_METRICS, gen_kernel(), UBO_CAMERA_PROPERTIES, UBO_TIME_INFO, #string GLSL
	layout(binding = 6) uniform sampler2D u_noise;

	in vec2 vo_uv;

	float linearize_depth(float depth) {
		float z = depth * 2 - 1; 
		return (2 * u_near * u_far) / (u_far + u_near - z * (u_far - u_near));	
	}

	vec4 texture_s0(sampler2DMS source, vec2 uv) {
		return texelFetch(source, ivec2(uv * u_window_size), 0);
	}

	void main() {
		vec2 noise_scale = u_window_size / 4; 
		vec2 uv = vo_uv;

		float depth = texture_s0(u_depth, uv).x;
		if(depth >= 1.) {
			o_occlusion_raw = 1;
			return;
		}

		vec3 frag_pos = texture_s0(u_position, uv).xyz;
		vec3 normal = texture_s0(u_normal, uv).xyz;
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

			float scene_depth = texture_s0(u_depth, P.xy).x;
			float point_depth = linearize_depth(P.z);
			scene_depth = linearize_depth(scene_depth);

			// float range_check = smoothstep(0, 1, kernel_radius / abs(scene_depth - point_depth));
			float range_check = smoothstep(kernel_radius, 0, abs(scene_depth - point_depth));
			occlusion += (scene_depth < point_depth - kernel_bias ? 1. : 0.) * range_check;
		}
		occlusion = 1 - (occlusion / float(samples_count));
		o_occlusion_raw = occlusion;
	}
GLSL);

SRC_FRAG_BLUR :: #run incl(UBO_SCREEN_METRICS, UBO_TIME_INFO, #string GLSL
	in vec2 vo_uv;
	out vec4 o_color;

	vec4 texture_s0(sampler2DMS source, vec2 uv) {
		return texelFetch(source, ivec2(uv * u_window_size), 0);
	}

	void main() {
		vec2 uv = vo_uv;
		vec2 texture_factor = 1.0 / u_window_size;

		float kernel[4] = float[4](1, 1, 1, 1);
		const float S = 1. / (4 * 4);

		float occlusion = 0;
		float depth = texture_s0(u_depth_0, uv).x;
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
		o_color = vec4(vec3(occlusion), 1);
	}
GLSL);

gen_kernel :: () -> string {
	builder := String_Builder.{allocator = temp};
	KERNEL_SIZE :: 32;
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