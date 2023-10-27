GL_REQUIRED_VERSION_MAJOR :: 4;
GL_REQUIRED_VERSION_MINOR :: 3;

init_resources :: (initial_size := ivec2.{1280, 720}) {
	print("\e[0m");
	glfwInit();
	glfwWindowHint(GLFW_SAMPLES, 4);
	glfwWindowHint(GLFW_CONTEXT_VERSION_MAJOR, 4);
	glfwWindowHint(GLFW_CONTEXT_VERSION_MINOR, 3);
	glfwWindowHint(GLFW_OPENGL_PROFILE, GLFW_OPENGL_CORE_PROFILE);

	refresh_window_size(initial_size.x, initial_size.y);
	window = glfwCreateWindow(initial_size.x, initial_size.y, "CE3", null, null);
	if !window {
		print("Failed to create GLFW window\n");
		glfwTerminate();
		exit(-1);
	}

	glfwMakeContextCurrent(window);

	glEnable(GL_MULTISAMPLE);
	glEnable(GL_TEXTURE_CUBE_MAP_SEAMLESS);
	gl_load(*gl);
	glViewport(0, 0, xx initial_size.x, xx initial_size.y);
	framebuffer_size_callback :: (window : *GLFWwindow, width : s32, height : s32) #c_call {
		glViewport(0, 0, xx width, xx height);
		refresh_window_size(width, height);
		window_resized_this_frame = true;
	}
	glfwSetFramebufferSizeCallback(window, framebuffer_size_callback);  
	key_callback :: (window : *GLFWwindow, keycode : s32, scancode : s32, action : s32, mode : s32) #c_call {
		if action == GLFW_PRESS {
			keys_down[keycode] = true;
		} else if action == GLFW_RELEASE {
			keys_down[keycode] = false;
		}
		push_context ctx {
			push(*window_events, .{
				type = .KEY,
				key_event = .{
					keycode = keycode,
					type = ifx action == GLFW_PRESS then .PRESS 
					else ifx action == GLFW_RELEASE then .RELEASE else .UNKNOWN
				}
			});
		}
	}
	glfwSetKeyCallback(window, key_callback);
	mouse_callback :: (window : *GLFWwindow, xpos : float64, ypos : float64) #c_call {
		new_cursor_position = Vector2.{xx xpos, xx ypos};
	}
	glfwSetCursorPosCallback(window, mouse_callback);
	mouse_button_callback :: (window : *GLFWwindow, button : s32, action : s32, mods : s32) #c_call {
		if action == 1 {
			mouse_buttons_down[button] = true;
			mouse_buttons_pressed[button] = true;
		} else if action == 0 {
			mouse_buttons_down[button] = false;
			mouse_buttons_released[button] = true;
		}
		push_context ctx {
			push(*window_events, .{
				type = .MOUSE_BUTTON,
				mouse_button_event = .{
					button = button,
					action = action,
					mods = mods
				}
			});
			// if button == GLFW_MOUSE_BUTTON_LEFT {
			// 	if action == GLFW_PRESS {
			// 		backend_state.left_mouse_state = .DOWN;
			// 	} else if action == GLFW_RELEASE {
			// 		backend_state.left_mouse_state = .DOWN;
			// 	}
			// }

			//TODO update mouse button state in backend_state
			// print("mbe = %\n", action);
		}
	}
	glfwSetMouseButtonCallback(window, mouse_button_callback);
}
deinit_resources :: () {
	glfwTerminate();
	deinit(*window_events);
}
Window_Cycle :: struct { 
	print_statistical_fps := false;
	fps_log_period := 100;
	target_fps := 60;
	capture_video := false;
}
window_cycle :: (
	print_statistical_fps := false,
	fps_log_period := 100,
	target_fps := 60,
	capture_video := false
) -> Window_Cycle {
	return .{
		print_statistical_fps,
		fps_log_period,
		target_fps,
		capture_video
	};
}

