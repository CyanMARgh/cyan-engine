#import,dir "../core";
#import "Basic"()(MEMORY_DEBUGGER = true);
#import "Math";
#import "GL";
#import "Random";

METHODS :: enum u8 { OLD; NEW; NEW_2; };
METHOD :: METHODS.NEW_2;
SHOW_ZONES :: true;

main :: () {
	defer report_memory_leaks();
	init_resources(); defer deinit_resources();
	init_default_graphics(); defer deinit_default_graphics();

	fb_gbuffer := make_framebuffer(1280, 720, 
		.{"depth", .DEPTH, GL_DEPTH_COMPONENT32},
		.{"color", .COLOR, GL_RGB8},
		.{"normal", .COLOR, GL_RGB16F},
		.{"position", .COLOR, GL_RGB16F}
	);
	defer deinit(*fb_gbuffer);

	shader_default := compile_shader_vf(VERT_DEFAULT, incl(dstheader(fb_gbuffer), FRAG_EXTENDED));
	defer deinit(*shader_default);

	#if METHOD == .OLD {
		shader_apply_light_simple := compile_shader_vf(VERT_SCREEN_QUAD, incl(srcheader(fb_gbuffer), FRAG_APPLY_LIGHT_SIMPLE));
		defer deinit(*shader_apply_light_simple);
	} else {
		shader_copy_depth := compile_shader_vf(VERT_SCREEN_QUAD, incl(srcheader(fb_gbuffer), FRAG_COPY_DEPTH));
		defer deinit(*shader_copy_depth);		
	}

	shader_light_points := compile_shader_vf(VERT_LIGHT_POINT, FRAG_LIGHT_POINT);
	defer deinit(*shader_light_points);
	shader_light_zones_debug := compile_shader_vf(VERT_LIGHT_ZONE, incl(FRAG_LIGHT_ZONE_DEBUG));
	defer deinit(*shader_light_zones_debug);
	shader_light_zones := compile_shader_vf(VERT_LIGHT_ZONE, incl(srcheader(fb_gbuffer), FRAG_LIGHT_ZONE));
	defer deinit(*shader_light_zones);

	shader_grid := compile_shader_vf(VERT_PLANE, incl(dstheader(fb_gbuffer), FRAG_GRID));

	loaded_assets := load_assets("./res/helmet/DamagedHelmet.gltf");
	defer deinit(*loaded_assets);

	Point_Source :: struct {
		center : Vector3 #align 16;
		range : float;
		color : Vector3 #align 16;
		brightness : float;
	};

	#if METHOD == .OLD || SHOW_ZONES {
		NUM_LIGHTS :: 75;		
	} else #if METHOD == .NEW {
		NUM_LIGHTS :: 8000;
	} else {
		NUM_LIGHTS :: 28000;		
	}

	colors := NewArray(NUM_LIGHTS, Vector3);
	defer array_free(colors);
	 // [NUM_LIGHTS]Vector3;

	phis := NewArray(NUM_LIGHTS, float);
	defer array_free(phis);
	rads := NewArray(NUM_LIGHTS, float);
	defer array_free(rads);
	yfreqs := NewArray(NUM_LIGHTS, float);
	defer array_free(yfreqs);
	yphases := NewArray(NUM_LIGHTS, float);
	defer array_free(yphases);

	// phis, rads, yfreqs, yphases : [NUM_LIGHTS]float;

	for * rads it.* = pow(random_get_within_range(1, NUM_LIGHTS / 4), 0.5);
	for * phis it.* = random_get_within_range(0, PI * 2);
	for * yfreqs it.* = random_get_within_range(1, 2);
	for * yphases it.* = random_get_within_range(0, PI * 2);
	for * colors { 
		it.* = .{random_get_within_range(0, 1), random_get_within_range(0, 1), random_get_within_range(0, 1)};
		it.* /= max(it.x, it.y, it.z);
	}

	ssbo_light := make_ssbo_dynamic(Point_Source, NUM_LIGHTS);
	defer deinit(*ssbo_light);

	graphics_state.default_camera.linear_speed *= .3;

	glEnable(GL_CULL_FACE);
	check_gl_error();
	for window_cycle(print_statistical_fps = true, fps_log_period = 100) {
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
	
		for i : 0..NUM_LIGHTS-1 {
			phi := phis[i];
			R := rads[i];
			push(*ssbo_light, .{.{R * sin(phi), (sin(yphases[i] + yfreqs[i] * current_time) * .5 + .5) * 3 - 1, R * cos(phi)}, 1., colors[i], 1});
		}
		commit(*ssbo_light);

		set_size(*fb_gbuffer, backend_state.window_metrics.size);

		bind_as_target(fb_gbuffer);
			clear_target(GL_COLOR_BUFFER_BIT | GL_DEPTH_BUFFER_BIT, .[.7, .8, .9, 1], .[0, 0, 0, 0], .[0, 0, 0, 0]);

			glEnable(GL_DEPTH_TEST);
				use(*shader_default);
					draw_all_roots(loaded_assets);
				for translate(.{0, -1, 0}) {
					for scale(.{100, 1, 100}) {
						use(*shader_grid);
							set_model_transform(graphics_state.scene_translation);
							draw_empty_mesh(6);
					}
				}
			glDisable(GL_DEPTH_TEST);

		bind_default_target();
			clear_target(GL_DEPTH_BUFFER_BIT | GL_COLOR_BUFFER_BIT);
			glEnable(GL_DEPTH_TEST);
			// glDepthMask(GL_TRUE);
			#if METHOD != .OLD {
				use(*shader_copy_depth);
					// bind(5, ssbo_light);
					bind_as_source(fb_gbuffer);				
			} else {
				use(*shader_apply_light_simple);
					bind(5, ssbo_light);
					bind_as_source(fb_gbuffer);
			}
			draw_empty_mesh(6);

			#if METHOD != .OLD {
				#if SHOW_ZONES {
					glPolygonMode(GL_FRONT_AND_BACK, GL_LINE);
					glEnable(GL_CULL_FACE);
					for *shader_light_zones_debug {
						#if METHOD == .NEW {
							set("u_rows", cast(u32)10);
							set("u_columns", cast(u32)10);
							bind(5, ssbo_light);
							draw_empty_mesh_instanced(10 * 10 * 6, NUM_LIGHTS);
						} else {
							draw_empty_mesh_instanced(36, NUM_LIGHTS);						
						}
					}
					glPolygonMode(GL_FRONT_AND_BACK, GL_FILL);					
				}

				glDepthFunc(GL_GREATER);
				glCullFace(GL_FRONT);
				glDepthMask(GL_FALSE);
				glEnable(GL_BLEND);
				glBlendFunc(GL_SRC_ALPHA, GL_ONE);

				for *shader_light_zones {
					bind(5, ssbo_light);
					bind_as_source(fb_gbuffer);
					#if METHOD == .NEW {
						set("u_rows", cast(u32)10);
						set("u_columns", cast(u32)10);
						draw_empty_mesh_instanced(10 * 10 * 6, NUM_LIGHTS);
					} else {
						draw_empty_mesh_instanced(36, NUM_LIGHTS);						
					}
				}

				glDisable(GL_BLEND);
				glDepthMask(GL_TRUE);
				glCullFace(GL_BACK);
				glDepthFunc(GL_LESS);

			}
			for *shader_light_points {
				bind(5, ssbo_light);
				bind_as_source(fb_gbuffer);
				draw_empty_mesh_instanced(36, NUM_LIGHTS);
			}
			glDisable(GL_DEPTH_TEST);

		check_gl_error();
	}
}

