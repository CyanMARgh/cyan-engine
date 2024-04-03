#import,dir "../core";
#import "Basic"()(MEMORY_DEBUGGER = true);
#import "GL";
#import "Math";
 
main :: () {
	defer report_memory_leaks();
	init_resources(); defer deinit_resources();
	// gl_enable_debug_output(true);

	{
		s : s32;
		glGetIntegerv(GL_MAX_3D_TEXTURE_SIZE, *s);
		print("s = %\n", s);
		glGetIntegerv(GL_MAX_TEXTURE_SIZE, *s);
		print("s = %\n", s);
	}

	init_default_graphics(); defer deinit_default_graphics();

	shader_default := compile_shader_vf(VERT_DEFAULT, incl(DSTHEADER_DEFAULT, FRAG_EXTENDED));
	defer deinit(*shader_default);
	loaded_assets := load_assets("./res/shapes.glb");
	defer deinit(*loaded_assets);

	shader_fill_white := compile_shader_vf(VERT_SCREEN_QUAD, FRAG_FILL_WHITE);
	defer deinit(*shader_fill_white);


	// shader_prerender_slice := compile_shader_vf(VERT_SCREEN_QUAD, FRAG_PRERENDER_SLICE);
	// defer deinit(*shader_prerender_slice);
	shader_screen_pass := compile_shader_vf(VERT_SCREEN_QUAD, FRAG_SHOW_3D_TEXTURE);
	defer deinit(*shader_screen_pass);
	shader_volume_cubes := compile_shader_vf(VERT_VOXEL, FRAG_SHOW_NORMAL);
	defer deinit(*shader_volume_cubes);


	tex3d := make_empty_texture_3d(GL_R8, 100);
	defer deinit(*tex3d);

	{
		ubo_slice_camera := make_ubo(UBO_Content_Camera);
		defer deinit(*ubo_slice_camera);

		stencil_texture := make_stencil_texture(tex3d.width, tex3d.height);
		defer deinit(*stencil_texture);

		fbo : u32;
		glGenFramebuffers(1, *fbo);
		defer glDeleteFramebuffers(1, *fbo);


		glBindFramebuffer(GL_FRAMEBUFFER, fbo);
		glViewport(0, 0, xx tex3d.width, xx tex3d.height);
		glFramebufferTexture2D(GL_FRAMEBUFFER, GL_DEPTH_STENCIL_ATTACHMENT, stencil_texture.category, stencil_texture.id, 0);

		for z : 0..tex3d.depth-1 {
			zf := z / (cast(float)tex3d.depth - 1);
			glFramebufferTexture3D(GL_FRAMEBUFFER, GL_COLOR_ATTACHMENT0, tex3d.category, tex3d.id, 0, z);

			glClearColor(0, 0, 0, 1);
			glClear(GL_COLOR_BUFFER_BIT | GL_DEPTH_BUFFER_BIT | GL_STENCIL_BUFFER_BIT);

			{
				mat_t := Matrix4.{
					1, 0, 0, 0,
					0, 1, 0, 0,
					0, 0, 1, 0,
					0, 0, 0, 1
				};
				mat_r := Matrix4_Identity;
				FAR := 100.;
				NEAR := 0.;
				mat_p := Matrix4.{
					1, 0, 0, 0,
					0, 1, 0, 0,
					0, 0, -2/(FAR-NEAR), -(FAR+NEAR)/(FAR-NEAR),
					0, 0, 0, 1
				};

				ubo_content_projection_camera := UBO_Content_Camera.{
					transpose(mat_t), transpose(mat_r), transpose(mat_p),
					transpose(mat_t * mat_r * mat_p),
					0, 0,
					1,
					.{0, 0, 0}
				};
				set_value(*ubo_slice_camera, ubo_content_projection_camera);
			}

			bind(1, ubo_slice_camera);
			defer bind(1, graphics_state.ubo_default_camera);
			{
				glColorMask(GL_FALSE, GL_FALSE, GL_FALSE, GL_FALSE);

				glEnable(GL_STENCIL_TEST);
				defer glDisable(GL_STENCIL_TEST);

				glStencilFunc(GL_ALWAYS, 0, 0xFF);
				glStencilOp(GL_KEEP, GL_KEEP, GL_INCR);

				for *shader_default {
					for translate(.{0, 0, zf * 2 - 1}) {
						for scale(.10) {
						 	draw_all_roots(loaded_assets);
						}
					}
				}
				glColorMask(GL_TRUE, GL_TRUE, GL_TRUE, GL_TRUE);

				glStencilFunc(GL_EQUAL, 1, 0x01);
				glStencilOp(GL_KEEP, GL_KEEP, GL_KEEP);

				for *shader_fill_white {
					draw_empty_mesh(6);
				}
			}
		}
	}
	bind_default_target();

	check_gl_error();

	glEnable(GL_DEPTH_TEST);
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

		use(*shader_volume_cubes);
			bind(0, tex3d);

			set(*shader_volume_cubes, "u_dimensions", .{tex3d.width, tex3d.height, tex3d.depth});
			for scale(2) {
				set_model_transform(graphics_state.scene_translation);
				draw_empty_mesh(xx(tex3d.width * tex3d.height * tex3d.depth * 36));
			}
		// use(*shader_screen_pass);
		// 	glActiveTexture(GL_TEXTURE0 + 0);
		// 	glBindTexture(tex3d.category, tex3d.id);

		// 	draw_empty_mesh(6);
		check_gl_error();
	}
}