for_expansion :: (using window_cycle : Window_Cycle, $body : Code, flags : For_Flags) #expand {
	`it, `it_index := 0;
	`exit :: () {
		glfwSetWindowShouldClose(window, 1);		
	}
	`Events : struct {};
	`for_expansion :: (events : type_of(Events), $body : Code, flags : For_Flags) #expand {
		for :process window_events {
			`it, `it_index := it, it_index;
			#insert body;
		}
	}
	need_screenshot := false;
	screenshot_name := "";
	`screenshot :: (_screenshot_name := "") #expand {
		need_screenshot = true;
		screenshot_name = _screenshot_name;
	}

	cycle_length := 1000. * 2 * PI;
	backend_state.target_delta_time, backend_state.delta_time = 1. / target_fps;
	backend_state.current_time = 0.;

	ffmpeg : FFMPEG;
	frame : Frame; defer clear(frame);
	frame.bytes = alloc(1920 * 1080 * 4);
	if capture_video {
		filename := tprint("screenshots/capture_%.mp4", calendar_to_string(to_calendar(current_time_consensus())));
		ffmpeg = ffmpeg_start_rendering(1280, 720, filename = filename, fps = target_fps);
	}
	defer if capture_video ffmpeg_end_rendering(*ffmpeg);

	ubo_window_metrics = make_ubo_initialized(window_metrics);
	bind(0, ubo_window_metrics);
	ubo_time_info = make_ubo_initialized(time_info);
	bind(3, ubo_time_info);

	make_directory_if_it_does_not_exist("screenshots");
	is_first_frame = true;
	last_measured_time := current_time_monotonic();

	frame_counter := 0;
	last_checkpoint_time := 0.;

	while !glfwWindowShouldClose(window) {
		// for check_time() 
		{
			for * mouse_buttons_pressed it.* = false;
			for * mouse_buttons_released it.* = false;
			glfwPollEvents();
			cursor_delta = new_cursor_position - cursor_position;			
			cursor_position = new_cursor_position;
			if lmb_pressed() {
				dragg_start = backend_state.cursor_position;
			}

			set_value(*ubo_window_metrics, window_metrics);
			set_value(*ubo_time_info, time_info);

			`delta_time := backend_state.delta_time;
			`current_time := backend_state.current_time;
			#insert body;			
			glFlush();
		}

		// for check_time() 
		{
			glfwSwapBuffers(window);
		}

		if need_screenshot || capture_video {
			fill_frame_with_screenshot(*frame);
			if capture_video {
				ffmpeg_scale_and_send_frame(*ffmpeg, *frame);
			}
			if need_screenshot {
				filename := ifx screenshot_name
					then tprint("screenshots/%.png\0", screenshot_name)
					else tprint("screenshots/screenshot_%.png\0", calendar_to_string(to_calendar(current_time_consensus())));
				stbi_write_png(xx filename.data, xx frame.width, xx frame.height, 4, xx frame.bytes, xx (frame.width * 4));
				need_screenshot = false;
			}
		}
		reset_temporary_storage();

		new_measured_time := current_time_monotonic();
		if capture_video {
			backend_state.delta_time = 1. / target_fps;
		} else {
			backend_state.delta_time = xx to_float64_seconds(new_measured_time - last_measured_time);
		}
		last_measured_time = new_measured_time;
		backend_state.current_time = fmod_cycling(backend_state.current_time + backend_state.delta_time, cycle_length);

		if print_statistical_fps {
			frame_counter += 1;
			if frame_counter == fps_log_period {
				frame_counter = 0;
				delay := backend_state.current_time - last_checkpoint_time;
				last_checkpoint_time = backend_state.current_time;
				print("fps = %\n", fps_log_period / delay);
			}			
		}
	}
}
Window_Event :: struct {
	type : enum u8 {
		NONE;
		MOUSE_BUTTON;
		KEY;
	};
	union {
		key_event : struct {
			keycode : s32;
			type : enum u8 { UNKNOWN; PRESS; HOLD; RELEASE; };
		};
		mouse_button_event : struct {
			button : s32;
			action : s32;
			mods : s32;
		};
	};
}

centerize_cursor :: () {
	cursor_position = .{window_metrics.width / 2., window_metrics.height / 2.};
	new_cursor_position = cursor_position;
	glfwSetCursorPos(backend_state.window, cursor_position.x, cursor_position.y);
}
lock_cursor :: () {
	glfwSetInputMode(window, GLFW_CURSOR, GLFW_CURSOR_DISABLED);
	is_cursor_locked = true;
	centerize_cursor();
}
unlock_cursor :: () {
	glfwSetInputMode(window, GLFW_CURSOR, GLFW_CURSOR_NORMAL);
	is_cursor_locked = false;
	centerize_cursor();
}
switch_cursor_lock :: () {
	glfwSetInputMode(window, GLFW_CURSOR, xx ifx is_cursor_locked then GLFW_CURSOR_NORMAL else GLFW_CURSOR_DISABLED);
	is_cursor_locked ^= true;
	centerize_cursor();
}
lmb_pressed :: () -> bool {
	return mouse_buttons_pressed[GLFW_MOUSE_BUTTON_LEFT];
}
lmb_released :: () -> bool {
	return mouse_buttons_released[GLFW_MOUSE_BUTTON_LEFT];
}
lmb_down :: () -> bool {
	return mouse_buttons_down[GLFW_MOUSE_BUTTON_LEFT];
}
// Mouse_State :: enum u8 { UP; PUSH; DOWN; RELEASE; }
backend_state : struct {
	window : *GLFWwindow;
	ctx : Context;

	is_cursor_locked := false;
	is_first_frame := true;
	window_resized_this_frame := false;

	new_cursor_position, cursor_position : Vector2;
	cursor_delta : Vector2;
	dragg_start : Vector2;

	window_events : SB_Queue(Window_Event, 100);
	mouse_buttons_down : [GLFW_MOUSE_BUTTON_LAST]bool;
	mouse_buttons_pressed : [GLFW_MOUSE_BUTTON_LAST] bool;
	mouse_buttons_released : [GLFW_MOUSE_BUTTON_LAST] bool;
	keys_down : [1024]bool;
	// left_mouse_state := Mouse_State.UP;

	// keys_events : [1024]bool;
	window_metrics : struct {
		width, height : s32;
		width_over_height : float;
		height_over_width : float;
		#place width;
		size : ivec2;
	}
	ubo_window_metrics : UBO;

	using time_info : struct {
		current_time : float;
		delta_time : float;
		target_delta_time : float;	
	}
	ubo_time_info : UBO;
};

refresh_window_size :: (width : s32, height : s32) #c_call {
	window_metrics.width = width;
	window_metrics.height = height;
	window_metrics.width_over_height = width / cast(float)height;
	window_metrics.height_over_width = height / cast(float)width;
}
#scope_file
using,except(delta_time) backend_state;