FRAG_COPY_DEPTH :: #run incl(UBO_TIME_INFO, UBO_CAMERA_PROPERTIES, #string GLSL
	in vec2 vo_uv;
	out vec4 o_color;

	void main() {
		vec2 uv = vo_uv;
		gl_FragDepth = texture(u_depth, uv).x;
	}
GLSL);

FRAG_APPLY_LIGHT_SIMPLE :: #run incl(UBO_TIME_INFO, UBO_CAMERA_PROPERTIES, #string GLSL
	in vec2 vo_uv;

	in struct Point_Source {
		vec3 center;
		float range;
		vec3 color;
		float brightness;
	} vo;

	vec3 get_light(in vec3 base_color, in vec3 pos, in vec3 normal, in Point_Source source) {
		float ls = length(source.center - pos) / source.range;

		float att = 1 - smoothstep(0.5, 1., ls);

		return base_color * source.color * source.brightness * att;
	}

	out vec4 o_color;

	layout(std430, binding = 5) buffer ssbo_light {
		uint u_point_sources_count;
		Point_Source u_point_sources[];
	};

	void main() {
		vec2 uv = vo_uv;
		vec3 color = texture(u_color, uv).xyz;
		vec3 normal = texture(u_normal, uv).xyz;
		vec3 pos = texture(u_position, uv).xyz;

		vec3 result = vec3(0);
		for(int i = 0; i < u_point_sources_count; i++) {
			result += get_light(color, pos, normal, u_point_sources[i]);
		}

		o_color = vec4(result, 1);
		gl_FragDepth = texture(u_depth, uv).x;
	}
GLSL);

VERT_LIGHT_POINT :: #run incl(UBO_CAMERA_PROPERTIES, #string GLSL
	struct Point_Source {
		vec3 center;
		float range;
		vec3 color;
		float brightness;
	};
	layout(std430, binding = 5) buffer ssbo_light {
		uint u_point_sources_count;
		Point_Source u_point_sources[];
	};

	vec3 gen_vertice_cube() {
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
		return points[indices[gl_VertexID]];
	}

	out vec3 vo_color;

	const float point_size = 0.05;
	void main() {
		vec3 pos = gen_vertice_cube() * point_size + u_point_sources[gl_InstanceID].center;
		gl_Position = u_mat_trp * vec4(pos, 1);
		vo_color = u_point_sources[gl_InstanceID].color;
	}
GLSL);
FRAG_LIGHT_POINT :: #run incl(DSTHEADER_DEFAULT, UBO_CAMERA_PROPERTIES, UBO_SCREEN_METRICS,  #string GLSL
	in vec3 vo_color;

	void main() {
		o_color = vec4(vo_color, 1);
	}
