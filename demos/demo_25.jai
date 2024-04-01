#import,dir "../core";
#import "Basic"()(MEMORY_DEBUGGER = true);
#import "Math";
#import "GL";

main :: () {
	defer report_memory_leaks();
	init_resources(); defer deinit_resources();
	init_default_graphics(); defer deinit_default_graphics();
	// init_ui(); defer deinit_ui();

	shader_default := compile_shader_vf(VERT_DEFAULT, incl(DSTHEADER_DEFAULT, FRAG_EXTENDED));
	defer deinit(*shader_default);

	loaded_assets := load_assets("./res/shapes.glb");
	defer deinit(*loaded_assets);

	shader_fill_white := compile_shader_vf(VERT_SCREEN_QUAD, FRAG_FILL_WHITE);
	defer deinit(*shader_fill_white);

	texture_model_slices := make_empty_texture_3d(GL_R8, 512);
	defer deinit(*texture_model_slices);

	MODEL_SCALE :: 0.1;
	{
		ubo_slice_camera := make_ubo(UBO_Content_Camera);
		defer deinit(*ubo_slice_camera);

		stencil_texture := make_stencil_texture(texture_model_slices.width, texture_model_slices.height);
		defer deinit(*stencil_texture);

		fbo : u32;
		glGenFramebuffers(1, *fbo);
		defer glDeleteFramebuffers(1, *fbo);


		glBindFramebuffer(GL_FRAMEBUFFER, fbo);
		defer bind_default_target();
		glViewport(0, 0, xx texture_model_slices.width, xx texture_model_slices.height);
		glFramebufferTexture2D(GL_FRAMEBUFFER, GL_DEPTH_STENCIL_ATTACHMENT, stencil_texture.category, stencil_texture.id, 0);

		for z : 0..texture_model_slices.depth-1 {
			zf := z / (cast(float)texture_model_slices.depth - 1);
			glFramebufferTexture3D(GL_FRAMEBUFFER, GL_COLOR_ATTACHMENT0, texture_model_slices.category, texture_model_slices.id, 0, z);

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
						for scale(MODEL_SCALE) {
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

	occlusion_texture := make_empty_texture_3d(GL_RGBA16F, 64);
	defer deinit(*occlusion_texture);

	shader_gen_occlusion := compile_shader_c(COMP_GEN_OCCLUSION, 32, 32);
	defer deinit(*shader_gen_occlusion);


	z_done := 0;

	shader_show_texture := compile_shader_vf(VERT_SCREEN_SPACE, FRAG_SHOW_TEXTURE);
	defer deinit(*shader_show_texture);

	slice_coord := .5;
	glEnable(GL_CULL_FACE);
	for window_cycle() {
		for Events if it.type == {
			case .KEY; using it.key_event;
			if type == .PRESS ifx keycode == {
				case GLFW_KEY_ESCAPE; exit();
				case #char"P"; screenshot();
			}
			// if button == GLFW_MOUSE_BUTTON_LEFT && action == GLFW_PRESS {
			// 	maybe_switch = true;
			// }
		}
		if z_done < occlusion_texture.depth {
			for *shader_gen_occlusion {
				bind(0, texture_model_slices);
				set("u_scale", MODEL_SCALE);
				set("u_target_size", ivec3.{occlusion_texture.width, occlusion_texture.height, occlusion_texture.depth});
				glBindImageTexture(1, occlusion_texture.id, 0, GL_FALSE, 0, GL_READ_WRITE, GL_RGBA16F);
				set("u_offset", ivec3.{0, 0, xx z_done});
				compute(xx occlusion_texture.width, xx occlusion_texture.height, 1);
			}
			z_done += 1;
			print("% / %\n", z_done, occlusion_texture.depth);
		}
		glClearColor(.7, .8, .9, 1);
		glClear(GL_COLOR_BUFFER_BIT | GL_DEPTH_BUFFER_BIT);

		slice_coord = sin(backend_state.current_time) * .5 + .5;
		for *shader_show_texture {
			bind(0, texture_model_slices);
			set("u_slice_resolution", ivec2.{texture_model_slices.width, texture_model_slices.height});
			bind(1, occlusion_texture);
			set("u_slice_coord", slice_coord);
			draw_empty_mesh(6);
		}

		clear_target(GL_DEPTH_BUFFER_BIT);
		// ui_begin();
		// 	float_range(*slice_coord, 0., 1., "z = %");
		// ui_end();

		// if maybe_switch && !ui_state.ui_interacted_this_frame switch_cursor_lock();

		check_gl_error();
	}
}

COMP_GEN_OCCLUSION :: #string GLSL
	uniform layout(binding = 0) sampler3D u_model_slices;
	uniform layout(rgba16f, binding = 1) image3D u_occlusion;
	const float radius = 1.5;
	uniform ivec3 u_target_size;
	uniform float u_scale;
	uniform ivec3 u_offset;

	vec2 hash22(vec2 p) {
		vec3 p3 = fract(vec3(p.xyx) * vec3(.1031, .1030, .0973));
		p3 += dot(p3, p3.yzx+33.33);
		return fract((p3.xx+p3.yz)*p3.zy); 
	}
	vec2 hash23(vec3 p3) {
		p3 = fract(p3 * vec3(.1031, .1030, .0973));
		p3 += dot(p3, p3.yzx+33.33);
		return fract((p3.xx+p3.yz)*p3.zy);
	}
	vec3 hash33(vec3 p3) {
		p3 = fract(p3 * vec3(.1031, .1030, .0973));
		p3 += dot(p3, p3.yxz+33.33);
		return fract((p3.xxy + p3.yxx)*p3.zyx);
	}
	const float PI = 3.14159265;

	vec4 find_occlusion(vec3 p, float r, float r2) {
		const int QUALITY = 10000;
		const int STEPS = 40;
		const int SAMPLES = QUALITY / STEPS;
		float step_size = r / STEPS;

		float occ = 0.;
		float s = 0.;
		vec3 occ_dir = vec3(0);

		for(int i = 0; i < SAMPLES; i++) {
			vec2 h = hash23(p + vec3(0, 0, i));
			float phi = h.x * 2 * PI;
			float ry = h.y * 2 - 1;
			float rr = sqrt(1 - ry * ry);
			vec3 ray = vec3(rr * sin(phi), ry, rr * cos(phi));

			vec3 dp = ray * step_size;

			vec3 pij = p;// + (hash33(p) * 2 - 1) * r2;
			int j = 0;
			for(int j = 0; j < STEPS; j++) {
				pij += dp;
				if(texture(u_model_slices, pij).r > .5) {
					float occi = (STEPS - j) / float(STEPS);
					occ_dir += occi * ray;
					occ += occi;
					break;
				}
			}
			s += 1;
		}

		occ /= s;
		occ = pow(occ, .5);
		return vec4(1 - occ, occ * normalize(occ_dir));
	}

	void main() {
		ivec3 size = u_target_size;
		ivec3 p0 = ivec3(gl_GlobalInvocationID.xyz) + u_offset;
		if(p0.x >= size.x || p0.y >= size.y || p0.z >= size.z) return;

		vec3 uv = p0 / vec3(size - 1);

		imageStore(u_occlusion, p0, find_occlusion(uv, radius * u_scale, .5 / size.x));
	}
GLSL

VERT_SCREEN_SPACE :: #string GLSL
	out vec2 vo_uv;
	void main() {
		float points[12] = float[12](0, 0, 1, 1, 0, 1, 0, 0, 1, 0, 1, 1);
		vec2 _uv = vec2(points[gl_VertexID << 1], points[(gl_VertexID << 1) | 1]);
		vo_uv = vec2(_uv.x, 1 - _uv.y);
		gl_Position = vec4(_uv * 2 - 1, 0, 1);
	}
GLSL
FRAG_SHOW_TEXTURE :: #run incl(UBO_SCREEN_METRICS, #string GLSL
	uniform layout(binding = 0) sampler3D u_model_slices;
	uniform ivec2 u_slice_resolution;
	uniform layout(binding = 1) sampler3D u_occlusion;
	uniform float u_slice_coord;

	vec4 tex(vec2 uv) {
		return texture(u_model_slices, vec3(uv, u_slice_coord));
	}

	in vec2 vo_uv;
	out vec4 o_color;
	void main() {
		vec2 uv = ((vo_uv * 2 - 1) * vec2(u_width_over_height, -1)) * .5 + .5;
		if(uv.x > 0 && uv.x < 1) {
			float occ = texture(u_occlusion, vec3(uv, u_slice_coord)).x;
			occ = 1 - pow(1 - occ, 2);
			o_color = vec4(occ, occ, occ, 1);
			vec3 e = vec3(1. / u_slice_resolution, 0);
			vec4  c0 = tex(uv).rrrr;
			vec4 c1;
			c1.y = tex(uv - e.xz).r;
			c1.x = tex(uv + e.xz).r;
			c1.z = tex(uv + e.zy).r;
			c1.w = tex(uv - e.zy).r;
			if(length(c0 - c1) > 0) {
				o_color = vec4(1, 0, 1, 1);
			}
		} else {
			discard;
		}
	}
GLSL);

FRAG_FILL_WHITE :: #string GLSL
	out vec4 o_color;

	void main() {
		o_color = vec4(1);
	} 
GLSL