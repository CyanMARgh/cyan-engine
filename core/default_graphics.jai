graphics_state : struct {
	default_camera := Movable_Camera.{position = .{0, 0, 4}};

	// UBO BINDINGS
	// window_metrics (backend)	// 0
	ubo_default_camera : UBO;  	// 1
	ubo_model_transform : UBO; 	// 2
	// time_info  (backend)  	// 3
	// material -                 4
	// sun & main lights          5 

	empty_mesh : Mesh;
}

// COLOR BINDINGS
// base_color 				0
// metallic_roughness 		1
// normal    				2
// occlusion 				3
// emissive  				4
// transmission 			5


init_default_graphics :: () {
	default_camera.screen_size = backend_state.window_metrics.size;
	ubo_default_camera = make_ubo_initialized(to_ubo_content(default_camera));
	bind(1, ubo_default_camera);

	ubo_model_transform = make_ubo_initialized(Matrix4_Identity);
	bind(2, ubo_model_transform);
	
	empty_mesh = get_empty_mesh();
}
draw_empty_mesh :: (vertices : u32) {
	draw(empty_mesh, GL_TRIANGLES, vertices);
}
deinit_default_graphics :: () {
	deinit(*empty_mesh);
	deinit(*ubo_model_transform);
	deinit(*ubo_default_camera);
	graphics_state = .{};
}

update_default_camera :: (forced := false) {
	if forced || update_camera(*default_camera, backend_state.window_metrics.size, backend_state.is_cursor_locked) {
		set_value(*ubo_default_camera, to_ubo_content(default_camera));
	}
}

set_model_transform :: (transform : Matrix4) {
	set_value(*ubo_model_transform, transpose(transform));
}

#scope_file
using graphics_state;