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
	scene_translation := Matrix4_Identity;
}

// COLOR BINDINGS
// base_color 				0
// metallic_roughness 		1
// normal    				2
// occlusion 				3
// emissive  				4
// transmission 			5

Scene_Transformation :: struct {
	m : Matrix4;
}
translate :: (offset : Vector3) -> Scene_Transformation {
	return .{make_translation_matrix4(offset)};
}
scale :: (factor : Vector3) -> Scene_Transformation {
	return .{make_scale_matrix4(factor)};
}
scale :: (factor : float) -> Scene_Transformation {
	return scale(.{factor, factor, factor});
}
transformation :: (matrix4 : Matrix4) -> Scene_Transformation {
	return .{matrix4};
}

for_expansion :: (st : Scene_Transformation, $body : Code, flags : For_Flags) #expand {
	`it, `it_index := 0;
	old_translation := graphics_state.scene_translation;
	graphics_state.scene_translation = old_translation * st.m;
	defer graphics_state.scene_translation = old_translation;
	#insert body;
}
draw_node_p :: (using loaded_assets : Loaded_Assets, i : int) {
	draw_node(loaded_assets, i, graphics_state.scene_translation);
}

Model_Transformation :: struct {
	mat_m : Matrix4;
	center_position : Vector3;
}
init_default_graphics :: () {
	default_camera.screen_size = backend_state.window_metrics.size;
	ubo_default_camera = make_ubo_initialized(to_ubo_content(default_camera));
	bind(1, ubo_default_camera);

	ubo_model_transform = make_ubo_initialized(Model_Transformation.{Matrix4_Identity, .{}});
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
	set_value(*ubo_model_transform, Model_Transformation.{transpose(transform), (transform * Vector4.{0, 0, 0, 1}).xyz});
}

#scope_file
using graphics_state;