FRAG_PRERENDER_SLICE :: #run incl(UBO_TIME_INFO, UBO_SCREEN_METRICS, #string GLSL
	in vec2 vo_uv;
	out vec4 o_color;

	uniform float u_depth;

	void main() {
		o_color = vec4(length(vec3(vo_uv, u_depth) * 2 - 1) <= 1 ? 1 : 0);
		// o_color = vec4(1);
	}
GLSL);

FRAG_SHOW_3D_TEXTURE :: #run incl(UBO_TIME_INFO, UBO_SCREEN_METRICS, #string GLSL
	in vec2 vo_uv;
	out vec4 o_color;

	layout(binding = 0) uniform sampler3D u_test_texture;

	void main() {
		vec2 uv = vo_uv - .5;
		uv.x *= u_width_over_height;
		uv += .5;
		if(uv.x < 0 || uv.x > 1) discard;
		o_color = vec4(texture(u_test_texture, vec3(uv, fract(u_time))).xyz, 1);
	}
GLSL);

VERT_VOXEL :: #run incl(UBO_CAMERA_PROPERTIES, UBO_MAT_M, VERTICE_INTERFACE_OUT, #string GLSL
	uniform ivec3 u_dimensions;
	layout(binding = 0) uniform sampler3D u_test_texture;	

	Input_Vertice gen_cube_vertice() {
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
		vec3 point = points[indices[gl_VertexID % 36]];
		vec3 normal = normals[(gl_VertexID / 3) % 6];
		return Input_Vertice(point, normal, vec2(0));
	}

	Input_Vertice gen_vertice() {
		Input_Vertice vertice = gen_cube_vertice();
		int ii = gl_VertexID / 36;
		vec3 offset = vec3(
			ii % u_dimensions.x,
			(ii / u_dimensions.x) % u_dimensions.y,
			ii / (u_dimensions.x * u_dimensions.y)
		);
		vec3 texcoord = (offset + .5) / u_dimensions;

		vec3 scale = texture(u_test_texture, texcoord).r / u_dimensions;
		//texture(u_test_texture, texcoord).r;

		vertice.position = vertice.position * scale * .9 + (texcoord * 2 - 1);
		return vertice;
	}
GLSL);

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

FRAG_FILL_WHITE :: #string GLSL
	out vec4 o_color;

	void main() {
		o_color = vec4(1);
	} 
GLSL