GLSL);
FRAG_LIGHT_ZONE :: #run incl(DSTHEADER_DEFAULT, UBO_CAMERA_PROPERTIES, UBO_SCREEN_METRICS,  #string GLSL
	in struct Point_Source {
		vec3 center;
		float range;
		vec3 color;
		float brightness;
	} vo;

	vec3 get_light(in vec3 base_color, in vec3 pos, in vec3 normal, in Point_Source source) {
		float ls = length(source.center - pos) / source.range;
		// float att = 1. / (1 + ls * 1.7 + ls * ls * 20);

		float att = 1 - smoothstep(0.5, 1., ls);

		return base_color * source.color * source.brightness * att;
	}

	void main() {
		vec2 uv = (gl_FragCoord.xy) / u_window_size;
		vec3 color = texture(u_color, uv).xyz;
		vec3 normal = texture(u_normal, uv).xyz;
		vec3 pos = texture(u_position, uv).xyz;
		float depth = texture(u_depth, uv).x;

		vec3 total_light = get_light(color, pos, normal, vo);
		o_color = vec4(total_light, 1);
	}
GLSL);

FRAG_LIGHT_ZONE_DEBUG :: #run incl(DSTHEADER_DEFAULT, UBO_CAMERA_PROPERTIES, UBO_SCREEN_METRICS,  #string GLSL
	in struct Point_Source {
		vec3 center;
		float range;
		vec3 color;
		float brightness;
	} vo;

	void main() {
		o_color = vec4(vo.color, 1);
	}
GLSL);

#if METHOD == .NEW {
VERT_LIGHT_ZONE :: #run incl(UBO_CAMERA_PROPERTIES, #string GLSL
	struct Point_Source {
		vec3 center;
		float range;
		vec3 color;
		float brightness;
	};
	layout(std430, binding = 5) buffer ssbo_light {
		uint u_point_sources_count;
		Point_Source u_point_sources[];
	};

	out struct Point_Source {
		vec3 center;
		float range;
		vec3 color;
		float brightness;
	} vo;

	uniform uint u_rows;
	uniform uint u_columns;
	const float PI = 3.14159265359;

	vec3 gen_vertice_sphere() {
		uint subid = gl_VertexID % 6;
		uint quad_column = (gl_VertexID / 6) % u_columns;
		uint quad_row = gl_VertexID / (6 * u_columns);
		uint offsets[12] = uint[12](0, 1, 0, 0, 1, 1, 0, 1, 1, 1, 1, 2);
		uint row = quad_row + offsets[subid << 1];
		uint column = quad_column + offsets[(subid << 1) | 1];

		vec2 uv = vec2(float(column) / float(u_columns), float(row) / float(u_rows));
		float yaw = 2 * PI * uv.x;
		float pitch = PI * uv.y;

		return vec3(sin(yaw) * sin(pitch), cos(pitch), cos(yaw) * sin(pitch));
	}

	void main() {
		Point_Source ps = u_point_sources[gl_InstanceID];
		vec3 pos = gen_vertice_sphere() * ps.range * 2. + ps.center;
		gl_Position = u_mat_trp * vec4(pos, 1);
		vo = ps;
	}
GLSL);
} else {
VERT_LIGHT_ZONE :: #run incl(UBO_CAMERA_PROPERTIES, #string GLSL
	struct Point_Source {
		vec3 center;
		float range;
		vec3 color;
		float brightness;
	};
	layout(std430, binding = 5) buffer ssbo_light {
		uint u_point_sources_count;
		Point_Source u_point_sources[];
	};

	out struct Point_Source {
		vec3 center;
		float range;
		vec3 color;
		float brightness;
	} vo;

	uniform uint u_rows;
	uniform uint u_columns;
	const float PI = 3.14159265359;

	vec3 gen_vertice_cube() {
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
		return points[indices[gl_VertexID]];
	}

	void main() {
		Point_Source ps = u_point_sources[gl_InstanceID];
		vec3 pos = gen_vertice_cube() * ps.range + ps.center;
		gl_Position = u_mat_trp * vec4(pos, 1);
		vo = ps;
	}
GLSL);
}
FRAG_GRID :: #string GLSL
	in struct VO {
		vec3 position;
		vec3 normal;
		vec2 uv_0;
	} vo;

	void main() {
		vec2 uv_0 = vo.uv_0;
		vec3 base_color = vec3(.1, .1, .2);
		vec3 bright_color = vec3(.8, .8, .7);
		vec2 guv = fract(uv_0 * 200);
		guv = min(1 - guv, guv);
		float h = 1/(1 / guv.x + 1 / guv.y);
		float t = exp(-h * 40);
		vec3 result_color = mix(base_color, bright_color, t);

		#ifdef O_COLOR
			o_color = result_color;
		#else
			#ifdef O_COLOR4
				o_color = vec4(result_color, .7);
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
		#ifdef O_METALLIC_ROUGHNESS
			o_metallic_roughness = vec3(0);
		#endif
		#ifdef O_EMISSIVE
			o_emissive = vec3(0);
		#endif
	}
GLSL;