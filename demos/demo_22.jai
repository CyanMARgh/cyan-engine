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
	loaded_assets := load_assets("./res/shapes.glb");
	defer deinit(*loaded_assets);

	shader_draw_white := compile_shader_vf(VERT_DEFAULT, FRAG_FILL_WHITE);
	defer deinit(*shader_draw_white);
	shader_fill_white := compile_shader_vf(VERT_SCREEN_QUAD, FRAG_FILL_WHITE);
	defer deinit(*shader_fill_white);

	init_ui(); defer deinit_ui();

	z_offset := 0.0;

	// UBO_Content_Camera :: struct {
	// 	mat_t, mat_r, mat_p : Matrix4;
	// 	mat_trp : Matrix4;

	// 	near, far : float;
	// 	width_over_height : float;
	// 	eye : Vector3 #align 16;
	// }

	ubo_slice_camera := make_ubo(UBO_Content_Camera);
	defer deinit(*ubo_slice_camera);


	// glEnable(GL_CULL_FACE);
	for window_cycle() {
		maybe_switch := false;
		for Events if it.type == {
			case .KEY; using it.key_event;
			if type == .PRESS ifx keycode == {
				case GLFW_KEY_ESCAPE; exit();
				case #char"P"; screenshot();
			}
			case .MOUSE_BUTTON; using it.mouse_button_event;
			if button == GLFW_MOUSE_BUTTON_LEFT && action == GLFW_PRESS {
				maybe_switch = true;
			}
		}
		update_default_camera();

		glClearColor(.7, .8, .9, 1);
		// glClearStencil(0);
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
			scale := 0.18;
			mat_p := Matrix4.{
				backend_state.window_metrics.height_over_width, 0, 0, 0,
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

		{
			bind(1, ubo_slice_camera);
			defer bind(1, graphics_state.ubo_default_camera);
			
			glEnable(GL_STENCIL_TEST);
			defer glDisable(GL_STENCIL_TEST);

			glStencilFunc(GL_ALWAYS, 0, 0xFF);
			glStencilOp(GL_KEEP, GL_KEEP, GL_INCR);

			for *shader_default {
				for translate(.{0, 0, z_offset}) {
					for scale(.17) {
					 	draw_all_roots(loaded_assets);
					}
				}
			}

			glStencilFunc(GL_EQUAL, 1, 0x01);
			glStencilOp(GL_KEEP, GL_KEEP, GL_KEEP);

			for *shader_fill_white {
				draw_empty_mesh(6);
			}


			// glClearColor(1., 1., 1., 1.);
			// glClear(GL_COLOR_BUFFER_BIT);
		}

		// glClearStencil(0);
		// glStencilMask(0xFF);
		// // glEnable(GL_DEPTH_TEST);

		// glEnable(GL_STENCIL_TEST);
		// glDepthMask(GL_FALSE);
		// {
			// bind(1, ubo_slice_camera);
			// defer bind(1, graphics_state.ubo_default_camera);

		// 	glStencilFunc(GL_ALWAYS, 1, 0xff);
		// 	glStencilOpSeparate(GL_FRONT, GL_KEEP, GL_INCR_WRAP, GL_KEEP);
		// 	glStencilOpSeparate(GL_FRONT, GL_KEEP, GL_DECR_WRAP, GL_KEEP);

		// 	for *shader_default {
		// 		for translate(.{0, 0, z_offset}) draw_all_roots(loaded_assets);
		// 	}
		// }
		// glClear(GL_COLOR_BUFFER_BIT | GL_DEPTH_BUFFER_BIT);

		// glStencilOp(GL_KEEP, GL_KEEP, GL_KEEP);
		// // glColorMask(GL_TRUE, GL_TRUE, GL_TRUE, GL_TRUE);
		// glStencilFunc(GL_EQUAL, 1, 0xFF);

		// // glStencilFunc(GL_NOTEQUAL, 1, 0xFF);
		// // glStencilMask(0x00);
		// for *shader_fill_white {
		// 	draw_empty_mesh(6);
		// }

		// glDepthMask(GL_TRUE);
		// glDisable(GL_STENCIL_TEST);


		// glDisable(GL_DEPTH_TEST);

		// glClearColor(.7, .8, .9, 1);
		// glClear(GL_COLOR_BUFFER_BIT | GL_DEPTH_BUFFER_BIT | GL_STENCIL_BUFFER_BIT);

		// glEnable(GL_DEPTH_TEST);
		// glDepthFunc(GL_LESS);
		// glEnable(GL_STENCIL_TEST);
		// glStencilOp(GL_KEEP, GL_KEEP, GL_REPLACE);

		// glStencilFunc(GL_ALWAYS, 1, 0xff);
		// glStencilMask(0xff);

		// for *shader_default {
		// 	for translate(.{0, y_offset, 0}) draw_all_roots(loaded_assets);
		// }

		// glStencilFunc(GL_NOTEQUAL, 1, 0xFF);
		// glStencilMask(0x00);

		// for *shader_fill_white {
		// 	for translate(.{0, y_offset, 0}) {
		// 		for scale(1.1) {
		// 			draw_all_roots(loaded_assets);
		// 		}
		// 	}
		// }

		// glStencilMask(0xff);
		// glStencilFunc(GL_ALWAYS, 0, 0xff);

		// glDisable(GL_DEPTH_TEST);
		
		clear_target(GL_DEPTH_BUFFER_BIT);
		ui_begin();
			float_range(*z_offset, -0.45, 0.45, "z = %");
		ui_end();

		if maybe_switch && !ui_state.ui_interacted_this_frame switch_cursor_lock();
	}
}
#scope_file

FRAG_FILL_WHITE :: #string GLSL
	out vec4 o_color;

	void main() {
		o_color = vec4(1);
	} 
GLSL